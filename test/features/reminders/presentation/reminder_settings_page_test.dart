import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_settings_repository.dart';
import 'package:qinghe_timetable/features/reminders/presentation/reminder_settings_page.dart';

void main() {
  late FakeReminderSettingsRepository repository;
  late FakeReminderScheduler scheduler;

  setUp(() {
    repository = FakeReminderSettingsRepository();
    scheduler = FakeReminderScheduler();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderSettingsPage(
          repository: repository,
          scheduler: scheduler,
          onChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('allows changing lead time and reminder sound', (tester) async {
    await pumpPage(tester);

    await tester.ensureVisible(find.byKey(const Key('lead_time')));
    await tester.tap(find.byKey(const Key('lead_time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提前 10 分钟').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('reminder_sound')));
    await tester.tap(find.byKey(const Key('reminder_sound')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('柔和铃声').last);
    await tester.pumpAndSettle();

    expect(repository.leadMinutes, 10);
    expect(repository.sound, ReminderSound.soft);
  });

  testWidgets('does not request permission before a user enables reminders', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(scheduler.requestCalls, 0);
    expect(find.text('提前 30 分钟'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('persists enabled state after permission is granted', (
    tester,
  ) async {
    scheduler.notificationRequestResult = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(scheduler.notificationRequestCalls, 1);
    expect(await repository.watchRemindersEnabled().first, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('shows delayed warning when only inexact alarms are available', (
    tester,
  ) async {
    scheduler.notificationRequestResult = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
    );
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('提醒可能因系统限制而延迟'), 200);
    expect(find.text('提醒可能因系统限制而延迟'), findsOneWidget);
    expect(await repository.watchRemindersEnabled().first, isTrue);
  });

  testWidgets('keeps reminders disabled when notifications are denied', (
    tester,
  ) async {
    scheduler.notificationRequestResult = const ReminderPermissionStatus(
      notificationsAllowed: false,
      exactAlarmsAllowed: false,
    );
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(await repository.watchRemindersEnabled().first, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('通知权限未开启，无法启用课程提醒'), findsOneWidget);
  });

  testWidgets('recovers the switch after a scheduler failure', (tester) async {
    scheduler.throwOnRequest = true;
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('提醒设置失败，请稍后重试'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('shows separate permission rows and effective schedule mode', (
    tester,
  ) async {
    scheduler.state = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
    );

    await pumpPage(tester);

    expect(find.text('通知权限'), findsOneWidget);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('精确闹钟权限'), findsOneWidget);
    expect(find.text('未开启'), findsOneWidget);
    expect(find.text('当前调度模式'), findsOneWidget);
    expect(find.text('非精确（可能延迟）'), findsOneWidget);
  });

  testWidgets('opens matching Android permission actions', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('request_notification_permission')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_notification_settings')));
    await tester.pumpAndSettle();

    scheduler.state = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
    );
    await tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request_exact_alarm_permission')));
    await tester.pumpAndSettle();

    expect(scheduler.notificationRequestCalls, 1);
    expect(scheduler.openNotificationSettingsCalls, 1);
    expect(scheduler.exactAlarmRequestCalls, 1);
  });
}

class FakeReminderSettingsRepository implements ReminderSettingsRepository {
  bool enabled = false;
  int leadMinutes = 30;
  ReminderSound sound = ReminderSound.systemDefault;

  @override
  Future<void> setReminderLeadMinutes(int minutes) async {
    leadMinutes = minutes;
  }

  @override
  Future<void> setReminderSound(ReminderSound sound) async {
    this.sound = sound;
  }

  @override
  Future<void> setRemindersEnabled(bool enabled) async {
    this.enabled = enabled;
  }

  @override
  Stream<bool> watchRemindersEnabled() => Stream.value(enabled);

  @override
  Stream<ReminderPreferences> watchReminderPreferences() => Stream.value(
    ReminderPreferences(
      enabled: enabled,
      leadMinutes: leadMinutes,
      sound: sound,
    ),
  );
}

class FakeReminderScheduler implements ReminderScheduler {
  ReminderPermissionStatus state = const ReminderPermissionStatus(
    notificationsAllowed: false,
    exactAlarmsAllowed: false,
  );
  ReminderPermissionStatus notificationRequestResult =
      const ReminderPermissionStatus(
        notificationsAllowed: false,
        exactAlarmsAllowed: false,
      );
  ReminderPermissionStatus exactAlarmRequestResult =
      const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
      );
  int notificationRequestCalls = 0;
  int exactAlarmRequestCalls = 0;
  int openNotificationSettingsCalls = 0;
  bool throwOnRequest = false;

  @override
  Future<ReminderPermissionStatus> permissionStatus() async => state;

  @override
  Future<void> replaceAll(List<CourseReminder> reminders) async {}

  @override
  Future<void> openNotificationSettings() async {
    openNotificationSettingsCalls++;
  }

  @override
  Future<ReminderPermissionStatus> requestExactAlarmPermission() async {
    exactAlarmRequestCalls++;
    state = exactAlarmRequestResult;
    return state;
  }

  @override
  Future<ReminderPermissionStatus> requestNotificationPermission() async {
    notificationRequestCalls++;
    if (throwOnRequest) throw StateError('scheduler failed');
    state = notificationRequestResult;
    return state;
  }
}
