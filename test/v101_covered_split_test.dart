import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/section_split_page.dart';

void main() {
  testWidgets(
    'covered long block reuses smaller splits without averaging gaps',
    (t) async {
      SchoolSchedule? saved;
      const ranges = [
        SectionRangeTime(
          semesterId: 'a',
          startSection: 9,
          endSection: 12,
          startMinute: 1110,
          endMinute: 1310,
        ),
        SectionRangeTime(
          semesterId: 'a',
          startSection: 9,
          endSection: 10,
          startMinute: 1110,
          endMinute: 1205,
        ),
        SectionRangeTime(
          semesterId: 'a',
          startSection: 11,
          endSection: 12,
          startMinute: 1215,
          endMinute: 1310,
        ),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                saved = await Navigator.push<SchoolSchedule>(
                  c,
                  MaterialPageRoute(
                    builder: (_) => SectionSplitPage(
                      schedule: SchoolSchedule.defaults(),
                      semesterId: 'a',
                      ranges: ranges,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<int>));
      await t.pumpAndSettle();
      await t.tap(find.text('45 分钟').last);
      await t.pumpAndSettle();
      expect(find.textContaining('原始：第9–12节'), findsNothing);
      await t.ensureVisible(find.text('确认拆分并继续导入'));
      await t.tap(find.text('确认拆分并继续导入'));
      await t.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.sectionFor('a', 9)!.startMinute, 1110);
      expect(saved!.sectionFor('a', 10)!.endMinute, 1205);
      expect(saved!.sectionFor('a', 11)!.startMinute, 1215);
      expect(saved!.sectionFor('a', 12)!.endMinute, 1310);
    },
  );
  testWidgets('inconsistent enclosing endpoints remain unresolved', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SectionSplitPage(
          schedule: SchoolSchedule.defaults(),
          semesterId: 'a',
          ranges: const [
            SectionRangeTime(
              semesterId: 'a',
              startSection: 9,
              endSection: 10,
              startMinute: 1110,
              endMinute: 1205,
            ),
            SectionRangeTime(
              semesterId: 'a',
              startSection: 11,
              endSection: 12,
              startMinute: 1215,
              endMinute: 1310,
            ),
            SectionRangeTime(
              semesterId: 'a',
              startSection: 9,
              endSection: 12,
              startMinute: 1110,
              endMinute: 1315,
            ),
          ],
        ),
      ),
    );
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('45 分钟').last);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.textContaining('原始：第9–12节'), 300);
    expect(find.textContaining('原始：第9–12节'), findsOneWidget);
    await t.ensureVisible(find.text('确认拆分并继续导入'));
    await t.tap(find.text('确认拆分并继续导入'));
    await t.pumpAndSettle();
    expect(find.byType(SectionSplitPage), findsOneWidget);
    expect(find.text('拆分后的起止端点必须与原始区间一致'), findsNothing);
    expect(find.textContaining('课间不等或不是整分钟'), findsWidgets);
  });
}
