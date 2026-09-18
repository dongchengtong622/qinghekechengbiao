import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

void main() {
  testWidgets('shows semester and course details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: sampleSemester,
          courses: sampleCourses,
          displayWeek: 3,
        ),
      ),
    );

    expect(find.text('青禾课表'), findsOneWidget);
    expect(find.text('2026 秋季学期 · 第 3 周'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.textContaining('A302'), findsOneWidget);
  });
}
