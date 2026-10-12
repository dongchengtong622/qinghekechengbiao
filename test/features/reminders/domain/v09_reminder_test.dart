import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_planner.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  test('no ringtone restores silence instead of default alarm audio', () {
    expect(RingtoneSelection.fromStorage('none').id, 'none');
  });
  test('old selections remain and new alarm preferences persist', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = CourseRepository(db);
    await repo.setReminderSound(RingtoneSelection.water);
    await repo.setReminderMaxRings(5);
    final migrated = await repo.watchReminderPreferences().first;
    expect(migrated.snoozeEnabled, isTrue);
    expect(migrated.vibration, VibrationSelection.standard);
    expect(migrated.sound, RingtoneSelection.water);
    await repo.setReminderSnoozeEnabled(false);
    await repo.setReminderVibration(VibrationSelection.heartbeat);
    await repo.setReminderSound(RingtoneSelection.none);
    final restored = await CourseRepository(
      db,
    ).watchReminderPreferences().first;
    expect(restored.snoozeEnabled, isFalse);
    expect(restored.maxRings, 5);
    expect(restored.vibration, VibrationSelection.heartbeat);
    expect(restored.sound, RingtoneSelection.none);
  });
  test('snooze off emits one ring and keeps rich course details', () {
    final reminder = const ReminderPlanner()
        .plan(
          semester: sampleSemester,
          courses: sampleCourses,
          now: DateTime(2020),
          maxRings: 5,
          snoozeEnabled: false,
          sound: RingtoneSelection.none,
          vibration: VibrationSelection.heartbeat,
        )
        .first;
    expect(reminder.maxRings, 1);
    expect(reminder.snoozeEnabled, isFalse);
    expect(reminder.sound, RingtoneSelection.none);
    expect(reminder.vibration, VibrationSelection.heartbeat);
    expect(reminder.courseName, isNotEmpty);
    expect(reminder.classEndAt!.isAfter(reminder.classStartAt!), isTrue);
    expect(reminder.dateLabel, contains('星期'));
    expect(reminder.timeLabel, contains('–'));
    expect(reminder.sectionLabel, contains('节'));
  });
  test(
    'changing a room preserves the dismissed course occurrence identity',
    () {
      final original = sampleCourses.first;
      final s = original.sessions.first;
      Course withRoom(String room) => Course(
        id: original.id,
        semesterId: original.semesterId,
        source: original.source,
        name: original.name,
        teacher: original.teacher,
        colorValue: original.colorValue,
        sessions: [
          CourseSession(
            weekday: s.weekday,
            startSection: s.startSection,
            endSection: s.endSection,
            startWeek: s.startWeek,
            endWeek: s.endWeek,
            pattern: s.pattern,
            room: room,
            startMinute: s.startMinute,
            endMinute: s.endMinute,
            timeSource: s.timeSource,
          ),
        ],
      );
      final before = const ReminderPlanner()
          .plan(
            semester: sampleSemester,
            courses: [withRoom('旧教室')],
            now: DateTime(2020),
          )
          .first;
      final after = const ReminderPlanner()
          .plan(
            semester: sampleSemester,
            courses: [withRoom('新教室')],
            now: DateTime(2020),
          )
          .first;
      expect(after.occurrenceKey, before.occurrenceKey);
    },
  );
  test('malformed imported sound falls back safely', () {
    expect(
      RingtoneSelection.fromStorage('local|%broken|%zz'),
      RingtoneSelection.systemDefault,
    );
  });
}
