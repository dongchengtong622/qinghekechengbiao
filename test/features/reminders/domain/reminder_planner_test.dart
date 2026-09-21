import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/core/time/shanghai_time.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_planner.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  const planner = ReminderPlanner();
  final semester = Semester(
    id: '2026-autumn',
    name: '2026 秋季学期',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 4,
  );

  Course course({
    String id = 'math',
    int weekday = DateTime.monday,
    int startSection = 1,
    int? endSection,
    int startWeek = 1,
    int endWeek = 4,
    WeekPattern pattern = WeekPattern.everyWeek,
  }) {
    return Course(
      id: id,
      semesterId: semester.id,
      source: CourseSource.manual,
      name: '高等数学',
      teacher: '陈老师',
      colorValue: 0xFF2E7D66,
      sessions: [
        CourseSession(
          weekday: weekday,
          startSection: startSection,
          endSection: endSection ?? startSection + 1,
          startWeek: startWeek,
          endWeek: endWeek,
          pattern: pattern,
          room: 'A302',
        ),
      ],
    );
  }

  test('contains all twelve official section start times', () {
    const expected = <int, (int, int)>{
      1: (8, 25),
      2: (9, 15),
      3: (10, 15),
      4: (11, 5),
      5: (13, 40),
      6: (14, 30),
      7: (15, 30),
      8: (16, 20),
      9: (17, 10),
      10: (18, 45),
      11: (19, 35),
      12: (20, 25),
    };

    expect(cdcasSectionStarts.keys, expected.keys);
    for (final entry in expected.entries) {
      expect(cdcasSectionStarts[entry.key]?.hour, entry.value.$1);
      expect(cdcasSectionStarts[entry.key]?.minute, entry.value.$2);
    }
  });

  test('schedules section one exactly thirty minutes early', () {
    final reminders = planner.plan(
      semester: semester,
      courses: [course()],
      now: DateTime(2026, 9, 1),
    );

    expect(
      reminders.first.scheduledAt,
      ShanghaiTime.dateTime(2026, 9, 7, 7, 55),
    );
    expect(reminders.first.title, '30分钟后上课：高等数学');
    expect(reminders.first.body, '第1-2节 · A302 · 陈老师');
    expect(reminders.first.payload, 'math');
  });

  test('uses the selected lead time, sound, and custom class time', () {
    final customCourse = course();
    final session = customCourse.sessions.single;
    final reminders = planner.plan(
      semester: semester,
      courses: [
        Course(
          id: customCourse.id,
          semesterId: customCourse.semesterId,
          source: customCourse.source,
          name: customCourse.name,
          teacher: customCourse.teacher,
          colorValue: customCourse.colorValue,
          sessions: [
            CourseSession(
              weekday: session.weekday,
              startSection: session.startSection,
              endSection: session.endSection,
              startWeek: session.startWeek,
              endWeek: session.endWeek,
              pattern: session.pattern,
              room: session.room,
              startMinute: 9 * 60 + 40,
              endMinute: 11 * 60 + 15,
            ),
          ],
        ),
      ],
      now: DateTime(2026, 9, 1),
      leadTime: const Duration(minutes: 10),
      sound: ReminderSound.soft,
    );

    expect(
      reminders.first.scheduledAt,
      ShanghaiTime.dateTime(2026, 9, 7, 9, 30),
    );
    expect(reminders.first.title, '10分钟后上课：高等数学');
    expect(reminders.first.sound, ReminderSound.soft);
  });

  test('maps weekdays and honors week pattern and boundaries', () {
    final reminders = planner.plan(
      semester: semester,
      courses: [
        course(
          weekday: DateTime.wednesday,
          startSection: 5,
          startWeek: 2,
          endWeek: 4,
          pattern: WeekPattern.evenWeeks,
        ),
      ],
      now: DateTime(2026, 9, 1),
    );

    expect(reminders.map((item) => item.scheduledAt), [
      ShanghaiTime.dateTime(2026, 9, 16, 13, 10),
      ShanghaiTime.dateTime(2026, 9, 30, 13, 10),
    ]);
  });

  test('filters past reminders and combines multiple sessions', () {
    final second = course(
      id: 'english',
      weekday: DateTime.friday,
      startSection: 12,
      endSection: 12,
      startWeek: 1,
      endWeek: 1,
    );
    final reminders = planner.plan(
      semester: semester,
      courses: [course(), second],
      now: DateTime(2026, 9, 8),
    );

    expect(reminders, hasLength(4));
    expect(reminders.first.payload, 'english');
    expect(
      reminders.first.scheduledAt,
      ShanghaiTime.dateTime(2026, 9, 11, 19, 55),
    );
  });

  test('notification IDs are stable, positive, and unique by week', () {
    final first = planner.plan(
      semester: semester,
      courses: [course()],
      now: DateTime(2026, 9, 1),
    );
    final second = planner.plan(
      semester: semester,
      courses: [course()],
      now: DateTime(2026, 9, 1),
    );

    expect(first.map((item) => item.id), second.map((item) => item.id));
    expect(first.every((item) => item.id > 0), isTrue);
    expect(first.map((item) => item.id).toSet(), hasLength(first.length));
  });

  test('plans reminders as Shanghai times from a Tokyo current time', () {
    ShanghaiTime.ensureInitialized();
    final tokyo = timezone.getLocation('Asia/Tokyo');
    final reminders = planner.plan(
      semester: semester,
      courses: [course(endWeek: 1)],
      now: timezone.TZDateTime(tokyo, 2026, 9, 1),
    );

    final scheduledAt = reminders.single.scheduledAt;
    expect(scheduledAt, isA<timezone.TZDateTime>());
    expect((scheduledAt as timezone.TZDateTime).location.name, 'Asia/Shanghai');
    expect(scheduledAt.toIso8601String(), '2026-09-07T07:55:00.000+0800');
  });

  test('notification IDs include the complete session identity', () {
    final base = course(endWeek: 1);
    final firstSession = base.sessions.single;
    final multiSessionCourse = Course(
      id: base.id,
      semesterId: base.semesterId,
      source: base.source,
      name: base.name,
      teacher: base.teacher,
      colorValue: base.colorValue,
      sessions: [
        firstSession,
        CourseSession(
          weekday: firstSession.weekday,
          startSection: firstSession.startSection,
          endSection: firstSession.endSection + 1,
          startWeek: 1,
          endWeek: 1,
          pattern: WeekPattern.everyWeek,
          room: 'A305',
        ),
      ],
    );

    final reminders = planner.plan(
      semester: semester,
      courses: [multiSessionCourse],
      now: DateTime(2026, 9, 1),
    );

    expect(reminders, hasLength(2));
    expect(reminders.map((item) => item.id).toSet(), hasLength(2));
  });
}
