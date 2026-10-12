import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/settings/presentation/scoped_schedule_page.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';

void main() {
  final term = Semester(
    id: 'editor',
    name: '编辑课表',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  final schedule = SchoolSchedule(
    id: 'three',
    sections: const [
      SectionTime(1, 480, 525),
      SectionTime(2, 540, 585),
      SectionTime(3, 600, 645),
    ],
  );
  Future<void> page(
    WidgetTester t,
    void Function(SchoolSchedule) saved, {
    int minimum = 1,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        home: ScopedSchedulePage(
          semester: term,
          schedule: schedule,
          minimumSectionCount: minimum,
          onSave: (v) async {
            saved(v);
          },
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> pick(
    WidgetTester t,
    String key,
    List<int> values, {
    bool cancel = false,
  }) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
    for (var i = 0; i < values.length; i++) {
      t
          .widget<CupertinoPicker>(find.byKey(Key('wheel_$i')))
          .onSelectedItemChanged!(values[i]);
    }
    await t.tap(find.byKey(Key(cancel ? 'wheel_cancel' : 'wheel_save')));
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    await t.scrollUntilVisible(
      find.text('保存作息'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('保存作息'));
    await t.pumpAndSettle();
    await t.tap(find.text('保存作息'));
    await t.pumpAndSettle();
  }

  testWidgets('fixed wheel duration computes end and locks its picker', (
    t,
  ) async {
    SchoolSchedule? saved;
    await page(t, (v) => saved = v);
    expect(find.text('每节课时长（分钟）'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.byKey(const Key('fixed_lesson_duration')));
    await t.pumpAndSettle();
    await pick(t, 'lesson_minutes', [34]);
    await pick(t, 'section_start_1', [8, 10]);
    expect(find.text('08:45'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const Key('section_end_1')))
          .onPressed,
      null,
    );
    expect(find.text('课间（分钟）'), findsNothing);
    await save(t);
    expect(saved!.sectionFor(term.id, 1)!.endMinute, 525);
    expect(saved!.lessonMinutesFor(term.id), 35);
    expect(saved!.fixedLessonDurationFor(term.id), true);
  });
  testWidgets(
    'manual wheel edits unequal durations and cancel preserves original',
    (t) async {
      SchoolSchedule? saved;
      await page(t, (v) => saved = v);
      await pick(t, 'section_start_1', [7, 30], cancel: true);
      expect(find.text('08:00'), findsOneWidget);
      await pick(t, 'section_end_1', [8, 35]);
      await save(t);
      expect(saved!.sectionFor(term.id, 1)!.endMinute, 515);
      expect(saved!.fixedLessonDurationFor(term.id), false);
    },
  );
  testWidgets('switching fixed off unlocks end picker', (t) async {
    await page(t, (_) {});
    await t.tap(find.byKey(const Key('fixed_lesson_duration')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('fixed_lesson_duration')));
    await t.pumpAndSettle();
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const Key('section_end_1')))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('delete last period persists smaller count without renumbering', (
    t,
  ) async {
    SchoolSchedule? saved;
    await page(t, (v) => saved = v);
    await t.scrollUntilVisible(
      find.text('删除最后一节'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('删除最后一节'));
    await t.pumpAndSettle();
    expect(find.text('第3节'), findsNothing);
    await save(t);
    expect(saved!.sectionCountFor(term.id), 2);
    expect(saved!.sectionFor(term.id, 1)!.startMinute, 480);
    expect(saved!.sectionFor(term.id, 3), null);
  });
  testWidgets('used last period cannot be deleted', (t) async {
    await page(t, (_) {}, minimum: 3);
    await t.scrollUntilVisible(
      find.text('删除最后一节'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('删除最后一节'));
    await t.pumpAndSettle();
    expect(find.textContaining('先调整课程'), findsOneWidget);
    expect(find.text('第3节'), findsOneWidget);
  });
  testWidgets('at least one period is retained', (t) async {
    await page(t, (_) {});
    await t.scrollUntilVisible(
      find.text('删除最后一节'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    for (var i = 0; i < 3; i++) {
      await t.ensureVisible(find.text('删除最后一节'));
      await t.pumpAndSettle();
      await t.tap(find.text('删除最后一节'));
      await t.pumpAndSettle();
    }
    expect(find.text('第1节'), findsOneWidget);
    expect(find.text('至少保留一节作息。'), findsOneWidget);
  });
  testWidgets('overlap selected by wheel does not save', (t) async {
    var saved = false;
    await page(t, (_) => saved = true);
    await pick(t, 'section_end_1', [9, 30]);
    await save(t);
    expect(saved, false);
    expect(find.textContaining('重叠'), findsOneWidget);
  });
  testWidgets('fixed duration crossing midnight does not save', (t) async {
    var saved = false;
    await page(t, (_) => saved = true);
    await t.tap(find.byKey(const Key('fixed_lesson_duration')));
    await t.pumpAndSettle();
    await pick(t, 'section_start_3', [23, 50]);
    await save(t);
    expect(saved, false);
    expect(find.textContaining('次日'), findsOneWidget);
  });
}
