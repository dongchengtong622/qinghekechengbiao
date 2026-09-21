import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/core/time/shanghai_time.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  late FakeNotificationGateway gateway;
  late AndroidReminderScheduler scheduler;

  setUp(() {
    gateway = FakeNotificationGateway();
    scheduler = AndroidReminderScheduler(gateway);
  });

  final reminder = CourseReminder(
    id: 42,
    scheduledAt: DateTime(2026, 9, 21, 7, 55),
    title: '30分钟后上课：高等数学',
    body: '第1-2节 · A302 · 陈老师',
    payload: 'math',
  );

  test(
    'initializes once and cancels old reminders before replacement',
    () async {
      gateway.permission = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
      );

      await scheduler.replaceAll([reminder]);
      await scheduler.replaceAll([reminder]);

      expect(gateway.initializeCalls, 1);
      expect(gateway.events, [
        'cancelAll',
        'schedule:42:exact',
        'cancelAll',
        'schedule:42:exact',
      ]);
    },
  );

  test(
    'serializes concurrent replacements so the latest request wins',
    () async {
      gateway.permission = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
      );
      gateway.pauseFirstSchedule = true;
      final first = scheduler.replaceAll([reminder]);
      await gateway.firstScheduleStarted.future;
      final latestReminder = CourseReminder(
        id: 84,
        scheduledAt: DateTime(2026, 9, 22, 7, 55),
        title: '30分钟后上课：大学英语',
        body: '第1-2节 · B201 · 李老师',
        payload: 'english',
      );
      final second = scheduler.replaceAll([latestReminder]);

      gateway.releaseFirstSchedule.complete();
      await Future.wait([first, second]);

      expect(gateway.events, [
        'cancelAll',
        'schedule:42:exact',
        'cancelAll',
        'schedule:84:exact',
      ]);
    },
  );

  test('uses inexact scheduling when exact alarms are unavailable', () async {
    gateway.permission = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
    );

    await scheduler.replaceAll([reminder]);

    expect(gateway.events, ['cancelAll', 'schedule:42:inexact']);
  });

  test('does not schedule when notification permission is denied', () async {
    gateway.permission = const ReminderPermissionStatus(
      notificationsAllowed: false,
      exactAlarmsAllowed: false,
    );

    await scheduler.replaceAll([reminder]);

    expect(gateway.events, ['cancelAll']);
  });

  test(
    'keeps notification and exact-alarm permission actions separate',
    () async {
      gateway.permission = const ReminderPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: false,
      );

      final status = await scheduler.permissionStatus();
      expect(status.notificationsAllowed, isTrue);
      expect(status.exactAlarmsAllowed, isFalse);
      expect(gateway.notificationRequestCalls, 0);
      expect(gateway.exactAlarmRequestCalls, 0);

      await scheduler.requestNotificationPermission();
      await scheduler.requestExactAlarmPermission();
      await scheduler.openNotificationSettings();

      expect(gateway.notificationRequestCalls, 1);
      expect(gateway.exactAlarmRequestCalls, 1);
      expect(gateway.openNotificationSettingsCalls, 1);
    },
  );

  test('uses distinct channels and matching raw resources for each sound', () {
    expect(
      ReminderSound.values
          .map(FlutterLocalNotificationGateway.channelIdFor)
          .toSet(),
      hasLength(ReminderSound.values.length),
    );
    expect(
      FlutterLocalNotificationGateway.resourceNameFor(ReminderSound.chime),
      'qinghe_chime',
    );
    expect(
      FlutterLocalNotificationGateway.resourceNameFor(ReminderSound.soft),
      'qinghe_soft',
    );
    expect(
      FlutterLocalNotificationGateway.resourceNameFor(ReminderSound.alert),
      'qinghe_alert',
    );
  });

  test('normalizes scheduled instants to the Shanghai location', () {
    final result = FlutterLocalNotificationGateway.toShanghaiSchedule(
      DateTime.utc(2026, 9, 20, 23, 55),
    );

    expect(result, isA<timezone.TZDateTime>());
    expect(result.location, ShanghaiTime.location);
    expect(result.toIso8601String(), '2026-09-21T07:55:00.000+0800');
  });
}

class FakeNotificationGateway implements NotificationGateway {
  ReminderPermissionStatus permission = const ReminderPermissionStatus(
    notificationsAllowed: false,
    exactAlarmsAllowed: false,
  );
  int initializeCalls = 0;
  int notificationRequestCalls = 0;
  int exactAlarmRequestCalls = 0;
  int openNotificationSettingsCalls = 0;
  final events = <String>[];
  bool pauseFirstSchedule = false;
  final firstScheduleStarted = Completer<void>();
  final releaseFirstSchedule = Completer<void>();

  @override
  Future<void> cancelAll() async => events.add('cancelAll');

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async => permission;

  @override
  Future<void> openNotificationSettings() async {
    openNotificationSettingsCalls++;
  }

  @override
  Future<ReminderPermissionStatus> requestExactAlarmPermission() async {
    exactAlarmRequestCalls++;
    return permission;
  }

  @override
  Future<ReminderPermissionStatus> requestNotificationPermission() async {
    notificationRequestCalls++;
    return permission;
  }

  @override
  Future<void> schedule(CourseReminder reminder, {required bool exact}) async {
    events.add('schedule:${reminder.id}:${exact ? 'exact' : 'inexact'}');
    if (pauseFirstSchedule && !firstScheduleStarted.isCompleted) {
      firstScheduleStarted.complete();
      await releaseFirstSchedule.future;
    }
  }
}
