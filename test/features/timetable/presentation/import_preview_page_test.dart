import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/import_preview_page.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

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

  testWidgets('editing a recognized course stays in draft until confirmation', (
    tester,
  ) async {
    ImportPreview? committed;
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
          onPreview: (draft) async => ImportSummary(
            inserted: draft.courses.length,
            updated: 0,
            removed: 0,
            warnings: [],
          ),
          onConfirm: (draft) async {
            committed = draft;
            return _confirm(draft);
          },
        ),
      ),
    );
    await tester.tap(find.textContaining('周一 第1-2节'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('course_name')), '修正后的课程');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(committed, isNull);
    expect(find.text('修正后的课程'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '导入课表'),
      200,
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用以上时间并导入'));
    await tester.pumpAndSettle();
    expect(committed?.courses.single.name, '修正后的课程');
  });

  testWidgets(
    'selected shared import time is also used when editing the draft',
    (tester) async {
      final first = preview.courses.first;
      final imported = Course(
        id: first.id,
        semesterId: first.semesterId,
        source: first.source,
        externalId: first.externalId,
        name: first.name,
        teacher: first.teacher,
        colorValue: first.colorValue,
        sessions: const [
          CourseSession(
            weekday: 1,
            startSection: 5,
            endSection: 6,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: 'A302',
            startMinute: 505,
            endMinute: 600,
            timeSource: CourseTimeSource.imported,
          ),
        ],
      );
      final choice = SectionRangeTime(
        semesterId: preview.semester.id,
        startSection: 5,
        endSection: 6,
        startMinute: 840,
        endMinute: 935,
      );
      final draft = ImportPreview(
        semester: preview.semester,
        courses: [imported],
        importedTimes: [choice],
        timeChoices: {choice.key: choice},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ImportPreviewPage(
            preview: draft,
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
      await tester.tap(find.textContaining('周一 第5-6节'));
      await tester.pumpAndSettle();
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('15:35'), findsOneWidget);
    },
  );
  testWidgets(
    'complete imported time beyond default sections can be confirmed',
    (tester) async {
      final first = preview.courses.first;
      final c = Course(
        id: first.id,
        semesterId: first.semesterId,
        source: first.source,
        externalId: first.externalId,
        name: first.name,
        teacher: first.teacher,
        colorValue: first.colorValue,
        sessions: const [
          CourseSession(
            weekday: 1,
            startSection: 13,
            endSection: 14,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: 'A302',
          ),
        ],
      );
      final time = SectionRangeTime(
        semesterId: preview.semester.id,
        startSection: 13,
        endSection: 14,
        startMinute: 1140,
        endMinute: 1235,
      );
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ImportPreviewPage(
            preview: ImportPreview(
              semester: preview.semester,
              courses: [c],
              importedTimes: [time],
            ),
            changes: const ImportSummary(
              inserted: 1,
              updated: 0,
              removed: 0,
              warnings: [],
            ),
            onConfirm: (draft) async {
              writes++;
              return _confirm(draft);
            },
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '导入课表'),
        200,
      );
      await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
      await tester.pumpAndSettle();
      expect(find.text('确认拆分并继续导入'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('45 分钟').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('确认拆分并继续导入'), 200);
      await tester.tap(find.text('确认拆分并继续导入'));
      await tester.pumpAndSettle();
      expect(writes, 1);
    },
  );

  testWidgets(
    'missing import times disclose all default periods before writing',
    (tester) async {
      var writes = 0;
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
            onConfirm: (draft) async {
              writes++;
              return _confirm(draft);
            },
          ),
        ),
      );
      expect(find.textContaining('课表缺少完整时间'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '导入课表'),
        200,
      );
      await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('第1节 08:25–09:10'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('第12节 20:25–21:10'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('第12节 20:25–21:10'), findsOneWidget);
      await tester.tap(find.text('使用以上时间并导入'));
      await tester.pumpAndSettle();
      expect(writes, 1);
    },
  );

  testWidgets('legacy single ranges do not overlap missing-time defaults', (
    tester,
  ) async {
    var writes = 0;
    final course = preview.courses.single;
    final draft = ImportPreview(
      semester: preview.semester,
      courses: [
        Course(
          id: course.id,
          semesterId: course.semesterId,
          source: course.source,
          name: course.name,
          teacher: course.teacher,
          colorValue: course.colorValue,
          sessions: const [
            CourseSession(
              weekday: DateTime.monday,
              startSection: 9,
              endSection: 12,
              startWeek: 1,
              endWeek: 18,
              pattern: WeekPattern.everyWeek,
              room: 'A302',
            ),
          ],
        ),
      ],
      warnings: const [],
    );
    final schedule = SchoolSchedule.defaults().withRangeTimes([
      SectionRangeTime(
        semesterId: preview.semester.id,
        startSection: 9,
        endSection: 9,
        startMinute: 1140,
        endMinute: 1185,
      ),
      SectionRangeTime(
        semesterId: preview.semester.id,
        startSection: 10,
        endSection: 10,
        startMinute: 1195,
        endMinute: 1240,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: draft,
          schedule: schedule,
          changes: const ImportSummary(
            inserted: 1,
            updated: 0,
            removed: 0,
            warnings: [],
          ),
          onConfirm: (draft) async {
            writes++;
            return _confirm(draft);
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '导入课表'),
      200,
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('确认使用默认作息'), findsOneWidget);
    expect(writes, 0);
    await tester.tap(find.text('返回核对'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(schedule.semesterSections, isEmpty);
    expect(schedule.range(preview.semester.id, 10, 10)?.endMinute, 1240);
  });
  testWidgets('many import warnings can be expanded without hiding courses', (
    tester,
  ) async {
    final noisy = ImportPreview(
      semester: preview.semester,
      courses: preview.courses,
      warnings: List.generate(6, (index) => '待核对内容 ${index + 1}'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: noisy,
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
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('识别提示（6 条）'), findsOneWidget);
    await tester.tap(find.text('识别提示（6 条）'));
    await tester.pumpAndSettle();
    expect(find.text('待核对内容 1'), findsOneWidget);
  });

  testWidgets('requires review of uncertain import fields before saving', (
    tester,
  ) async {
    ImportPreview? committed;
    final uncertain = ImportPreview(
      semester: preview.semester,
      courses: preview.courses,
      courseReviews: const {
        'school-math': ImportCourseReview(
          rawText: '高等数学 1-18周 A302',
          fieldsNeedingReview: {'周次'},
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewPage(
          preview: uncertain,
          changes: const ImportSummary(
            inserted: 1,
            updated: 0,
            removed: 0,
            warnings: [],
          ),
          onConfirm: (draft) async {
            committed = draft;
            return _confirm(draft);
          },
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '导入课表'),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pumpAndSettle();
    expect(committed, isNull);
    expect(find.textContaining('识别字段需要核对'), findsOneWidget);
    await tester.ensureVisible(find.text('查看导入原文'));
    await tester.tap(find.text('查看导入原文'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学 1-18周 A302'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('已核对周次'));
    await tester.tap(find.text('已核对周次'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '导入课表'),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用以上时间并导入'));
    await tester.pumpAndSettle();
    expect(committed, isNotNull);
  });

  testWidgets('deleting a draft and leaving the preview never writes courses', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ImportPreviewPage(
                    preview: preview,
                    changes: const ImportSummary(
                      inserted: 1,
                      updated: 0,
                      removed: 0,
                      warnings: [],
                    ),
                    onConfirm: (draft) async {
                      writes++;
                      return _confirm(draft);
                    },
                  ),
                ),
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(preview.courses.length, 1);
  });

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

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '导入课表'),
      200,
    );
    await tester.tap(find.widgetWithText(FilledButton, '导入课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用以上时间并导入'));
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
