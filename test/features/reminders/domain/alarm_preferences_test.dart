import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_planner.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';

void main() {
  test(
    'snooze defaults and allowed values survive repository recreation',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CourseRepository(db);
      final defaults = await repo.watchReminderPreferences().first;
      expect(defaults.snoozeMinutes, 5);
      expect(defaults.maxRings, 2);
      await repo.setReminderSnoozeMinutes(30);
      await repo.setReminderMaxRings(10);
      final restored = await CourseRepository(
        db,
      ).watchReminderPreferences().first;
      expect(restored.snoozeMinutes, 30);
      expect(restored.maxRings, 10);
      expect(() => repo.setReminderSnoozeMinutes(7), throwsArgumentError);
      expect(() => repo.setReminderMaxRings(4), throwsArgumentError);
    },
  );
  test(
    'alarm plans include explicit cutoff and stable occurrence identities',
    () {
      final plans = const ReminderPlanner().plan(
        semester: sampleSemester,
        courses: sampleCourses,
        now: DateTime(2020),
        snoozeMinutes: 15,
        maxRings: 3,
      );
      expect(plans, isNotEmpty);
      expect(
        plans.first.classStartAt!.difference(plans.first.scheduledAt),
        const Duration(minutes: 30),
      );
      expect(plans.first.occurrenceKey, isNotEmpty);
      expect(plans.first.snoozeMinutes, 15);
      expect(plans.first.maxRings, 3);
      final noLead = const ReminderPlanner().plan(
        semester: sampleSemester,
        courses: sampleCourses,
        now: DateTime(2020),
        leadTime: Duration.zero,
      );
      expect(noLead, isEmpty);
    },
  );
  test('default reminder constructor remains compatible', () {
    const p = ReminderPreferences(
      enabled: true,
      leadMinutes: 30,
      sound: RingtoneSelection.chime,
    );
    expect(p.maxRings, 2);
  });

  test('public-holiday silence defaults on and can be turned off', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = CourseRepository(db);
    expect(
      (await repo.watchReminderPreferences().first).holidaySilenceEnabled,
      isTrue,
    );
    await repo.setHolidaySilenceEnabled(false);
    expect(
      (await CourseRepository(
        db,
      ).watchReminderPreferences().first).holidaySilenceEnabled,
      isFalse,
    );
  });
}
