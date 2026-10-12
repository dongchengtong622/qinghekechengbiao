import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/import_preview_page.dart';

void main() {
  final term = Semester(
    id: 'term',
    name: '秋季',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 20,
  );
  const summary = ImportSummary(
    inserted: 1,
    updated: 0,
    removed: 0,
    warnings: [],
  );
  ImportPreview draft({bool complete = true, bool missing = false}) =>
      ImportPreview(
        semester: term,
        courses: [
          Course(
            id: 'math',
            semesterId: 'term',
            source: CourseSource.cdcasKingo,
            name: '数学',
            teacher: '张明',
            colorValue: 0,
            sessions: [
              CourseSession(
                weekday: 1,
                startSection: 1,
                endSection: 2,
                startWeek: 1,
                endWeek: 16,
                pattern: WeekPattern.everyWeek,
                room: 'A101',
                startMinute: missing ? null : 480,
                endMinute: complete && !missing ? 575 : null,
                timeSource: missing
                    ? CourseTimeSource.schedule
                    : CourseTimeSource.imported,
              ),
            ],
          ),
        ],
      );
  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final source in CourseTimeSource.values) {
    testWidgets(
      'complete Excel time overrides $source without default or old-time selection',
      (tester) async {
        viewport(tester);
        ImportPreview? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: ImportPreviewPage(
              preview: draft(),
              changes: summary,
              existingTimes: [
                SectionRangeTime(
                  semesterId: 'term',
                  startSection: 1,
                  endSection: 2,
                  startMinute: 505,
                  endMinute: 600,
                  source: source,
                ),
              ],
              onConfirm: (value) async {
                saved = value;
                return summary;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('时间冲突'), findsNothing);
        expect(find.textContaining('已识别课表时间'), findsNothing);
        expect(find.textContaining('08:00–09:35'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, '导入课表'),
          250,
        );
        await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('确认拆分并继续导入'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('45 分钟').last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('确认拆分并继续导入'), 200);
        await tester.tap(find.text('确认拆分并继续导入'));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
      },
    );
  }
  testWidgets(
    'cancelling ambiguous section split leaves the original schedule and storage untouched',
    (tester) async {
      viewport(tester);
      var writes = 0;
      final original = SchoolSchedule.defaults();
      await tester.pumpWidget(
        MaterialApp(
          home: ImportPreviewPage(
            preview: draft(),
            changes: summary,
            schedule: original,
            onConfirm: (_) async {
              writes++;
              return summary;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '导入课表'),
        250,
      );
      await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
      await tester.pumpAndSettle();
      expect(find.text('确认拆分并继续导入'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(original.semesterSections, isEmpty);
      expect(original.rangeTimes, isEmpty);
    },
  );
  testWidgets(
    'missing times with an empty scoped template offer explicit defaults',
    (tester) async {
      viewport(tester);
      ImportPreview? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: ImportPreviewPage(
            preview: draft(missing: true),
            changes: summary,
            schedule: SchoolSchedule.defaults().withSemesterSections(
              'term',
              [],
            ),
            onConfirm: (value) async {
              saved = value;
              return summary;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '导入课表'),
        250,
      );
      await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
      await tester.pumpAndSettle();
      expect(find.text('确认使用默认作息'), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('使用以上时间并导入'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.sectionSchedule!.sectionFor('term', 1)?.startMinute, 505);
    },
  );
  testWidgets('missing Excel time requests default schedule confirmation', (
    tester,
  ) async {
    viewport(tester);
    ImportPreview? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: draft(missing: true),
          changes: summary,
          onConfirm: (value) async {
            saved = value;
            return summary;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('默认作息'), findsWidgets);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '导入课表'),
      250,
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(saved, isNull);
    await tester.tap(find.text('使用以上时间并导入'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
  });
  testWidgets('partial Excel boundary remains marked as this import', (
    tester,
  ) async {
    viewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: draft(complete: false),
          changes: summary,
          existingTimes: const [
            SectionRangeTime(
              semesterId: 'term',
              startSection: 1,
              endSection: 2,
              startMinute: 505,
              endMinute: 600,
            ),
          ],
          onConfirm: (_) async => summary,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('08:00–10:00（课表导入）'), findsOneWidget);
    expect(find.text('08:25–10:00（当前作息 · 此前导入）'), findsOneWidget);
  });
}
