import 'package:drift/drift.dart';

import '../../reminders/domain/reminder_models.dart';
import '../../reminders/domain/reminder_settings_repository.dart';
import '../domain/models.dart';
import '../domain/school_schedule.dart';
import 'app_database.dart';
import 'timetable_import.dart';
import 'sample_schedule.dart';
import 'import_time_plan.dart';

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
    return _watchCourses();
  }

  Stream<List<Course>> watchCoursesForSemester(String semesterId) {
    return _watchCourses(semesterId: semesterId);
  }

  Stream<List<Course>> _watchCourses({String? semesterId}) {
    final courseQuery = database.select(database.courseRows);
    if (semesterId != null) {
      courseQuery.where((row) => row.semesterId.equals(semesterId));
    }
    final query =
        courseQuery.join([
          leftOuterJoin(
            database.appMetadata,
            database.appMetadata.key.equals('school_schedule'),
          ),
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

    return query
        .watch()
        .distinct((before, after) {
          if (before.length != after.length) return false;
          for (var i = 0; i < before.length; i++) {
            if (before[i].readTable(database.courseRows) !=
                    after[i].readTable(database.courseRows) ||
                before[i].readTableOrNull(database.courseSessionRows) !=
                    after[i].readTableOrNull(database.courseSessionRows) ||
                before[i].readTableOrNull(database.appMetadata) !=
                    after[i].readTableOrNull(database.appMetadata)) {
              return false;
            }
          }
          return true;
        })
        .map((rows) {
          final courses = <String, Course>{};
          final scheduleData = rows.isEmpty
              ? null
              : rows.first.readTableOrNull(database.appMetadata)?.value;
          final schedule = scheduleData == null
              ? SchoolSchedule.defaults()
              : SchoolSchedule.decode(scheduleData);
          for (final row in rows) {
            final courseRow = row.readTable(database.courseRows);
            final sessionRow = row.readTableOrNull(database.courseSessionRows);
            final existing = courses[courseRow.id];
            final sessions = existing == null
                ? <CourseSession>[]
                : List<CourseSession>.of(existing.sessions);
            if (sessionRow != null) {
              sessions.add(
                schedule.resolve(
                  _sessionFromRow(sessionRow),
                  semesterId: courseRow.semesterId,
                ),
              );
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

  Stream<List<Semester>> watchSemesters() => database
      .select(database.semesterRows)
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => Semester(
                id: r.id,
                name: r.name,
                firstWeekStart: r.firstWeekStart,
                totalWeeks: r.totalWeeks,
              ),
            )
            .toList(),
      );

  Future<bool> hasConfiguredSemester() async {
    final flag = await (database.select(
      database.appMetadata,
    )..where((r) => r.key.equals('semester_configured'))).getSingleOrNull();
    if (flag?.value == 'true') return true;
    final terms = await database.select(database.semesterRows).get();
    if (terms.any((s) => s.id != sampleSemester.id)) return true;
    final imports = await (database.select(
      database.courseRows,
    )..where((r) => r.sourceType.equals(CourseSource.cdcasKingo.name))).get();
    return imports.isNotEmpty;
  }

  Future<void> activateSemester(String id) => database.transaction(() async {
    if (await (database.select(
          database.semesterRows,
        )..where((r) => r.id.equals(id))).getSingleOrNull() ==
        null) {
      throw const FormatException('课表不存在');
    }
    await database
        .update(database.semesterRows)
        .write(const SemesterRowsCompanion(isActive: Value(false)));
    await (database.update(database.semesterRows)
          ..where((r) => r.id.equals(id)))
        .write(const SemesterRowsCompanion(isActive: Value(true)));
    await _setMetadata('semester_configured', 'true');
  });

  Future<void> saveSemesterSchedule(String id, SchoolSchedule input) =>
      database.transaction(() async {
        final previous = await readSchoolSchedule();
        final next = previous.withSemesterSections(
          id,
          input.semesterSections[id] ?? input.sections,
          sectionCount: input.sectionCountFor(id),
          fixedLessonDuration: input.fixedLessonDurationFor(id),
          lessonMinutes: input.lessonMinutesFor(id),
          breakMinutes: input.breakMinutesFor(id),
          replaceRules: true,
        );
        await _validateStoredTimes(next);
        await _setMetadata('school_schedule', next.encode());
      });

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
    return query
        .watchSingleOrNull()
        .map((row) => row?.value == 'true')
        .distinct();
  }

  @override
  Stream<ReminderPreferences> watchReminderPreferences() {
    return database.select(database.appMetadata).watch().map((rows) {
      final values = {for (final row in rows) row.key: row.value};
      final leadMinutes = int.tryParse(values['reminder_lead_minutes'] ?? '');
      final soundName = values['reminder_sound'];
      return ReminderPreferences(
        enabled: values['reminders_enabled'] == 'true',
        leadMinutes: leadMinutes != null && leadMinutes >= 0 ? leadMinutes : 30,
        sound: RingtoneSelection.fromStorage(soundName),
        snoozeEnabled: values['reminder_snooze_enabled'] != 'false',
        vibration: VibrationSelection.fromStorage(values['reminder_vibration']),
        snoozeMinutes: _validOption(values['reminder_snooze_minutes'], const [
          5,
          10,
          15,
          30,
        ], 5),
        maxRings: _validOption(values['reminder_max_rings'], const [
          2,
          3,
          5,
          10,
        ], 2),
        holidaySilenceEnabled: values['holiday_silence_enabled'] != 'false',
      );
    });
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

  @override
  Future<void> setReminderLeadMinutes(int minutes) {
    if (minutes < 0) throw ArgumentError.value(minutes, 'minutes');
    return _setMetadata('reminder_lead_minutes', '$minutes');
  }

  @override
  Future<void> setReminderSound(RingtoneSelection sound) {
    return _setMetadata('reminder_sound', sound.storageValue);
  }

  @override
  Future<void> setReminderSnoozeEnabled(bool enabled) =>
      _setMetadata('reminder_snooze_enabled', '$enabled');
  @override
  Future<void> setReminderVibration(VibrationSelection vibration) =>
      _setMetadata('reminder_vibration', vibration.name);

  static int _validOption(String? value, List<int> allowed, int fallback) {
    final parsed = int.tryParse(value ?? '');
    return allowed.contains(parsed) ? parsed! : fallback;
  }

  @override
  Future<void> setReminderSnoozeMinutes(int minutes) {
    if (!const [5, 10, 15, 30].contains(minutes)) {
      throw ArgumentError.value(minutes);
    }
    return _setMetadata('reminder_snooze_minutes', '$minutes');
  }

  @override
  Future<void> setReminderMaxRings(int count) {
    if (!const [2, 3, 5, 10].contains(count)) throw ArgumentError.value(count);
    return _setMetadata('reminder_max_rings', '$count');
  }

  @override
  Future<void> setHolidaySilenceEnabled(bool enabled) =>
      _setMetadata('holiday_silence_enabled', '$enabled');

  Future<bool> readGridView() async {
    final row = await (database.select(
      database.appMetadata,
    )..where((r) => r.key.equals('grid_view'))).getSingleOrNull();
    return row?.value == 'true';
  }

  Stream<SchoolSchedule> watchSchoolSchedule() =>
      (database.select(database.appMetadata)
            ..where((r) => r.key.equals('school_schedule')))
          .watchSingleOrNull()
          .map((row) => row?.value)
          .distinct()
          .map(
            (value) => value == null
                ? SchoolSchedule.defaults()
                : SchoolSchedule.decode(value),
          );

  Future<SchoolSchedule> readSchoolSchedule() async {
    final row = await (database.select(
      database.appMetadata,
    )..where((r) => r.key.equals('school_schedule'))).getSingleOrNull();
    return row == null
        ? SchoolSchedule.defaults()
        : SchoolSchedule.decode(row.value);
  }

  Future<void> saveSchoolSchedule(SchoolSchedule schedule) =>
      database.transaction(() async {
        var merged = SchoolSchedule(
          id: schedule.id,
          sections: schedule.sections,
          prepPeriods: schedule.prepPeriods,
          rangeTimes: (await readSchoolSchedule()).rangeTimes,
          semesterSections: schedule.semesterSections,
          sectionCounts: schedule.sectionCounts,
          fixedLessonDuration: schedule.fixedLessonDuration,
          lessonMinutes: schedule.lessonMinutes,
          breakMinutes: schedule.breakMinutes,
        );
        for (final r in schedule.rangeTimes) {
          merged = merged.withRangeTime(r);
        }
        await _validateStoredTimes(merged);
        await _setMetadata('school_schedule', merged.encode());
      });

  Future<void> setGridView(bool value) => _setMetadata('grid_view', '$value');

  Future<void> _setMetadata(String key, String value) {
    return database
        .into(database.appMetadata)
        .insertOnConflictUpdate(
          AppMetadataCompanion.insert(key: key, value: value),
        );
  }

  Future<int> minimumSemesterWeeks(String semesterId) async {
    final ignored = await hasConfiguredSemester()
        ? <String>[]
        : await _unchangedSampleIds();
    final courses = await watchCoursesForSemester(semesterId).first;
    return courses
        .where((c) => !ignored.contains(c.id))
        .expand((c) => c.sessions)
        .fold<int>(1, (n, s) => n > s.endWeek ? n : s.endWeek);
  }

  Future<void> saveSemester(Semester semester, {bool makeActive = false}) {
    return database.transaction(() async {
      final previous = await (database.select(
        database.semesterRows,
      )..where((r) => r.id.equals(semester.id))).getSingleOrNull();
      final retainActive = makeActive || (previous?.isActive ?? false);
      if (semester.name.trim().isEmpty ||
          semester.totalWeeks < 1 ||
          semester.totalWeeks > 60 ||
          semester.firstWeekStart.weekday != DateTime.monday) {
        throw const FormatException('请核对学期名称、周数和第一周星期一');
      }
      // Only retire untouched demonstration data on the first setup. This is
      // transactional so a rejected change cannot delete edited user courses.
      if (!await hasConfiguredSemester()) {
        final sampleIds = await _unchangedSampleIds();
        if (sampleIds.isNotEmpty) {
          await (database.delete(
            database.courseRows,
          )..where((r) => r.id.isIn(sampleIds))).go();
        }
      }
      final sessions = await (database.select(database.courseSessionRows).join([
        innerJoin(
          database.courseRows,
          database.courseRows.id.equalsExp(database.courseSessionRows.courseId),
        ),
      ])..where(database.courseRows.semesterId.equals(semester.id))).get();
      var requiredWeeks = 1;
      for (final row in sessions) {
        final end = row.readTable(database.courseSessionRows).endWeek;
        if (end > requiredWeeks) requiredWeeks = end;
      }
      if (semester.totalWeeks < requiredWeeks) {
        throw FormatException(
          '已有课程安排到第 $requiredWeeks 周，学期总周数不能少于 $requiredWeeks 周。请先修改相关课程周次，再缩短学期。',
        );
      }
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
              isActive: Value(retainActive),
            ),
          );
      await _setMetadata('semester_configured', 'true');
    });
  }

  Future<void> saveCourse(
    Course course, {
    bool synchronizeTimes = true,
    CourseSession? timeToSynchronize,
  }) {
    if (course.sessions.isEmpty) {
      throw ArgumentError.value(
        course.sessions,
        'sessions',
        'must not be empty',
      );
    }
    return database.transaction(() async {
      if (synchronizeTimes) {
        var schedule = await readSchoolSchedule();
        final choices = <String, String>{};
        for (final s
            in timeToSynchronize == null
                ? course.sessions
                : [timeToSynchronize]) {
          if (s.timeSource == CourseTimeSource.custom &&
              s.startMinute != null &&
              s.endMinute != null) {
            final key = '${s.startSection}:${s.endSection}';
            if (choices[key] != null && choices[key] != s.timeLabel) {
              throw const FormatException('同节次有多个手动时间，请明确选择要同步的时段。');
            }
            choices[key] = s.timeLabel!;
            schedule = schedule.withRangeTime(
              SectionRangeTime(
                semesterId: course.semesterId,
                startSection: s.startSection,
                endSection: s.endSection,
                startMinute: s.startMinute!,
                endMinute: s.endMinute!,
                source: CourseTimeSource.custom,
              ),
            );
          }
        }
        await _setMetadata('school_schedule', schedule.encode());
      }
      await _saveCourse(course);
      await _validateStoredTimes(await readSchoolSchedule());
    });
  }

  Future<ImportSummary> importTimetable(ImportPreview preview) {
    if (preview.courses.isEmpty) {
      throw ArgumentError('courses must not be empty');
    }
    if (preview.semester.totalWeeks < 1 ||
        preview.semester.totalWeeks > 60 ||
        preview.courses.any(
          (c) => c.sessions.any((s) => s.endWeek > preview.semester.totalWeeks),
        )) {
      throw const FormatException('课程周次超出学期，请先调整学期总周数再导入。');
    }
    return database.transaction(() async {
      final plan = ImportTimePlan(
        preview,
        await readSchoolSchedule(),
        existingTimes: await readUnsharedTimes(preview.semester.id),
      );
      if (plan.invalidKeys.isNotEmpty) {
        throw const FormatException('部分时间无法与作息匹配，请补全开始和结束时间。');
      }
      if (plan.conflicts.isNotEmpty) {
        throw const FormatException('同节次时间存在冲突，请在预览中选择时间后导入。');
      }
      await _setMetadata('school_schedule', plan.schedule.encode());
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
          id:
              existing?.id ??
              'cdcas-${preview.semester.id}-${course.externalId}',
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

      final staleIds = (preview.replaceExisting ? importedRows : <CourseRow>[])
          .map((row) => row.id)
          .where((id) => !retainedIds.contains(id))
          .toList(growable: false);
      if (staleIds.isNotEmpty) {
        await (database.delete(
          database.courseRows,
        )..where((row) => row.id.isIn(staleIds))).go();
      }
      final sampleIds = await _unchangedSampleIds();
      if (sampleIds.isNotEmpty) {
        await (database.delete(
          database.courseRows,
        )..where((row) => row.id.isIn(sampleIds))).go();
      }
      await _retireEmptySampleSemester();

      // Retained manual courses must also fit when replacing imported courses.
      await saveSemester(preview.semester, makeActive: true);
      await _validateStoredTimes(plan.schedule);

      return ImportSummary(
        inserted: inserted,
        updated: updated,
        removed: staleIds.length + sampleIds.length,
        warnings: List.unmodifiable(preview.warnings),
      );
    });
  }

  Future<ImportSummary> previewTimetableImport(ImportPreview preview) async {
    if (preview.courses.isEmpty) {
      throw ArgumentError('courses must not be empty');
    }
    final importedRows =
        await (database.select(database.courseRows)..where(
              (row) =>
                  row.semesterId.equals(preview.semester.id) &
                  row.sourceType.equals(CourseSource.cdcasKingo.name),
            ))
            .get();
    final existingByExternalId = <String, Course>{};
    for (final row in importedRows) {
      if (row.externalId != null) {
        existingByExternalId[row.externalId!] = await _courseFromRow(row);
      }
    }
    var inserted = 0;
    var updated = 0;
    final retained = <String>{};
    for (final course in preview.courses) {
      final externalId = course.externalId;
      if (externalId == null || externalId.isEmpty) {
        throw ArgumentError('imported courses require externalId');
      }
      retained.add(externalId);
      final existing = existingByExternalId[externalId];
      if (existing == null) {
        inserted++;
      } else {
        final normalized = Course(
          id: existing.id,
          semesterId: preview.semester.id,
          source: CourseSource.cdcasKingo,
          externalId: externalId,
          name: course.name,
          teacher: course.teacher,
          colorValue: course.colorValue,
          sessions: course.sessions,
        );
        if (!_sameCourse(existing, normalized)) updated++;
      }
    }
    final sampleIds = await _unchangedSampleIds();
    return ImportSummary(
      inserted: inserted,
      updated: updated,
      removed:
          sampleIds.length +
          (preview.replaceExisting
              ? existingByExternalId.keys
                    .where((id) => !retained.contains(id))
                    .length
              : 0),
      warnings: List.unmodifiable(preview.warnings),
    );
  }

  Future<void> _saveCourse(Course course) async {
    final savedSchedule = await (database.select(
      database.appMetadata,
    )..where((r) => r.key.equals('school_schedule'))).getSingleOrNull();
    final schedule = savedSchedule == null
        ? SchoolSchedule.defaults()
        : SchoolSchedule.decode(savedSchedule.value);
    for (final session in course.sessions) {
      final effective = schedule.resolve(
        session,
        semesterId: course.semesterId,
      );
      if (effective.startMinute == null || effective.endMinute == null) {
        throw const FormatException('该节次缺少完整作息，请填写开始和结束时间。');
      }
    }
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
                startMinute: Value(
                  session.timeSource != CourseTimeSource.schedule
                      ? session.startMinute
                      : null,
                ),
                endMinute: Value(
                  session.timeSource != CourseTimeSource.schedule
                      ? session.endMinute
                      : null,
                ),
                timeSource: Value(session.timeSource.name),
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
      await _migrateLegacyTimes();
      final seeded = await (database.select(
        database.appMetadata,
      )..where((row) => row.key.equals('sample_seed_v1'))).getSingleOrNull();
      if (seeded == null) {
        final existing = await database.select(database.courseRows).get();
        if (existing.isEmpty) {
          await saveSemester(sampleSemester, makeActive: true);
          await _setMetadata('semester_configured', 'false');
          for (final course in sampleCourses) {
            await _saveCourse(course);
          }
        }
        await database
            .into(database.appMetadata)
            .insert(
              AppMetadataCompanion.insert(key: 'sample_seed_v1', value: 'done'),
            );
      }
      final imported =
          await (database.select(database.courseRows)..where(
                (row) => row.sourceType.equals(CourseSource.cdcasKingo.name),
              ))
              .get();
      if (imported.isNotEmpty) {
        final sampleIds = await _unchangedSampleIds();
        if (sampleIds.isNotEmpty) {
          await (database.delete(
            database.courseRows,
          )..where((row) => row.id.isIn(sampleIds))).go();
        }
        await _retireEmptySampleSemester();
      }
    });
  }

  Future<List<String>> _unchangedSampleIds() async {
    final ids = sampleCourses.map((course) => course.id).toList();
    final rows = await (database.select(
      database.courseRows,
    )..where((row) => row.id.isIn(ids))).get();
    final samples = {for (final course in sampleCourses) course.id: course};
    final matches = <String>[];
    for (final row in rows) {
      final original = samples[row.id];
      if (original != null &&
          row.semesterId == sampleSemester.id &&
          row.sourceType == CourseSource.manual.name &&
          _sameCourse(await _courseFromRow(row), original)) {
        matches.add(row.id);
      }
    }
    return matches;
  }

  Future<void> _migrateLegacyTimes() async {
    final migrated = await (database.select(
      database.appMetadata,
    )..where((r) => r.key.equals('shared_times_v1'))).getSingleOrNull();
    if (migrated != null) return;
    var schedule = await readSchoolSchedule();
    final groups = <String, List<SectionRangeTime>>{};
    for (final c in await database.select(database.courseRows).get()) {
      final course = await _courseFromRow(c);
      for (final s in course.sessions) {
        if (s.timeSource != CourseTimeSource.custom) continue;
        final resolved = schedule.resolve(s);
        if (resolved.startMinute == null || resolved.endMinute == null) {
          continue;
        }
        final r = SectionRangeTime(
          semesterId: c.semesterId,
          startSection: s.startSection,
          endSection: s.endSection,
          startMinute: resolved.startMinute!,
          endMinute: resolved.endMinute!,
          source: CourseTimeSource.custom,
        );
        final group = groups.putIfAbsent(r.key, () => []);
        if (!group.any(
          (v) => v.startMinute == r.startMinute && v.endMinute == r.endMinute,
        )) {
          group.add(r);
        }
      }
    }
    for (final group in groups.values) {
      final r = group.first;
      // Competing legacy edits are retained until an explicit time edit resolves them.
      if (group.length == 1 &&
          schedule.range(r.semesterId, r.startSection, r.endSection) == null) {
        schedule = schedule.withRangeTime(r);
      }
    }
    await _setMetadata('school_schedule', schedule.encode());
    await _setMetadata('shared_times_v1', 'done');
  }

  Future<void> migrateLegacyTimes() =>
      database.transaction(_migrateLegacyTimes);

  Future<void> _validateStoredTimes(SchoolSchedule schedule) async {
    for (final row in await database.select(database.courseRows).get()) {
      for (final s in (await _courseFromRow(row)).sessions) {
        if (schedule.sectionCounts.containsKey(row.semesterId) &&
            s.endSection > schedule.sectionCountFor(row.semesterId)) {
          throw FormatException('第${s.endSection}节仍有课程使用，请先调整课程后再删除节次。');
        }
        final time = schedule.resolve(s, semesterId: row.semesterId);
        if (time.startMinute == null || time.endMinute == null) {
          throw const FormatException('现有课程缺少完整作息，请补齐后保存。');
        }
      }
    }
  }

  Future<List<SectionRangeTime>> readUnsharedTimes(String semesterId) async {
    final schedule = await readSchoolSchedule();
    final result = <SectionRangeTime>[];
    final rows = await (database.select(
      database.courseRows,
    )..where((r) => r.semesterId.equals(semesterId))).get();
    for (final row in rows) {
      for (final s in (await _courseFromRow(row)).sessions) {
        if (s.timeSource == CourseTimeSource.schedule ||
            schedule.range(semesterId, s.startSection, s.endSection) != null) {
          continue;
        }
        final time = schedule.resolve(s);
        if (time.startMinute != null && time.endMinute != null) {
          result.add(
            SectionRangeTime(
              semesterId: semesterId,
              startSection: s.startSection,
              endSection: s.endSection,
              startMinute: time.startMinute!,
              endMinute: time.endMinute!,
              source: s.timeSource,
            ),
          );
        }
      }
    }
    return result;
  }

  Future<void> _retireEmptySampleSemester() async {
    final sampleRow = await (database.select(
      database.semesterRows,
    )..where((row) => row.id.equals(sampleSemester.id))).getSingleOrNull();
    if (sampleRow == null ||
        sampleRow.isActive ||
        sampleRow.name != sampleSemester.name ||
        sampleRow.totalWeeks != sampleSemester.totalWeeks ||
        sampleRow.firstWeekStart.year != sampleSemester.firstWeekStart.year ||
        sampleRow.firstWeekStart.month != sampleSemester.firstWeekStart.month ||
        sampleRow.firstWeekStart.day != sampleSemester.firstWeekStart.day) {
      return;
    }
    final remaining = await (database.select(
      database.courseRows,
    )..where((row) => row.semesterId.equals(sampleSemester.id))).get();
    if (remaining.isEmpty) {
      await (database.delete(
        database.semesterRows,
      )..where((row) => row.id.equals(sampleSemester.id))).go();
    }
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
      startMinute: row.startMinute,
      endMinute: row.endMinute,
      timeSource: CourseTimeSource.values.byName(row.timeSource),
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
      '${session.room}|${session.timeSource.name}|'
      '${session.timeSource != CourseTimeSource.schedule ? session.startMinute : null}|'
      '${session.timeSource != CourseTimeSource.schedule ? session.endMinute : null}';
}
