import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../../../reminders/domain/reminder_models.dart';
import '../../domain/school_schedule.dart';
import '../course_repository.dart';
import '../app_database.dart';

const _reminderKeys = <String>{
  'reminders_enabled',
  'reminder_lead_minutes',
  'reminder_sound',
  'reminder_snooze_minutes',
  'reminder_snooze_enabled',
  'reminder_vibration',
  'reminder_max_rings',
  'holiday_silence_enabled',
};

class ValidatedTimetableBackup {
  const ValidatedTimetableBackup({
    required this.semesters,
    required this.activeSemesterId,
    required this.courses,
    required this.schoolSchedule,
    required this.reminderPreferences,
    required this.warnings,
  });

  final List<Semester> semesters;
  final String activeSemesterId;
  final List<Course> courses;
  final SchoolSchedule schoolSchedule;
  final Map<String, String> reminderPreferences;
  final List<String> warnings;
}

class BackupRestorePreview {
  const BackupRestorePreview(this.backup);

  final ValidatedTimetableBackup backup;
  int get semesterCount => backup.semesters.length;
  int get courseCount => backup.courses.length;
  List<String> get warnings => backup.warnings;
}

class BackupDiff {
  const BackupDiff({
    required this.added,
    required this.replaced,
    required this.removed,
    required this.currentCourseCount,
  });

  final int added;
  final int replaced;
  final int removed;
  final int currentCourseCount;
}

class TimetableBackupService {
  const TimetableBackupService(this.database);

  final AppDatabase database;

  Future<BackupDiff> compare(ValidatedTimetableBackup backup) async {
    final current = await database.select(database.courseRows).get();
    final currentIds = current.map((course) => course.id).toSet();
    final incomingIds = backup.courses.map((course) => course.id).toSet();
    return BackupDiff(
      added: incomingIds.difference(currentIds).length,
      replaced: incomingIds.intersection(currentIds).length,
      removed: currentIds.difference(incomingIds).length,
      currentCourseCount: currentIds.length,
    );
  }

  Future<String> exportJson() => database.transaction(() async {
    final semesters = await database.select(database.semesterRows).get();
    final courses = await database.select(database.courseRows).get();
    final sessions = await database.select(database.courseSessionRows).get();
    final metadata = await database.select(database.appMetadata).get();
    final values = {for (final row in metadata) row.key: row.value};
    return jsonEncode({
      'format': 'qinghe-timetable-backup',
      'majorVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'activeSemesterId': semesters
          .where((semester) => semester.isActive)
          .firstOrNull
          ?.id,
      'semesters': [
        for (final semester in semesters)
          {
            'id': semester.id,
            'name': semester.name,
            'firstWeekStart': semester.firstWeekStart.toIso8601String(),
            'totalWeeks': semester.totalWeeks,
          },
      ],
      'courses': [
        for (final course in courses)
          {
            'id': course.id,
            'semesterId': course.semesterId,
            'source': course.sourceType,
            'externalId': course.externalId,
            'name': course.name,
            'teacher': course.teacher,
            'colorValue': course.colorValue,
            'sessions': [
              for (final session in sessions.where(
                (row) => row.courseId == course.id,
              ))
                {
                  'weekday': session.weekday,
                  'startSection': session.startSection,
                  'endSection': session.endSection,
                  'startWeek': session.startWeek,
                  'endWeek': session.endWeek,
                  'pattern': session.pattern,
                  'room': session.room,
                  'startMinute': session.startMinute,
                  'endMinute': session.endMinute,
                  'timeSource': session.timeSource,
                },
            ],
          },
      ],
      'schoolSchedule': jsonDecode(
        values['school_schedule'] ?? SchoolSchedule.defaults().encode(),
      ),
      'reminderPreferences': {
        for (final key in _reminderKeys)
          if (values.containsKey(key)) key: values[key],
      },
    });
  });

