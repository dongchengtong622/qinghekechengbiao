import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_page.dart';
import 'package:qinghe_timetable/features/reminders/presentation/reminder_settings_page.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'features/reminders/presentation/reminder_settings_page_test.dart'
    show FakeReminderSettingsRepository, FakeReminderScheduler;

void main() {
  testWidgets(
    'next reminder shows actual course details without empty placeholders',
    (t) async {
      final next = ValueNotifier<CourseReminder?>(
        CourseReminder(
          id: 1,
          scheduledAt: DateTime(2026, 10, 7, 9, 40),
          title: '上课',
          body: '',
          payload: '',
          courseName: '数据结构',
          teacher: '王涛',
          room: '南湖A109',
          dateLabel: '2026年10月7日 星期三',
          timeLabel: '10:10–11:50',
          sectionLabel: '第3–4节',
          weekLabel: '第1–16周',
        ),
      );
      addTearDown(next.dispose);
      final actual = ValueNotifier<DateTime?>(DateTime(2026, 10, 7, 9, 45));
      addTearDown(actual.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: ReminderSettingsPage(
            repository: FakeReminderSettingsRepository(),
            scheduler: FakeReminderScheduler(),
            onChanged: (_) async {},
            nextReminderListenable: next,
            nextReminderAtListenable: actual,
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final label in [
        '数据结构',
        '教师：王涛',
        '教室：南湖A109',
        '上课：10:10–11:50',
        '第3–4节',
        '第1–16周',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('2026-10-07 09:45'), findsOneWidget);
      next.value = null;
      await t.pump();
      expect(find.text('暂无已安排提醒'), findsOneWidget);
    },
  );
  testWidgets('home places actions in more menu, no app title or bottom add', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: TimetablePage(
          semester: Semester(
            id: 'a',
            name: '秋季学期',
            firstWeekStart: DateTime(2026, 9, 7),
            totalWeeks: 20,
          ),
          courses: const [],
          initialDisplayWeek: 1,
          currentWeek: 1,
          onAdd: () {},
          onImport: () {},
          onReminders: () {},
        ),
      ),
    );
    expect(find.text('青禾课表'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    await t.tap(find.byKey(const Key('home_more')));
    await t.pumpAndSettle();
    for (final s in ['导入课表', '课程提醒', '桌面小组件', '设置']) {
      expect(find.text(s), findsOneWidget);
    }
  });
  testWidgets('reminders hide disabled suboptions and advanced controls', (
    t,
  ) async {
    final r = FakeReminderSettingsRepository();
    final s = FakeReminderScheduler();
    await t.pumpWidget(
      MaterialApp(
        home: ReminderSettingsPage(
          repository: r,
          scheduler: s,
          onChanged: (_) async {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('法定节假日静默'), findsNothing);
    expect(find.text('铃声'), findsNothing);
    expect(find.text('课程提醒权限'), findsNothing);
    expect(find.text('下一次已安排提醒'), findsOneWidget);
  });
  testWidgets(
    'missing exact permission requires consent, remains off on return',
    (t) async {
      final r = FakeReminderSettingsRepository();
      final s = FakeReminderScheduler();
      s.state = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: false,
        sdkInt: 34,
      );
      await t.pumpWidget(
        MaterialApp(
          home: ReminderSettingsPage(
            repository: r,
            scheduler: s,
            onChanged: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
      await t.pumpAndSettle();
      expect(find.text('去设置'), findsOneWidget);
      expect(r.enabled, isFalse);
      await t.tap(find.text('去设置'));
      await t.pumpAndSettle();
      expect(r.enabled, isFalse);
      expect(s.exactAlarmRequestCalls, 1);
    },
  );
}
