import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

final _semester = Semester(
  id: 'term',
  name: '学期',
  firstWeekStart: DateTime(2026, 9, 7),
  totalWeeks: 18,
);
Course _course(String name, int day, {int week = 1, String room = 'A302'}) =>
    Course(
      id: name,
      semesterId: 'term',
      source: CourseSource.manual,
      name: name,
      teacher: '张老师',
      colorValue: 0xFF2E7D66,
      sessions: [
        CourseSession(
          weekday: day,
          startSection: 1,
          endSection: 2,
          startWeek: week,
          endWeek: week,
          pattern: WeekPattern.everyWeek,
          room: room,
        ),
      ],
    );
Future<void> _open(
  WidgetTester tester, {
  DateTime? now,
  List<Course>? courses,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TimetablePage(
        semester: _semester,
        courses: courses ?? [_course('今天课程', 2), _course('未来课程', 2, week: 3)],
        initialDisplayWeek: 3,
        currentWeek: 1,
        now: now ?? DateTime(2026, 9, 8),
        initialGridView: true,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'axis flags a single import that conflicts with an overlapping paired import',
    (tester) async {
      final schedule = SchoolSchedule.decode(
        SchoolSchedule(
          id: 'school',
          sections: const [SectionTime(1, 480, 520), SectionTime(2, 540, 580)],
          rangeTimes: const [
            SectionRangeTime(
              semesterId: 'term',
              startSection: 1,
              endSection: 1,
              startMinute: 480,
              endMinute: 520,
            ),
            SectionRangeTime(
              semesterId: 'term',
              startSection: 1,
              endSection: 2,
              startMinute: 600,
              endMinute: 710,
            ),
          ],
        ).encode(),
      );
      final original = _course('合并课程', 2);
      final effective = schedule.resolve(
        original.sessions.first,
        semesterId: 'term',
      );
      expect(effective.timeLabel, '10:00–11:50');
      final course = Course(
        id: original.id,
        semesterId: original.semesterId,
        source: original.source,
        name: original.name,
        teacher: original.teacher,
        colorValue: original.colorValue,
        sessions: [effective],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TimetablePage(
            semester: _semester,
            courses: [course],
            initialDisplayWeek: 1,
            currentWeek: 1,
            now: DateTime(2026, 9, 8),
            initialGridView: true,
            schedule: schedule,
            scheduleSectionCount: 2,
          ),
        ),
      );
      final firstAxis = find.byKey(const Key('section_axis_1'));
      expect(
        find.descendant(of: firstAxis, matching: find.text('时间待确认')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstAxis, matching: find.text('08:00')),
        findsNothing,
      );
      expect(find.text('时间待确认'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'axis preserves consistent single and paired imports that override the base schedule',
    (tester) async {
      final schedule = SchoolSchedule.decode(
        SchoolSchedule(
          id: 'school',
          sections: const [SectionTime(1, 480, 520), SectionTime(2, 540, 580)],
          rangeTimes: const [
            SectionRangeTime(
              semesterId: 'term',
              startSection: 1,
              endSection: 1,
              startMinute: 600,
              endMinute: 640,
            ),
            SectionRangeTime(
              semesterId: 'term',
              startSection: 2,
              endSection: 2,
              startMinute: 660,
              endMinute: 710,
            ),
            SectionRangeTime(
              semesterId: 'term',
              startSection: 1,
              endSection: 2,
              startMinute: 600,
              endMinute: 710,
            ),
          ],
        ).encode(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TimetablePage(
            semester: _semester,
            courses: const [],
            initialDisplayWeek: 1,
            currentWeek: 1,
            now: DateTime(2026, 9, 8),
            initialGridView: true,
            schedule: schedule,
            scheduleSectionCount: 2,
          ),
        ),
      );
      final firstAxis = find.byKey(const Key('section_axis_1'));
      final secondAxis = find.byKey(const Key('section_axis_2'));
      expect(
        find.descendant(of: firstAxis, matching: find.text('10:00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstAxis, matching: find.text('10:40')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: secondAxis, matching: find.text('11:00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: secondAxis, matching: find.text('11:50')),
        findsOneWidget,
      );
      expect(find.text('时间待确认'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'single period long room stays inside course tile at overview and zoom',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final course = Course(
        id: 'long',
        semesterId: 'term',
        source: CourseSource.manual,
        name: '居住区景观规划设计长课程名称',
        teacher: '王老师',
        colorValue: 0xFF123456,
        sessions: const [
          CourseSession(
            weekday: 2,
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
          home: TimetablePage(
            semester: _semester,
            courses: [course],
            initialDisplayWeek: 1,
            currentWeek: 1,
            initialGridView: true,
            now: DateTime(2026, 9, 8),
            scheduleSectionCount: 30,
          ),
        ),
      );
      final room = find.text('第三教学楼210室');
      expect(room, findsOneWidget);
      final tile = find
          .ancestor(of: room, matching: find.byType(Material))
          .first;
      expect(
        tester.getRect(tile).contains(tester.getRect(room).center),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.identity()
        ..scaleByDouble(2, 2, 1, 1);
      await tester.pump();
      expect(room, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('reset_week_zoom')));
      await tester.pump();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    },
  );
  testWidgets('grid details preserve selected session when editing', (
    tester,
  ) async {
    Course? edited;
    final base = _course('双时段课程', 2);
    final course = Course(
      id: base.id,
      semesterId: base.semesterId,
      source: base.source,
      name: base.name,
      teacher: base.teacher,
      colorValue: base.colorValue,
      sessions: [
        base.sessions.first,
        const CourseSession(
          weekday: 2,
          startSection: 5,
          endSection: 6,
          startWeek: 1,
          endWeek: 18,
          pattern: WeekPattern.everyWeek,
          room: 'B401',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: _semester,
          courses: [course],
          initialDisplayWeek: 1,
          currentWeek: 1,
          initialGridView: true,
          now: DateTime(2026, 9, 8),
          onEdit: (value) => edited = value,
        ),
      ),
    );
    await tester.tap(find.text('双时段课程').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.text('双时段课程'),
          )
          .last,
    );
    expect(edited?.sessions.first.startSection, 5);
    expect(edited?.sessions.first.room, 'B401');
    expect(edited?.sessions, hasLength(2));
    expect(edited?.colorValue, 0xFF2E7D66);
  });
  testWidgets(
    'axis uses saved individual section times and exact single section import override',
    (tester) async {
      final schedule = SchoolSchedule(
        id: 'school',
        sections: const [SectionTime(1, 480, 520), SectionTime(2, 535, 575)],
        rangeTimes: const [
          SectionRangeTime(
            semesterId: 'term',
            startSection: 2,
            endSection: 2,
            startMinute: 540,
            endMinute: 580,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TimetablePage(
            semester: _semester,
            courses: const [],
            initialDisplayWeek: 1,
            currentWeek: 1,
            now: DateTime(2026, 9, 8),
            initialGridView: true,
            schedule: schedule,
            scheduleSectionCount: 2,
          ),
        ),
      );
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('08:40'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('09:40'), findsOneWidget);
      expect(find.text('08:55'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'axis does not invent missing or individual times for imported paired range',
    (tester) async {
      final schedule = SchoolSchedule(
        id: 'school',
        sections: const [SectionTime(1, 480, 520)],
        rangeTimes: const [
          SectionRangeTime(
            semesterId: 'term',
            startSection: 1,
            endSection: 2,
            startMinute: 600,
            endMinute: 710,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TimetablePage(
            semester: _semester,
            courses: const [],
            initialDisplayWeek: 1,
            currentWeek: 1,
            now: DateTime(2026, 9, 8),
            initialGridView: true,
            schedule: schedule,
            scheduleSectionCount: 2,
          ),
        ),
      );
      expect(find.text('时间待确认'), findsNWidgets(2));
      expect(find.text('08:00'), findsNothing);
      expect(find.text('10:55'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('switching a future week grid to list shows only today courses', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('未来课程'), findsOneWidget);
    await tester.tap(find.byKey(const Key('view_list')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 周'), findsOneWidget);
    expect(find.textContaining('周二 · 9/8 · 今天'), findsOneWidget);
    expect(find.text('今天课程'), findsOneWidget);
    expect(find.text('未来课程'), findsNothing);
    expect(find.textContaining('周一 ·'), findsNothing);
    expect(find.text('查看整周'), findsNothing);
  });
  testWidgets(
    'switching to list on a free day does not show other days courses',
    (tester) async {
      await _open(tester, courses: [_course('其他日期课程', 1)]);
      await tester.tap(find.byKey(const Key('view_list')));
      await tester.pumpAndSettle();
      expect(find.text('今天没课，自由安排'), findsOneWidget);
      expect(find.text('其他日期课程'), findsNothing);
    },
  );
  testWidgets(
    'grid can return from another week to today without losing grid controls',
    (tester) async {
      await _open(tester);
      expect(find.text('查看整周'), findsNothing);
      await tester.tap(find.text('回到今天'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text('今天课程'), findsOneWidget);
      expect(find.byKey(const Key('view_list')), findsOneWidget);
      expect(find.byKey(const Key('reset_week_zoom')), findsOneWidget);
    },
  );
  testWidgets(
    'outside semester list switch shows actual today and no old term course',
    (tester) async {
      await _open(tester, now: DateTime(2027, 2, 2));
      await tester.tap(find.byKey(const Key('view_list')));
      await tester.pumpAndSettle();
      expect(find.textContaining('周二 · 2/2 · 今天'), findsOneWidget);
      expect(find.text('今天没课，自由安排'), findsOneWidget);
      expect(find.text('未来课程'), findsNothing);
    },
  );
  testWidgets(
    'overview includes room and tapping course still opens all day details',
    (tester) async {
      await _open(tester);
      expect(find.text('A302'), findsOneWidget);
      await tester.tap(find.text('未来课程'));
      await tester.pumpAndSettle();
      expect(find.text('周二全部课程（含时间冲突）'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('张老师'),
        ),
        findsOneWidget,
      );
      expect(find.text('A302'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
