import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/course_editor_page.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    Course? initialCourse,
    required Future<void> Function(Course) onSave,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: CourseEditorPage(
          semesterId: 'active-semester',
          initialCourse: initialCourse,
          onSave: onSave,
        ),
      ),
    );
  }

  testWidgets('requires a course name', (tester) async {
    await pumpEditor(tester, onSave: (_) async {});

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请输入课程名称'), findsOneWidget);
  });

  testWidgets('rejects an end section before the start section', (
    tester,
  ) async {
    await pumpEditor(tester, onSave: (_) async {});
    await tester.enterText(find.byKey(const Key('course_name')), '高等数学');
    await tester.enterText(find.byKey(const Key('start_section')), '4');
    await tester.enterText(find.byKey(const Key('end_section')), '2');

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('结束节次不能早于开始节次'), findsOneWidget);
  });

  testWidgets('saves a valid course', (tester) async {
    Course? saved;
    await pumpEditor(tester, onSave: (course) async => saved = course);
    await tester.enterText(find.byKey(const Key('course_name')), '高等数学');
    await tester.enterText(find.byKey(const Key('teacher')), '陈老师');
    await tester.enterText(find.byKey(const Key('room')), 'A302');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved?.name, '高等数学');
    expect(saved?.teacher, '陈老师');
    expect(saved?.sessions.single.room, 'A302');
    expect(saved?.semesterId, 'active-semester');
  });

  testWidgets('prefills an existing course for editing', (tester) async {
    const existing = Course(
      id: 'math',
      semesterId: 'sample-2026-autumn',
      source: CourseSource.manual,
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
    );

    await pumpEditor(tester, initialCourse: existing, onSave: (_) async {});

    expect(find.widgetWithText(TextFormField, '高等数学'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '陈老师'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'A302'), findsOneWidget);
  });

  testWidgets('editing the first session preserves remaining sessions', (
    tester,
  ) async {
    const existing = Course(
      id: 'math',
      semesterId: 'active-semester',
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
        CourseSession(
          weekday: DateTime.wednesday,
          startSection: 3,
          endSection: 4,
          startWeek: 1,
          endWeek: 18,
          pattern: WeekPattern.everyWeek,
          room: 'B201',
        ),
      ],
    );
    Course? saved;
    await pumpEditor(
      tester,
      initialCourse: existing,
      onSave: (course) async => saved = course,
    );
    await tester.enterText(find.byKey(const Key('room')), 'A305');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved?.sessions, hasLength(2));
    expect(saved?.sessions.first.room, 'A305');
    expect(saved?.sessions.last.room, 'B201');
  });
}
