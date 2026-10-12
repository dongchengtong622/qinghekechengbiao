import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/settings/presentation/settings_sections.dart';

void main() {
  testWidgets('settings home has five entries and nested semester controls', (
    t,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      await t.runAsync(db.close);
    });
    final r = CourseRepository(db);
    await r.seedIfEmpty();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSections(
            repository: r,
            onChanged: () async {},
            onBackup: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(5));
    for (final label in ['提醒设置', '课表与学期', '作息时间', '数据管理', '关于与帮助']) {
      expect(find.widgetWithText(ListTile, label), findsOneWidget);
    }
    expect(find.text('学期信息'), findsNothing);
    expect(find.text('备份与恢复'), findsNothing);
    await t.tap(find.widgetWithText(ListTile, '课表与学期'));
    await t.pumpAndSettle();
    expect(find.text('学期信息'), findsOneWidget);
    expect(find.text('课表管理'), findsOneWidget);
    expect(find.text('备份与恢复'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
}
