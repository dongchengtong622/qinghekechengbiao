import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/excel_manual_mapping_page.dart';

void main() {
  testWidgets('selects the weekday row and returns an editable preview', (
    tester,
  ) async {
    final semester = Semester(
      id: 'term',
      name: '学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    ImportPreview? result;
    final mapping = ExcelMappingRequiredException([
      const ExcelSheetGrid(
        name: '课表',
        rowCount: 3,
        columnCount: 3,
        cells: [
          GridCell('标题', 0, 0),
          GridCell('时段', 1, 0),
          GridCell('第一天', 1, 1),
          GridCell('第二天', 1, 2),
          GridCell('第1-2节', 2, 0),
          GridCell('数学\n1-16周', 2, 1),
        ],
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<ImportPreview>(
                MaterialPageRoute(
                  builder: (_) => ExcelManualMappingPage(
                    mapping: mapping,
                    semester: semester,
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('excel_weekday_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('第 2 行').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新识别'));
    await tester.pumpAndSettle();
    expect(result?.courses.single.name, '数学');
  });
}
