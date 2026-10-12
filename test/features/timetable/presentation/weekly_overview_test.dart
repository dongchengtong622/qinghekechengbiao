import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';

void main() {
  testWidgets('week initially fits screen and supports zoom reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: sampleSemester,
          courses: sampleCourses,
          initialDisplayWeek: 3,
          currentWeek: 3,
          initialGridView: true,
          scheduleSectionCount: 14,
        ),
      ),
    );
    final grid = tester.getRect(find.byKey(const Key('timetable_grid')));
    expect(grid.right, lessThanOrEqualTo(360));
    expect(grid.bottom, lessThanOrEqualTo(760));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.textContaining('周日'), findsWidgets);
    expect(find.text('14'), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    expect(find.textContaining('第'), findsWidgets);
    await tester.tap(find.byKey(const Key('reset_week_zoom')));
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    expect(tester.takeException(), isNull);
  });
}
