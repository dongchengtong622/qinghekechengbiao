import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

void main() {
  testWidgets('shows semester and course details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: sampleSemester,
          courses: sampleCourses,
          displayWeek: 3,
        ),
      ),
    );

    expect(find.text('青禾课表'), findsOneWidget);
    expect(find.text('2026 秋季学期 · 第 3 周'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.textContaining('A302'), findsOneWidget);
  });

  testWidgets('invokes add and edit actions', (tester) async {
    var added = false;
    Course? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: sampleSemester,
          courses: sampleCourses,
          displayWeek: 3,
          onAdd: () => added = true,
          onEdit: (course) => edited = course,
        ),
      ),
    );

    await tester.tap(find.byTooltip('添加课程'));
    await tester.tap(find.text('高等数学'));

    expect(added, isTrue);
    expect(edited?.id, 'math');
  });

  testWidgets('exposes import and reminder actions in the header', (tester) async {
    var imported = false;
    var remindersOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: sampleSemester,
          courses: sampleCourses,
          displayWeek: 3,
          onImport: () => imported = true,
          onReminders: () => remindersOpened = true,
        ),
      ),
    );

    await tester.tap(find.byTooltip('导入课表'));
    await tester.tap(find.byTooltip('提醒'));

    expect(imported, isTrue);
    expect(remindersOpened, isTrue);
  });

  testWidgets('confirms before deleting a course', (tester) async {
    Course? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: sampleSemester,
          courses: sampleCourses,
          displayWeek: 3,
          onDelete: (course) => deleted = course,
        ),
      ),
    );

    await tester.tap(find.byTooltip('课程操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除课程'));
    await tester.pumpAndSettle();
    expect(find.text('确认删除“高等数学”？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(deleted?.id, 'math');
  });
}
