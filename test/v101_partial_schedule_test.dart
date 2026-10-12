import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/settings/presentation/scoped_schedule_page.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  testWidgets(
    'partial imported times never fill later periods with stale defaults',
    (t) async {
      final schedule = SchoolSchedule.defaults().withRangeTimes(const [
        SectionRangeTime(
          semesterId: 'a',
          startSection: 9,
          endSection: 9,
          startMinute: 1140,
          endMinute: 1185,
        ),
        SectionRangeTime(
          semesterId: 'a',
          startSection: 10,
          endSection: 10,
          startMinute: 1195,
          endMinute: 1240,
        ),
      ]);
      await t.pumpWidget(
        MaterialApp(
          home: ScopedSchedulePage(
            semester: Semester(
              id: 'a',
              name: 'A',
              firstWeekStart: DateTime(2026, 9, 7),
              totalWeeks: 17,
            ),
            schedule: schedule,
            onSave: (_) async {},
          ),
        ),
      );
      final state = t.state(find.byType(ScopedSchedulePage));
      // All controllers exist even when ListView has not laid out later rows.
      final fields = (state as dynamic).starts as List<TextEditingController>;
      expect(fields[8].text, '19:00');
      expect(fields[9].text, '19:55');
      expect(fields[10].text, isEmpty);
      expect(fields[11].text, isEmpty);
    },
  );
}
