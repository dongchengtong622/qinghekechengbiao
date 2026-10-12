import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_planner.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  test('shared semester range controls reminder start time', () {
    final term = Semester(
      id: 's',
      name: '',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 1,
    );
    final schedule = SchoolSchedule.defaults().withRangeTime(
      const SectionRangeTime(
        semesterId: 's',
        startSection: 5,
        endSection: 6,
        startMinute: 505,
        endMinute: 600,
        source: CourseTimeSource.custom,
      ),
    );
    final reminders = const ReminderPlanner().plan(
      semester: term,
      now: DateTime(2026, 9, 1),
      schedule: schedule,
      courses: const [
        Course(
          id: 'math',
          semesterId: 's',
          source: CourseSource.manual,
          name: '数学',
          teacher: '',
          colorValue: 0,
          sessions: [
            CourseSession(
              weekday: 1,
              startSection: 5,
              endSection: 6,
              startWeek: 1,
              endWeek: 1,
              pattern: WeekPattern.everyWeek,
              room: '',
            ),
          ],
        ),
      ],
    );
    expect(reminders.single.classStartAt!.hour, 8);
    expect(reminders.single.classStartAt!.minute, 25);
    expect(reminders.single.scheduledAt.hour, 7);
    expect(reminders.single.scheduledAt.minute, 55);
  });
  test(
    'changing school start time retains occurrence identity and updates alarm',
    () {
      final term = Semester(
        id: 's',
        name: '',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 1,
      );
      final courses = [
        const Course(
          id: 'math',
          semesterId: 's',
          source: CourseSource.manual,
          name: '数学',
          teacher: '',
          colorValue: 0,
          sessions: [
            CourseSession(
              weekday: 1,
              startSection: 1,
              endSection: 1,
              startWeek: 1,
              endWeek: 1,
              pattern: WeekPattern.everyWeek,
              room: '',
            ),
          ],
        ),
      ];
      final before = const ReminderPlanner().plan(
        semester: term,
        courses: courses,
        now: DateTime(2026, 9, 1),
      );
      final after = const ReminderPlanner().plan(
        semester: term,
        courses: courses,
        now: DateTime(2026, 9, 1),
        schedule: SchoolSchedule(
          id: 'custom',
          sections: [const SectionTime(1, 480, 525)],
        ),
      );
      expect(after.single.classStartAt!.hour, 8);
      expect(after.single.classStartAt!.minute, 0);
      expect(after.single.scheduledAt.minute, 30);
      expect(after.single.occurrenceKey, before.single.occurrenceKey);
      expect(after.single.id, before.single.id);
    },
  );
}
