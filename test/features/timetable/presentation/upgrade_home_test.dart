import 'package:flutter/material.dart';
import 'package:qinghe_timetable/core/time/section_times.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

void main() {
  test(
    'custom start without end is shown instead of fallback section time',
    () {
      const session = CourseSession(
        weekday: 1,
        startSection: 1,
        endSection: 2,
        startWeek: 1,
        endWeek: 18,
        pattern: WeekPattern.everyWeek,
        room: '',
        startMinute: 540,
      );
      expect(SectionTimes.label(session), '09:00 开始');
    },
  );

  testWidgets('opens today and can return after browsing another day', (
    tester,
  ) async {
    final term = Semester(
      id: 's',
      name: '学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: term,
          courses: const [],
          initialDisplayWeek: 1,
          currentWeek: 1,
          now: DateTime(2026, 9, 8),
        ),
      ),
    );
    expect(find.textContaining('周二 · 9/8'), findsOneWidget);
    expect(find.textContaining('周一 · 9/7'), findsNothing);
    await tester.tap(find.byKey(const Key('day_nav_4')));
    await tester.pump();
    await tester.tap(find.text('回到今天'));
    await tester.pump();
    expect(find.textContaining('周二 · 9/8'), findsOneWidget);
  });
  testWidgets(
    'today, complete week navigation and grid switch are available on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semester = Semester(
        id: 'term',
        name: '秋季学期',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TimetablePage(
            semester: semester,
            courses: const [],
            initialDisplayWeek: 1,
            currentWeek: 1,
            now: DateTime(2026, 9, 7),
            onAdd: () {},
          ),
        ),
      );
      expect(find.textContaining('9月7日'), findsWidgets);
      expect(find.byKey(const Key('day_nav_7')), findsOneWidget);
      await tester.tap(find.byKey(const Key('view_grid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('timetable_grid')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a single-period long course remains readable at large text size',
    (tester) async {
      final term = Semester(
        id: 'term',
        name: '学期',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      );
      final course = Course(
        id: 'c',
        semesterId: 'term',
        source: CourseSource.manual,
        name: '居住区景观规划设计长课程名称',
        teacher: '教师',
        colorValue: 0xFF2E7D66,
        sessions: const [
          CourseSession(
            weekday: 1,
            startSection: 1,
            endSection: 1,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: '第三教学楼210室',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: TimetablePage(
            semester: term,
            courses: [course],
            initialDisplayWeek: 1,
            currentWeek: 1,
            initialGridView: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
