import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

class CountingSchedule extends SchoolSchedule {
  CountingSchedule()
    : super(id: 'count', sections: SchoolSchedule.defaults().sections);
  int calls = 0;
  @override
  CourseSession resolve(CourseSession session, {String? semesterId}) {
    calls++;
    return super.resolve(session, semesterId: semesterId);
  }
}

void main() {
  testWidgets(
    'weekly view resolves each course once and reuses result on day switch',
    (t) async {
      final schedule = CountingSchedule();
      final courses = [
        for (var i = 0; i < 70; i++)
          Course(
            id: '$i',
            semesterId: 'a',
            source: CourseSource.manual,
            name: '课程$i',
            teacher: '教师',
            colorValue: 0xff228866,
            sessions: [
              CourseSession(
                weekday: i % 7 + 1,
                startSection: 1,
                endSection: 2,
                startWeek: 1,
                endWeek: 17,
                pattern: WeekPattern.everyWeek,
                room: 'A101',
              ),
            ],
          ),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: TimetablePage(
            semester: Semester(
              id: 'a',
              name: 'A',
              firstWeekStart: DateTime(2026, 9, 7),
              totalWeeks: 17,
            ),
            courses: courses,
            schedule: schedule,
            initialDisplayWeek: 1,
            currentWeek: 1,
            initialGridView: true,
            now: DateTime(2026, 9, 7),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(schedule.calls, 70);
      await t.tap(find.byKey(const Key('view_list')));
      await t.pumpAndSettle();
      expect(schedule.calls, 70);
    },
  );
}
