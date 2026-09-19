import 'package:drift/drift.dart';

import '../../reminders/domain/reminder_settings_repository.dart';
import '../domain/models.dart';
import 'app_database.dart';
import 'cdcas_kingo_importer.dart';
import 'sample_schedule.dart';

class ImportSummary {
  const ImportSummary({
    required this.inserted,
    required this.updated,
    required this.removed,
    required this.warnings,
  });

  final int inserted;
  final int updated;
  final int removed;
  final List<String> warnings;
}

class CourseRepository implements ReminderSettingsRepository {
  CourseRepository(this.database);

  final AppDatabase database;

  Stream<List<Course>> watchCourses() {
    final query =
        database.select(database.courseRows).join([
          leftOuterJoin(
            database.courseSessionRows,
            database.courseSessionRows.courseId.equalsExp(
              database.courseRows.id,
            ),
          ),
        ])..orderBy([
          OrderingTerm.asc(database.courseSessionRows.weekday),
          OrderingTerm.asc(database.courseSessionRows.startSection),
        ]);

    return query.watch().map((rows) {
      final courses = <String, Course>{};
      for (final row in rows) {
        final courseRow = row.readTable(database.courseRows);
        final sessionRow = row.readTableOrNull(database.courseSessionRows);
        final existing = courses[courseRow.id];
        final sessions = existing == null
            ? <CourseSession>[]
            : List<CourseSession>.of(existing.sessions);
        if (sessionRow != null) {
          sessions.add(_sessionFromRow(sessionRow));
        }
        courses[courseRow.id] = Course(
          id: courseRow.id,
          semesterId: courseRow.semesterId,
          source: CourseSource.values.byName(courseRow.sourceType),
          externalId: courseRow.externalId,
          name: courseRow.name,
          teacher: courseRow.teacher,
          colorValue: courseRow.colorValue,
          sessions: sessions,
        );
      }
      return courses.values.toList(growable: false);
    });
  }