  BackupRestorePreview previewRestore(String source) {
    try {
      final data = _map(jsonDecode(source));
      if (data['format'] != 'qinghe-timetable-backup' ||
          data['majorVersion'] != 1) {
        throw const FormatException('备份格式或版本不受支持。');
      }
      if (DateTime.tryParse(_string(data['createdAt'])) == null) {
        throw const FormatException('备份创建时间无效。');
      }
      final semesterData = _list(data['semesters']);
      final semesters = [
        for (final value in semesterData)
          (() {
            final item = _map(value);
            final date = DateTime.tryParse(_string(item['firstWeekStart']));
            final weeks = _integer(item['totalWeeks']);
            if (date == null || weeks < 1 || weeks > 60) {
              throw const FormatException('备份中的学期日期或总周数无效。');
            }
            return Semester(
              id: _nonEmpty(item['id']),
              name: _nonEmpty(item['name']),
              firstWeekStart: date,
              totalWeeks: weeks,
            );
          })(),
      ];
      final semesterById = {
        for (final semester in semesters) semester.id: semester,
      };
      final activeId = _nonEmpty(data['activeSemesterId']);
      if (semesters.isEmpty ||
          semesterById.length != semesters.length ||
          !semesterById.containsKey(activeId)) {
        throw const FormatException('备份中的学期或当前学期引用无效。');
      }
      final schedule = SchoolSchedule.decode(
        jsonEncode(_map(data['schoolSchedule'])),
      );
      final courses = <Course>[];
      for (final value in _list(data['courses'])) {
        final item = _map(value);
        final semesterId = _nonEmpty(item['semesterId']);
        final semester = semesterById[semesterId];
        if (semester == null) throw const FormatException('课程引用了不存在的学期。');
        final sessions = <CourseSession>[];
        for (final sourceSession in _list(item['sessions'])) {
          final session = _map(sourceSession);
          final weekday = _integer(session['weekday']);
          final startSection = _integer(session['startSection']);
          final endSection = _integer(session['endSection']);
          final startWeek = _integer(session['startWeek']);
          final endWeek = _integer(session['endWeek']);
          final startMinute = _nullableInteger(session['startMinute']);
          final endMinute = _nullableInteger(session['endMinute']);
          final timeSource = CourseTimeSource.values.byName(
            _string(session['timeSource']),
          );
          if (weekday < 1 ||
              weekday > 7 ||
              startSection < 1 ||
              endSection < startSection ||
              endSection > 30 ||
              startWeek < 1 ||
              endWeek < startWeek ||
              endWeek > semester.totalWeeks ||
              (timeSource == CourseTimeSource.schedule &&
                  endSection > schedule.sectionCountFor(semesterId)) ||
              (timeSource != CourseTimeSource.schedule &&
                  ((startMinute == null && endMinute == null) ||
                      (startMinute != null &&
                          (startMinute < 0 || startMinute > 1439)) ||
                      (endMinute != null &&
                          (endMinute < 0 || endMinute > 1439)) ||
                      (startMinute != null &&
                          endMinute != null &&
                          endMinute <= startMinute)))) {
            throw const FormatException('备份中的课程节次、周次或时间无效。');
          }
          sessions.add(
            CourseSession(
              weekday: weekday,
              startSection: startSection,
              endSection: endSection,
              startWeek: startWeek,
              endWeek: endWeek,
              pattern: WeekPattern.values.byName(_string(session['pattern'])),
              room: _string(session['room']),
              startMinute: timeSource != CourseTimeSource.schedule
                  ? startMinute
                  : null,
              endMinute: timeSource != CourseTimeSource.schedule
                  ? endMinute
                  : null,
              timeSource: timeSource,
            ),
          );
        }
        if (sessions.isEmpty) throw const FormatException('备份中的课程缺少上课时段。');
        final name = _nonEmpty(item['name']);
        if (name.length > 80) throw const FormatException('备份中的课程名称过长。');
        courses.add(
          Course(
            id: _nonEmpty(item['id']),
            semesterId: semesterId,
            source: CourseSource.values.byName(_string(item['source'])),
            externalId: item['externalId'] == null
                ? null
                : _string(item['externalId']),
            name: name,
            teacher: _string(item['teacher']),
            colorValue: _integer(item['colorValue']),
            sessions: List.unmodifiable(sessions),
          ),
        );
      }
      if (courses.map((course) => course.id).toSet().length != courses.length) {
        throw const FormatException('备份包含重复课程标识。');
      }
      final reminderData = _map(data['reminderPreferences']);
      if (reminderData.keys.any((key) => !_reminderKeys.contains(key))) {
        throw const FormatException('备份包含未知的提醒设置。');
      }
      final preferences = <String, String>{
        for (final entry in reminderData.entries)
          entry.key: _string(entry.value),
      };
      _validateReminderPreferences(preferences);
      final warnings = <String>[];
      if ((preferences['reminder_sound'] ?? '').startsWith('local|')) {
        preferences['reminder_sound'] = 'systemDefault';
        warnings.add('原设备导入的本地铃声无法随 JSON 备份迁移，已改为系统默认铃声。');
      }
      return BackupRestorePreview(
        ValidatedTimetableBackup(
          semesters: List.unmodifiable(semesters),
          activeSemesterId: activeId,
          courses: List.unmodifiable(courses),
          schoolSchedule: schedule,
          reminderPreferences: Map.unmodifiable(preferences),
          warnings: List.unmodifiable(warnings),
        ),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份文件损坏或字段无效，现有课表未更改。');
    }
  }

  Future<void> restore(ValidatedTimetableBackup backup) async {
    await database.transaction(() async {
      await database.delete(database.courseSessionRows).go();
      await database.delete(database.courseRows).go();
      await database.delete(database.semesterRows).go();
      await (database.delete(database.appMetadata)..where(
            (row) => row.key.isIn({..._reminderKeys, 'school_schedule'}),
          ))
          .go();
      for (final semester in backup.semesters) {
        await database
            .into(database.semesterRows)
            .insert(
              SemesterRowsCompanion.insert(
                id: semester.id,
                name: semester.name,
                firstWeekStart: semester.firstWeekStart,
                totalWeeks: semester.totalWeeks,
                isActive: Value(semester.id == backup.activeSemesterId),
              ),
            );
      }
      await database
          .into(database.appMetadata)
          .insertOnConflictUpdate(
            AppMetadataCompanion.insert(
              key: 'school_schedule',
              value: backup.schoolSchedule.encode(),
            ),
          );
      await database
          .into(database.appMetadata)
          .insertOnConflictUpdate(
            AppMetadataCompanion.insert(key: 'sample_seed_v1', value: 'done'),
          );
      await database
          .into(database.appMetadata)
          .insertOnConflictUpdate(
            AppMetadataCompanion.insert(
              key: 'semester_configured',
              value: 'true',
            ),
          );
      for (final course in backup.courses) {
        await database
            .into(database.courseRows)
            .insert(
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
        for (final session in course.sessions) {
          await database
              .into(database.courseSessionRows)
              .insert(
                CourseSessionRowsCompanion.insert(
                  courseId: course.id,
                  weekday: session.weekday,
                  startSection: session.startSection,
                  endSection: session.endSection,
                  startWeek: session.startWeek,
                  endWeek: session.endWeek,
                  pattern: session.pattern.name,
                  room: session.room,
                  startMinute: Value(session.startMinute),
                  endMinute: Value(session.endMinute),
                  timeSource: Value(session.timeSource.name),
                ),
              );
        }
      }
      for (final entry in backup.reminderPreferences.entries) {
        await database
            .into(database.appMetadata)
            .insertOnConflictUpdate(
              AppMetadataCompanion.insert(key: entry.key, value: entry.value),
            );
      }
      await (database.delete(
        database.appMetadata,
      )..where((r) => r.key.equals('shared_times_v1'))).go();
      await CourseRepository(database).migrateLegacyTimes();
    });
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('备份文件结构无效。');
  }

  List<dynamic> _list(Object? value) {
    if (value is List) return value;
    throw const FormatException('备份文件列表字段无效。');
  }

  String _string(Object? value) {
    if (value is String) return value;
    throw const FormatException('备份文件文字字段无效。');
  }

  String _nonEmpty(Object? value) {
    final result = _string(value);
    if (result.trim().isEmpty) throw const FormatException('备份文件缺少必要字段。');
    return result;
  }

  int _integer(Object? value) {
    if (value is int) return value;
    throw const FormatException('备份文件数字字段无效。');
  }

  int? _nullableInteger(Object? value) =>
      value == null ? null : _integer(value);

  void _validateReminderPreferences(Map<String, String> preferences) {
    for (final key in [
      'reminders_enabled',
      'holiday_silence_enabled',
      'reminder_snooze_enabled',
    ]) {
      final value = preferences[key];
      if (value != null && value != 'true' && value != 'false') {
        throw const FormatException('备份中的提醒开关无效。');
      }
    }
    final lead = preferences['reminder_lead_minutes'];
    final leadMinutes = lead == null ? null : int.tryParse(lead);
    if (lead != null &&
        (leadMinutes == null || leadMinutes < 0 || leadMinutes > 1440)) {
      throw const FormatException('备份中的提前提醒时间无效。');
    }
    for (final (key, allowed) in [
      ('reminder_snooze_minutes', <int>{5, 10, 15, 30}),
      ('reminder_max_rings', <int>{2, 3, 5, 10}),
    ]) {
      final value = preferences[key];
      if (value != null && !allowed.contains(int.tryParse(value))) {
        throw const FormatException('备份中的提醒重复设置无效。');
      }
    }
    final vibration = preferences['reminder_vibration'];
    if (vibration != null &&
        !VibrationSelection.values.any((item) => item.name == vibration)) {
      throw const FormatException('备份中的振动设置无效。');
    }
    final sound = preferences['reminder_sound'];
    if (sound != null && sound.trim().isEmpty) {
      throw const FormatException('备份中的提醒铃声无效。');
    }
  }
}
