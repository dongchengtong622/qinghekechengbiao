import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/workbook_selection_page.dart';

void main() {
  testWidgets('selects one worksheet before importing', (tester) async {
    final semester = Semester(
      id: 'term',
      name: '秋季学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    SheetImportResult sheet(String name, String courseName) =>
        SheetImportResult(
          name: name,
          grid: ExcelSheetGrid(
            name: name,
            cells: const [],
            rowCount: 0,
            columnCount: 0,
          ),
          preview: ImportPreview(
            semester: semester,
            courses: [
              Course(
                id: courseName,
                semesterId: semester.id,
                source: CourseSource.cdcasKingo,
                externalId: courseName,
                name: courseName,
                teacher: '',
                colorValue: 0xff000000,
                sessions: const [
                  CourseSession(
                    weekday: 1,
                    startSection: 1,
                    endSection: 2,
                    startWeek: 1,
                    endWeek: 18,
                    pattern: WeekPattern.everyWeek,
                    room: '',
                  ),
                ],
              ),
            ],
          ),
        );
    ImportPreview? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await Navigator.of(context).push<ImportPreview>(
                  MaterialPageRoute(
                    builder: (_) => WorkbookSelectionPage(
                      workbook: WorkbookImportPreview([
                        sheet('一班', '高等数学'),
                        sheet('二班', '大学英语'),
                      ]),
                      semester: semester,
                    ),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('一班'), findsOneWidget);
    expect(find.text('二班'), findsOneWidget);
    await tester.tap(find.text('二班'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入所选工作表'));
    await tester.pumpAndSettle();
    expect(chosen?.courses.map((course) => course.name), ['大学英语']);
  });
}
