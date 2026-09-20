import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_import_page.dart';

void main() {
  testWidgets('offers Excel selection without a teaching-system webview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(
          loadPreview: () async => null,
          onPreview: _summary,
          onImport: _summary,
        ),
      ),
    );

    expect(find.text('Excel 导入课表'), findsOneWidget);
    expect(find.text('选择 Excel 文件'), findsOneWidget);
    expect(find.textContaining('教务系统'), findsNothing);
  });

  testWidgets('opens the existing confirmation page after selecting a file', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(
          loadPreview: () async => _preview,
          onPreview: _summary,
          onImport: _summary,
        ),
      ),
    );

    await tester.tap(find.text('选择 Excel 文件'));
    await tester.pumpAndSettle();

    expect(find.text('确认导入'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
  });
}

Future<ImportSummary> _summary(ImportPreview preview) async => ImportSummary(
  inserted: preview.courses.length,
  updated: 0,
  removed: 0,
  warnings: preview.warnings,
);

final _preview = ImportPreview(
  semester: Semester(
    id: 'excel-2026-2027-1',
    name: '2026-2027学年第1学期',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  ),
  courses: const [
    Course(
      id: 'excel-math',
      semesterId: 'excel-2026-2027-1',
      source: CourseSource.cdcasKingo,
      externalId: 'math',
      name: '高等数学',
      teacher: '陈老师',
      colorValue: 0xFF2E7D66,
      sessions: [
        CourseSession(
          weekday: DateTime.monday,
          startSection: 1,
          endSection: 2,
          startWeek: 1,
          endWeek: 18,
          pattern: WeekPattern.everyWeek,
          room: 'A302',
        ),
      ],
    ),
  ],
);
