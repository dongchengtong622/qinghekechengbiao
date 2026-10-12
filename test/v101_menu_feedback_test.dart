import 'package:qinghe_timetable/core/widgets/compact_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/core/theme/app_theme.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  testWidgets('week trigger and selected item have no grey ink feedback', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TimetablePage(
          semester: Semester(
            id: 'a',
            name: '学期',
            firstWeekStart: DateTime(2026, 8, 31),
            totalWeeks: 18,
          ),
          courses: const [],
          initialDisplayWeek: 6,
          currentWeek: 6,
        ),
      ),
    );
    final context = t.element(find.byKey(const Key('week_selector')));
    expect(Theme.of(context).highlightColor, Colors.transparent);
    final menu = t.widget<PopupMenuButton<int>>(
      find.byKey(const Key('week_selector')),
    );
    expect(menu.initialValue, isNull);
    await t.tap(find.byKey(const Key('week_selector')));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
  testWidgets(
    'menu animates paint transforms with fixed size and delays navigation until closed',
    (t) async {
      String? selected;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: CompactActionMenu(
                entries: const [
                  CompactMenuEntry('import', Icons.download, '导入课表'),
                  CompactMenuEntry('settings', Icons.settings, '设置'),
                ],
                onSelected: (v) => selected = v,
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('更多'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      final size = t.getSize(find.byKey(const Key('compact_menu_surface')));
      final firstScale = t
          .widget<ScaleTransition>(
            find.ancestor(
              of: find.byKey(const Key('compact_menu_surface')),
              matching: find.byType(ScaleTransition),
            ),
          )
          .scale
          .value;
      expect(firstScale, lessThan(1));
      await t.pump(const Duration(milliseconds: 90));
      expect(t.getSize(find.byKey(const Key('compact_menu_surface'))), size);
      expect(
        t
            .widget<ScaleTransition>(
              find.ancestor(
                of: find.byKey(const Key('compact_menu_surface')),
                matching: find.byType(ScaleTransition),
              ),
            )
            .scale
            .value,
        greaterThan(firstScale),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('设置'));
      await t.pump();
      expect(selected, isNull);
      await t.pumpAndSettle();
      expect(selected, 'settings');
      expect(find.byKey(const Key('compact_menu_surface')), findsNothing);
      await t.tap(find.byTooltip('更多'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(20, 500));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('compact_menu_surface')), findsNothing);
      expect(selected, 'settings');
    },
  );
  testWidgets(
    'week list is fully open on first frame and closes without fading rows',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TimetablePage(
            semester: Semester(
              id: 'a',
              name: '学期',
              firstWeekStart: DateTime(2026, 8, 31),
              totalWeeks: 18,
            ),
            courses: const [],
            initialDisplayWeek: 6,
            currentWeek: 6,
          ),
        ),
      );
      await t.tap(find.byKey(const Key('week_selector')));
      await t.pump();
      final surface = find
          .ancestor(of: find.text('第 1 周'), matching: find.byType(Material))
          .first;
      expect(t.getSize(surface).height, greaterThan(200));
      await t.tapAt(const Offset(750, 550));
      await t.pump();
      await t.pump();
      expect(find.text('第 1 周'), findsNothing);
    },
  );
}
