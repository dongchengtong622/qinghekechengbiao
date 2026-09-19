import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/cdcas_kingo_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/import_preview_page.dart';

void main() {
  final preview = ImportPreview(
    semester: Semester(
      id: 'cdcas-2026-2027-1',
      name: '2026-2027学年第1学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    ),
    courses: const [
      Course(
        id: 'school-math',
        semesterId: 'cdcas-2026-2027-1',
        source: CourseSource.cdcasKingo,
        externalId: 'K1001',
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
    warnings: const ['一行信息未识别'],
  );

  testWidgets('lists semester, counts, courses, and warnings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: preview,
          changes: const ImportSummary(
            inserted: 1,
            updated: 0,
            removed: 0,
            warnings: [],
          ),
          onConfirm: _confirm,
        ),
      ),
    );

    expect(find.text('确认导入'), findsOneWidget);
    expect(find.text('2026-2027学年第1学期'), findsOneWidget);
    expect(find.textContaining('1 门课程'), findsOneWidget);
    expect(find.textContaining('1 个上课时段'), findsOneWidget);
    expect(find.textContaining('将新增 1'), findsOneWidget);
    expect(find.textContaining('周一 第1-2节'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('一行信息未识别'), findsOneWidget);
  });

  testWidgets('disables confirm while import is running', (tester) async {
    final completer = Completer<ImportSummary>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: preview,
          changes: const ImportSummary(
            inserted: 1,
            updated: 0,
            removed: 0,
            warnings: [],
          ),
          onConfirm: (_) {
            calls++;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '正在导入…'));
    expect(calls, 1);

    completer.complete(
      const ImportSummary(inserted: 1, updated: 0, removed: 0, warnings: []),
    );
    await tester.pumpAndSettle();
  });
}

Future<ImportSummary> _confirm(ImportPreview preview) async {
  return const ImportSummary(inserted: 1, updated: 0, removed: 0, warnings: []);
}
