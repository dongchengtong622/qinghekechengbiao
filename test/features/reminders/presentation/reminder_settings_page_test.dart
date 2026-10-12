import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/data/ringtone_service.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_diagnostics.dart';
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
  Future<void> pumpPage(
    WidgetTester tester, {
    ReminderSettingChanged? onChanged,
    ValueNotifier<DateTime?>? next,
    bool optionsOnly = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderSettingsPage(
          optionsOnly: optionsOnly,
          repository: repository,
          scheduler: scheduler,
          onChanged: onChanged ?? (_) async {},
          ringtoneService: FakeRingtoneService(),
          vibrationService: FakeVibrationService(),
          nextReminderAtListenable: next,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void ready() {
    repository.enabled = true;
    scheduler.state = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
  }

  for (final title in ['上课提醒', '法定节假日静默']) {
    testWidgets('$title updates within a frame while saving is pending', (
      tester,
    ) async {
      ready();
      repository.holidaySilenceEnabled = true;
      await pumpPage(tester);
      final pending = Completer<void>();
      repository.writeGate = pending.future;
      final tile = find.widgetWithText(SwitchListTile, title);
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
      pending.complete();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('enabling responds before delayed scheduling completes', (
    tester,
  ) async {
    ready();
    repository.enabled = false;
    final pending = Completer<void>();
    await pumpPage(tester, onChanged: (_) => pending.future);
    final tile = find.widgetWithText(SwitchListTile, '上课提醒');
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('enabling rechecks permissions after external revocation', (
    tester,
  ) async {
    ready();
    repository.enabled = false;
    await pumpPage(tester);
    scheduler.state = const ReminderPermissionStatus(
      notificationsAllowed: false,
      exactAlarmsAllowed: true,
    );
    final pending = Completer<void>();
    scheduler.statusGate = pending.future;
    await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
    await tester.pump();
    expect(repository.enabled, isFalse);
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
    expect(find.text('开启课程提醒'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('rapid off-on-off taps persist the final choice in order', (
    tester,
  ) async {
    ready();
    final scheduled = <bool>[];
    await pumpPage(
      tester,
      onChanged: (enabled) async => scheduled.add(enabled),
    );
    final pending = Completer<void>();
    repository.writeGate = pending.future;
    final tile = find.widgetWithText(SwitchListTile, '上课提醒');
    for (final expected in [false, true, false]) {
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.widget<SwitchListTile>(tile).value, expected);
    }
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
    expect(scheduled, [false]);
  });

  testWidgets('save failure restores the stored choice and allows retry', (
    tester,
  ) async {
    ready();
    await pumpPage(tester);
    repository.failWrite = true;
    final tile = find.widgetWithText(SwitchListTile, '上课提醒');
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(find.text('保存提醒设置失败，请重试'), findsOneWidget);
    repository.failWrite = false;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
  });

  testWidgets('leaving the page during save still cancels disabled alarms', (
    tester,
  ) async {
    ready();
    final scheduled = <bool>[];
    await pumpPage(tester, onChanged: (value) async => scheduled.add(value));
    final pending = Completer<void>();
    repository.writeGate = pending.future;
    await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
    expect(scheduled, [false]);
  });

  testWidgets('failed last toggle reconciles the preceding successful save', (
    tester,
  ) async {
    ready();
    final scheduled = <bool>[];
    await pumpPage(tester, onChanged: (value) async => scheduled.add(value));
    final pending = Completer<void>();
    repository.writeGate = pending.future;
    repository.failEnabledValue = true;
    final tile = find.widgetWithText(SwitchListTile, '上课提醒');
    await tester.tap(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
    expect(scheduled, [false]);
  });

  testWidgets('delayed resume permissions do not restore stale preferences', (
    tester,
  ) async {
    ready();
    await pumpPage(tester);
    final pending = Completer<void>();
    scheduler.statusGate = pending.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byKey(const Key('holiday_silence')));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.holidaySilenceEnabled, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('holiday_silence')))
          .value,
      isFalse,
    );
  });

  testWidgets('scheduling failure keeps the successfully saved preference', (
    tester,
  ) async {
    ready();
    await pumpPage(
      tester,
      onChanged: (_) async => throw StateError('schedule'),
    );
    await tester.tap(find.byKey(const Key('holiday_silence')));
    await tester.pumpAndSettle();
    expect(repository.holidaySilenceEnabled, isFalse);
    expect(find.text('提醒调度失败，请重试'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('holiday_silence')))
          .onChanged,
      isNotNull,
    );
  });

  testWidgets(
    'old zero lead configuration can recover without visible disabled options',
    (tester) async {
      scheduler.state = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
      );
      repository.leadMinutes = 0;
      await pumpPage(tester);
      expect(find.byKey(const Key('lead_time')), findsNothing);
      await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提前 30 分钟'));
      await tester.pumpAndSettle();
      expect(repository.enabled, isTrue);
      expect(repository.leadMinutes, 30);
    },
  );
  testWidgets('settings retain alarm options and expose permission entry', (
    tester,
  ) async {
    await pumpPage(tester, optionsOnly: true);
    expect(find.text('铃声'), findsOneWidget);
    expect(find.text('振动'), findsOneWidget);
    expect(find.text('稍后提醒'), findsOneWidget);
    // The permission entry remains reachable below the alarm options.
    await tester.scrollUntilVisible(find.text('课程提醒权限'), 150);
    expect(find.text('课程提醒权限'), findsOneWidget);
    expect(scheduler.notificationRequestCalls, 0);
    expect(repository.enabled, isFalse);
  });
  testWidgets('granted capabilities skip permission requests', (tester) async {
    scheduler.state = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
    await pumpPage(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
    await tester.pumpAndSettle();
    expect(repository.enabled, isTrue);
    expect(scheduler.notificationRequestCalls, 0);
    expect(scheduler.exactAlarmRequestCalls, 0);
  });
  testWidgets(
    'granting notification does not automatically open exact settings',
    (tester) async {
      scheduler.notificationRequestResult = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: false,
      );
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
      await tester.pumpAndSettle();
      expect(scheduler.notificationRequestCalls, 0);
      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();
      expect(scheduler.notificationRequestCalls, 1);
      expect(scheduler.exactAlarmRequestCalls, 0);
      expect(repository.enabled, isFalse);
    },
  );
  testWidgets('denial does not loop or enable reminders', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
    expect(scheduler.notificationRequestCalls, 1);
    expect(scheduler.exactAlarmRequestCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
    'revocation preserves user preference and reports actual capability',
    (tester) async {
      ready();
      await pumpPage(tester, optionsOnly: true);
      scheduler.state = const ReminderPermissionStatus(
        notificationsAllowed: false,
        exactAlarmsAllowed: false,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repository.enabled, isTrue);
      expect(find.textContaining('通知未允许'), findsWidgets);
      expect(scheduler.notificationRequestCalls, 0);
    },
  );
  testWidgets(
    'missing exact capability asks for manual authorization before enabling',
    (tester) async {
      scheduler.state = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: false,
      );
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, '上课提醒'));
      await tester.pumpAndSettle();
      expect(repository.enabled, isFalse);
      expect(scheduler.exactAlarmRequestCalls, 0);
      expect(find.text('开启课程提醒'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repository.enabled, isFalse);
    },
  );
  testWidgets('unchanged resume does not rebuild schedules', (tester) async {
    ready();
    var changed = 0;
    await pumpPage(
      tester,
      onChanged: (_) async {
        changed++;
      },
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(changed, 0);
  });
  testWidgets('ringtone subpage includes categories and persists no sound', (
    tester,
  ) async {
    ready();
    await pumpPage(tester, optionsOnly: true);
    await tester.tap(find.byKey(const Key('reminder_sound')));
    await tester.pumpAndSettle();
    expect(find.text('经典铃声'), findsOneWidget);
    expect(find.text('自然铃声'), findsOneWidget);
    expect(find.text('天气铃声'), findsOneWidget);
    await tester.tap(find.text('无铃声'));
    await tester.pumpAndSettle();
    expect(repository.sound, RingtoneSelection.none);
  });
  testWidgets('snooze subpage persists off and explains total count', (
    tester,
  ) async {
    ready();
    await pumpPage(tester, optionsOnly: true);
    await tester.tap(find.byKey(const Key('snooze_settings')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 次表示首次和后续 2 次'), findsOneWidget);
    await tester.tap(find.byKey(const Key('snooze_enabled')));
    await tester.pumpAndSettle();
    expect(repository.snoozeEnabled, isFalse);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const Key('snooze_interval')),
          )
          .onChanged,
      isNull,
    );
  });
  testWidgets(
    'protection distinguishes banner channel and unknown manufacturer',
    (tester) async {
      scheduler.state = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
        channelHighImportance: false,
      );
      await pumpPage(tester, optionsOnly: true);
      await tester.scrollUntilVisible(find.text('课程提醒权限'), 200);
      await tester.tap(find.text('课程提醒权限'));
      await tester.pumpAndSettle();
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('课程提醒渠道'), findsOneWidget);
      expect(find.text('横幅提醒'), findsOneWidget);
      expect(find.text('锁屏提醒'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('后台运行'), 200);
      expect(find.textContaining('需要检查'), findsWidgets);
      expect(find.textContaining('可能受限'), findsWidgets);
    },
  );
  testWidgets('vibration subpage saves independent rhythm and no vibration', (
    tester,
  ) async {
    ready();
    await pumpPage(tester, optionsOnly: true);
    await tester.tap(find.byKey(const Key('vibration_settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('心跳'));
    await tester.pumpAndSettle();
    expect(repository.vibration, VibrationSelection.heartbeat);
    await tester.tap(find.text('无振动'));
    await tester.pumpAndSettle();
    expect(repository.vibration, VibrationSelection.none);
  });
  testWidgets('next scheduled time is visible and holiday option persists', (
    tester,
  ) async {
    ready();
    final next = ValueNotifier<DateTime?>(DateTime(2026, 10, 1, 8, 25));
    addTearDown(next.dispose);
    await pumpPage(tester, next: next);
    expect(find.textContaining('2026-10-01 08:25'), findsOneWidget);
    await tester.tap(find.byKey(const Key('holiday_silence')));
    await tester.pumpAndSettle();
    expect(repository.holidaySilenceEnabled, isFalse);
  });
}

class FakeRingtoneService implements RingtoneService {
  @override
  Future<RingtoneSelection?> importLocal() async => null;
  @override
  Future<void> preview(RingtoneSelection sound) async {}
  @override
  Future<void> stop() async {}
}

class FakeReminderSettingsRepository implements ReminderSettingsRepository {
  Future<void>? writeGate;
  bool failWrite = false;
  bool? failEnabledValue;
  bool holidaySilenceEnabled = true;

  @override
  Future<void> setHolidaySilenceEnabled(bool enabled) async {
    await writeGate;
    holidaySilenceEnabled = enabled;
  }

  bool snoozeEnabled = true;
  VibrationSelection vibration = VibrationSelection.standard;
  @override
  Future<void> setReminderSnoozeEnabled(bool value) async {
    snoozeEnabled = value;
  }

  @override
  Future<void> setReminderVibration(VibrationSelection value) async {
    vibration = value;
  }

  int snoozeMinutes = 5;
  int maxRings = 2;
  @override
  Future<void> setReminderSnoozeMinutes(int value) async {
    snoozeMinutes = value;
  }

  @override
  Future<void> setReminderMaxRings(int value) async {
    maxRings = value;
  }

  bool enabled = false;
  int leadMinutes = 30;
  RingtoneSelection sound = RingtoneSelection.systemDefault;

  @override
  Future<void> setReminderLeadMinutes(int minutes) async {
    leadMinutes = minutes;
  }

  @override
  Future<void> setReminderSound(RingtoneSelection sound) async {
    this.sound = sound;
  }

  @override
  Future<void> setRemindersEnabled(bool enabled) async {
    await writeGate;
    if (failWrite || failEnabledValue == enabled) throw StateError('save');
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
      snoozeMinutes: snoozeMinutes,
      snoozeEnabled: snoozeEnabled,
      vibration: vibration,
      maxRings: maxRings,
      holidaySilenceEnabled: holidaySilenceEnabled,
    ),
  );
}

class FakeReminderScheduler implements ReminderScheduler {
  Future<void>? statusGate;
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
  Future<ReminderPermissionStatus> permissionStatus() async {
    await statusGate;
    return state;
  }

  @override
  Future<ReminderSyncReport> replaceAll(List<CourseReminder> reminders) async {
    return ReminderSyncReport(
      requested: reminders.length,
      registeredIds: reminders.map((item) => item.id).toSet(),
      nextAt: reminders.isEmpty ? null : reminders.first.scheduledAt,
      failures: const [],
    );
  }

  @override
  Future<void> sendTest({
    required RingtoneSelection sound,
    required Duration delay,
  }) async {}

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

class FakeVibrationService implements VibrationService {
  @override
  Future<bool> preview(VibrationSelection vibration) async => true;
  @override
  Future<void> stop() async {}
}
