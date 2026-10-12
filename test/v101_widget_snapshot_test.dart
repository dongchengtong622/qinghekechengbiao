import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/widgets/domain/widget_snapshot.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  test('snapshot contains 14 days, real week filtering and unknown slots', () {
    final term = Semester(
      id: 'a',
      name: '秋季',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 20,
    );
    Course c(String id, int week) => Course(
      id: id,
      semesterId: 'a',
      source: CourseSource.manual,
      name: id,
      teacher: '教师',
      colorValue: 0,
      sessions: [
        CourseSession(
          weekday: 1,
          startSection: 1,
          endSection: 2,
          startWeek: week,
          endWeek: week,
          pattern: WeekPattern.everyWeek,
          room: 'A302',
        ),
      ],
    );
    final snapshot = WidgetSnapshot.generate(
      semester: term,
      courses: [c('本周', 1), c('下周', 2), c('其他周', 5)],
      schedule: SchoolSchedule.defaults().withSemesterSections('a', []),
      now: DateTime.utc(2026, 9, 6, 23),
    );
    final data = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    expect(data['schemaVersion'], 1);
    expect(data['scheduleId'], 'a');
    expect(data['timeZone'], 'Asia/Shanghai');
    final list = data['instances'] as List;
    expect(list.map((x) => x['courseName']), ['本周', '下周']);
    expect(list.first['startAt'], isNull);
    expect(list.first['room'], 'A302');
    expect(
      data['coverageEnd'] - data['coverageStart'],
      14 * 24 * 60 * 60 * 1000,
    );
  });
  test('known imported endpoints use actual timetable times', () {
    final term = Semester(
      id: 'a',
      name: 'A',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 20,
    );
    final c = Course(
      id: 'c',
      semesterId: 'a',
      source: CourseSource.cdcasKingo,
      name: '课程',
      teacher: '王老师',
      colorValue: 0,
      sessions: [
        const CourseSession(
          weekday: 1,
          startSection: 1,
          endSection: 2,
          startWeek: 1,
          endWeek: 20,
          pattern: WeekPattern.oddWeeks,
          room: '教室',
          startMinute: 480,
          endMinute: 580,
          timeSource: CourseTimeSource.imported,
        ),
      ],
    );
    final data = jsonDecode(
      WidgetSnapshot.generate(
        semester: term,
        courses: [c],
        schedule: SchoolSchedule.defaults(),
        now: DateTime.utc(2026, 9, 7),
      ).encode(),
    );
    expect((data['instances'] as List).length, 1);
    expect(data['instances'][0]['timeLabel'], '08:00–09:40');
    expect(data['instances'][0]['teacher'], '王老师');
  });
}
