import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/schedule_preview_page.dart';

void main() {
  testWidgets('preview edits time and saves only after confirmation', (
    tester,
  ) async {
    SchoolSchedule? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulePreviewPage(
          schedule: SchoolSchedule(
            id: 'test',
            sections: [const SectionTime(1, 505, 550)],
          ),
          onSave: (s) async {
            saved = s;
          },
        ),
      ),
    );
    expect(saved, isNull);
    await tester.enterText(find.byKey(const Key('section_start_1')), '08:00');
    await tester.tap(find.text('应用作息时间'));
    await tester.pumpAndSettle();
    expect(saved?.sections.first.startMinute, 480);
  });
}