  Stream<Semester> watchActiveSemester() {
    final query = database.select(database.semesterRows)
      ..where((row) => row.isActive.equals(true));
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? sampleSemester
          : Semester(
              id: row.id,
              name: row.name,
              firstWeekStart: row.firstWeekStart,
              totalWeeks: row.totalWeeks,
            ),
    );
  }

  @override
  Stream<bool> watchRemindersEnabled() {
    final query = database.select(database.appMetadata)
      ..where((row) => row.key.equals('reminders_enabled'));
    return query.watchSingleOrNull().map((row) => row?.value == 'true');
  }

  @override
  Future<void> setRemindersEnabled(bool enabled) {
    return database
        .into(database.appMetadata)
        .insertOnConflictUpdate(
          AppMetadataCompanion.insert(
            key: 'reminders_enabled',
            value: enabled.toString(),
          ),
        );
  }

  Future<void> saveSemester(Semester semester, {bool makeActive = false}) {
    return database.transaction(() async {
      if (makeActive) {
        await database
            .update(database.semesterRows)
            .write(const SemesterRowsCompanion(isActive: Value(false)));
      }
      await database
          .into(database.semesterRows)
          .insertOnConflictUpdate(
            SemesterRowsCompanion.insert(
              id: semester.id,
              name: semester.name,
              firstWeekStart: semester.firstWeekStart,
              totalWeeks: semester.totalWeeks,
              isActive: Value(makeActive),
            ),
          );
    });
  }

  Future<void> saveCourse(Course course) {
    if (course.sessions.isEmpty) {
      throw ArgumentError.value(
        course.sessions,
        'sessions',
        'must not be empty',
      );
    }
    return database.transaction(() => _saveCourse(course));
  }

  Future<ImportSummary> importTimetable(ImportPreview preview) {
    if (preview.courses.isEmpty) {
      throw ArgumentError('courses must not be empty');
    }
    return database.transaction(() async {
      await database
          .update(database.semesterRows)
          .write(const SemesterRowsCompanion(isActive: Value(false)));
      await database
          .into(database.semesterRows)
          .insertOnConflictUpdate(
            SemesterRowsCompanion.insert(
              id: preview.semester.id,
              name: preview.semester.name,
              firstWeekStart: preview.semester.firstWeekStart,
              totalWeeks: preview.semester.totalWeeks,
              isActive: const Value(true),
            ),
          );

      final importedRows =
          await (database.select(database.courseRows)..where(
                (row) =>
                    row.semesterId.equals(preview.semester.id) &
                    row.sourceType.equals(CourseSource.cdcasKingo.name),
              ))
              .get();
      final existingByExternalId = <String, Course>{};
      for (final row in importedRows) {
        if (row.externalId == null) continue;
        existingByExternalId[row.externalId!] = await _courseFromRow(row);
      }

      var inserted = 0;
      var updated = 0;
      final retainedIds = <String>{};
      for (final course in preview.courses) {
        if (course.source != CourseSource.cdcasKingo ||
            course.externalId == null ||
            course.externalId!.isEmpty) {
          throw ArgumentError(
            'imported courses require cdcasKingo source and externalId',
          );
        }
        final existing = existingByExternalId[course.externalId!];
        final normalized = Course(
          id: existing?.id ?? course.id,
          semesterId: preview.semester.id,
          source: CourseSource.cdcasKingo,
          externalId: course.externalId,
          name: course.name,
          teacher: course.teacher,
          colorValue: course.colorValue,
          sessions: course.sessions,
        );
        retainedIds.add(normalized.id);
        if (existing == null) {
          inserted++;
          await _saveCourse(normalized);
        } else if (!_sameCourse(existing, normalized)) {
          updated++;
          await _saveCourse(normalized);
        }
      }

      final staleIds = importedRows
          .map((row) => row.id)
          .where((id) => !retainedIds.contains(id))
          .toList(growable: false);
      if (staleIds.isNotEmpty) {
        await (database.delete(
          database.courseRows,
        )..where((row) => row.id.isIn(staleIds))).go();
      }

      return ImportSummary(
        inserted: inserted,
        updated: updated,
        removed: staleIds.length,
        warnings: List.unmodifiable(preview.warnings),
      );
    });
  }

  Future<void> _saveCourse(Course course) async {
    await database
        .into(database.courseRows)
        .insertOnConflictUpdate(
          CourseRowsCompanion.insert(
            id: course.id,
            semesterId: Value(course.semesterId),
            sourceType: Value(course.source.name),
            externalId: Value(course.externalId),
            name: course.name,
            teacher: Value(course.teacher),
            colorValue: course.colorValue,
          ),
        );
    await (database.delete(
      database.courseSessionRows,
    )..where((row) => row.courseId.equals(course.id))).go();
    await database.batch((batch) {
      batch.insertAll(
        database.courseSessionRows,
        course.sessions
            .map(
              (session) => CourseSessionRowsCompanion.insert(
                courseId: course.id,
                weekday: session.weekday,
                startSection: session.startSection,
                endSection: session.endSection,
                startWeek: session.startWeek,
                endWeek: session.endWeek,
                pattern: session.pattern.name,
                room: session.room,
              ),
            )
            .toList(growable: false),
      );
    });
  }

  Future<void> deleteCourse(String id) {
    return (database.delete(
      database.courseRows,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<void> seedIfEmpty() {
    return database.transaction(() async {
      final seeded = await (database.select(
        database.appMetadata,
      )..where((row) => row.key.equals('sample_seed_v1'))).getSingleOrNull();
      if (seeded != null) return;

      final existing = await database
          .select(database.courseRows)
          .getSingleOrNull();
      if (existing == null) {
        await saveSemester(sampleSemester, makeActive: true);
        for (final course in sampleCourses) {
          await _saveCourse(course);
        }
      }
      await database
          .into(database.appMetadata)
          .insert(
            AppMetadataCompanion.insert(key: 'sample_seed_v1', value: 'done'),
          );
    });
  }

  CourseSession _sessionFromRow(CourseSessionRow row) {
    return CourseSession(
      weekday: row.weekday,
      startSection: row.startSection,
      endSection: row.endSection,
      startWeek: row.startWeek,
      endWeek: row.endWeek,
      pattern: WeekPattern.values.byName(row.pattern),
      room: row.room,
    );
  }

  Future<Course> _courseFromRow(CourseRow row) async {
    final sessionRows = await (database.select(
      database.courseSessionRows,
    )..where((session) => session.courseId.equals(row.id))).get();
    return Course(
      id: row.id,
      semesterId: row.semesterId,
      source: CourseSource.values.byName(row.sourceType),
      externalId: row.externalId,
      name: row.name,
      teacher: row.teacher,
      colorValue: row.colorValue,
      sessions: sessionRows.map(_sessionFromRow).toList(growable: false),
    );
  }

  bool _sameCourse(Course left, Course right) {
    if (left.id != right.id ||
        left.semesterId != right.semesterId ||
        left.source != right.source ||
        left.externalId != right.externalId ||
        left.name != right.name ||
        left.teacher != right.teacher ||
        left.colorValue != right.colorValue ||
        left.sessions.length != right.sessions.length) {
      return false;
    }
    final leftSessions = left.sessions.map(_sessionKey).toList()..sort();
    final rightSessions = right.sessions.map(_sessionKey).toList()..sort();
    for (var index = 0; index < leftSessions.length; index++) {
      if (leftSessions[index] != rightSessions[index]) return false;
    }
    return true;
  }

  String _sessionKey(CourseSession session) =>
      '${session.weekday}|${session.startSection}|${session.endSection}|'
      '${session.startWeek}|${session.endWeek}|${session.pattern.name}|'
      '${session.room}';
}
