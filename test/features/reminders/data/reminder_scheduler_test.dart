import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';

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
      gateway.permission = ReminderPermissionState.grantedExact;

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
      gateway.permission = ReminderPermissionState.grantedExact;
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
    gateway.permission = ReminderPermissionState.grantedInexact;

    await scheduler.replaceAll([reminder]);

    expect(gateway.events, ['cancelAll', 'schedule:42:inexact']);
  });

  test('does not schedule when notification permission is denied', () async {
    gateway.permission = ReminderPermissionState.denied;

    await scheduler.replaceAll([reminder]);

    expect(gateway.events, ['cancelAll']);
  });

  test(
    'requests permissions only through the explicit request method',
    () async {
      gateway.permission = ReminderPermissionState.grantedInexact;

      expect(
        await scheduler.permissionState(),
        ReminderPermissionState.grantedInexact,
      );
      expect(gateway.requestCalls, 0);

      expect(
        await scheduler.requestPermissions(),
        ReminderPermissionState.grantedInexact,
      );
      expect(gateway.requestCalls, 1);
    },
  );
}

class FakeNotificationGateway implements NotificationGateway {
  ReminderPermissionState permission = ReminderPermissionState.denied;
  int initializeCalls = 0;
  int requestCalls = 0;
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
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermissions() async {
    requestCalls++;
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
