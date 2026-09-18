import 'package:drift/drift.dart';

import '../domain/models.dart';
import 'app_database.dart';
import 'sample_schedule.dart';

class CourseRepository {
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

  Future<void> saveSemester(Semester semester, {bool makeActive = false}) {
    return database.transaction(() async {
      if (makeActive) {
        await database.update(database.semesterRows).write(
          const SemesterRowsCompanion(isActive: Value(false)),
        );
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
}
