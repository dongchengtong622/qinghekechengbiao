import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/settings/presentation/usage_guide_page.dart';
import 'package:qinghe_timetable/features/timetable/presentation/import_preview_page.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  testWidgets('guide exposes readable offline steps and later term editing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: UsageGuidePage()));
    await tester.tap(find.text('1. 第一次使用与操作顺序'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可以先导入并核对课程'), findsOneWidget);
    expect(find.textContaining('点击下面的功能'), findsOneWidget);
  });
  testWidgets(
    'term dialog keeps invalid shrinking open with course week explanation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => askImportSemester(
                  context,
                  Semester(
                    id: 's',
                    name: '测试',
                    firstWeekStart: DateTime(2026, 8, 31),
                    totalWeeks: 20,
                  ),
                  minimumWeeks: 18,
                ),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '16');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('已有课程到第 18 周，请填写至少 18 周'), findsOneWidget);
      expect(find.text('设置学期'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), '18');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('设置学期'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
