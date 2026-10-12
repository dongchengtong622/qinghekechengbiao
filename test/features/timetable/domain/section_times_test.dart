import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/core/time/section_times.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  test('an unresolved scoped slot does not invent a default time', () {
    const s = CourseSession(
      weekday: 1,
      startSection: 1,
      endSection: 1,
      startWeek: 1,
      endWeek: 20,
      pattern: WeekPattern.everyWeek,
      room: '',
    );
    expect(
      SectionTimes.label(
        SchoolSchedule.defaults()
            .withSemesterSections('a', [])
            .resolve(s, semesterId: 'a'),
      ),
      '时间待确认',
    );
  });
  test('section courses display complete reference start and end times', () {
    const labels = [
      '08:25–09:10',
      '09:15–10:00',
      '10:15–11:00',
      '11:05–11:50',
      '13:40–14:25',
      '14:30–15:15',
      '15:30–16:15',
      '16:20–17:05',
      '17:10–17:55',
      '18:45–19:30',
      '19:35–20:20',
      '20:25–21:10',
    ];
    for (var i = 0; i < labels.length; i++) {
      final session = CourseSession(
        weekday: 1,
        startSection: i + 1,
        endSection: i + 1,
        startWeek: 1,
        endWeek: 18,
        pattern: WeekPattern.everyWeek,
        room: '',
      );
      expect(
        SectionTimes.label(SchoolSchedule.defaults().resolve(session)),
        labels[i],
      );
    }
  });
}
