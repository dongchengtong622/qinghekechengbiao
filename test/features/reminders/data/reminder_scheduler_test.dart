import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/core/time/shanghai_time.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_diagnostics.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  late FakeNotificationGateway gateway;
  late AndroidReminderScheduler scheduler;

  setUp(() {
    gateway = FakeNotificationGateway();
    scheduler = AndroidReminderScheduler(gateway);
  });

  CourseReminder reminder(int id) => CourseReminder(
    id: id,
    scheduledAt: DateTime.utc(2026, 9, 21, 0, id.clamp(0, 59)),
    title: '课程提醒',
    body: '第1-2节',
    payload: 'course-$id',
  );

  test('reconciles verified reminders before deleting stale alarms', () async {
    gateway.allowNotifications();
    gateway.pending.addAll({11, 12, immediateTestNotificationId});

    final report = await scheduler.replaceAll([reminder(12), reminder(13)]);

    expect(report.failures, isEmpty);
    expect(report.registeredIds, {12, 13});
    expect(gateway.calls, isNot(contains('cancelAll')));
    expect(gateway.calls, contains('cancel:11'));
    expect(gateway.pending, {12, 13, immediateTestNotificationId});
  });

  test('keeps old reminders and test alarms after partial failure', () async {
    gateway.allowNotifications();
    gateway.pending.addAll({11, 12, immediateTestNotificationId});
    gateway.failedIds.add(13);

    final report = await scheduler.replaceAll([reminder(12), reminder(13)]);

    expect(report.failures.single.stage, ReminderStage.registration);
    expect(gateway.calls, isNot(contains('cancelAll')));
    expect(gateway.pending, containsAll({11, 12, immediateTestNotificationId}));
  });

  test('does not delete alarms when verification fails', () async {
    gateway.allowNotifications();
    gateway.pending.addAll({11, 12});
    gateway.failPendingAfterSchedule = true;

    final report = await scheduler.replaceAll([reminder(12)]);

    expect(report.failures.single.stage, ReminderStage.verification);
    expect(gateway.calls, isNot(contains('cancel:11')));
  });

  test('explicit disable cancels courses but preserves test alarms', () async {
    gateway.pending.addAll({
      11,
      12,
      delayedTestNotificationId,
      immediateTestNotificationId,
    });

    final report = await scheduler.replaceAll(const []);

    expect(report.failures, isEmpty);
    expect(gateway.pending, {
      delayedTestNotificationId,
      immediateTestNotificationId,
    });
  });

  test(
    'rejects duplicate and reserved course IDs before registration',
    () async {
      final duplicate = await scheduler.replaceAll([
        reminder(12),
        reminder(12),
      ]);
      final reserved = await scheduler.replaceAll([
        reminder(delayedTestNotificationId),
      ]);

      expect(duplicate.failures.single.stage, ReminderStage.planning);
      expect(reserved.failures.single.stage, ReminderStage.planning);
      expect(
        gateway.calls.where((item) => item.startsWith('schedule:')),
        isEmpty,
      );
    },
  );

  test(
    'reports denied notification permission without clearing alarms',
    () async {
      gateway.pending.add(11);

      final report = await scheduler.replaceAll([reminder(12)]);

      expect(report.failures.single.stage, ReminderStage.permissions);
      expect(gateway.pending, contains(11));
    },
  );

  test('falls back after an explicit exact-alarm platform error', () async {
    gateway.allowNotifications();
    gateway.rejectExactOnce = true;

    final report = await scheduler.replaceAll([reminder(12)]);

    expect(
      gateway.calls,
      containsAllInOrder(['schedule:12:exact', 'schedule:12:inexact']),
    );
    expect(report.registeredIds, {12});
    expect(report.failures.single.code, 'exact_fallback');
  });

  test('sends immediate and delayed tests through native paths', () async {
    gateway.allowNotifications();

    await scheduler.sendTest(sound: ReminderSound.chime, delay: Duration.zero);
    await scheduler.sendTest(
      sound: ReminderSound.soft,
      delay: const Duration(minutes: 1),
    );

    expect(gateway.calls, contains('show:$immediateTestNotificationId'));
    expect(
      gateway.calls,
      contains('schedule:$delayedTestNotificationId:exact'),
    );
  });

  test('serializes replacements so the latest request wins', () async {
    gateway.allowNotifications();
    gateway.pauseFirstSchedule = true;
    final first = scheduler.replaceAll([reminder(42)]);
    await gateway.firstScheduleStarted.future;
    final second = scheduler.replaceAll([reminder(43)]);
    gateway.releaseFirstSchedule.complete();
    await Future.wait([first, second]);

    expect(gateway.pending, {43});
  });

  test('keeps permission actions separate', () async {
    gateway.permission = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: false,
    );

    await scheduler.requestNotificationPermission();
    await scheduler.requestExactAlarmPermission();
    await scheduler.openNotificationSettings();

    expect(gateway.notificationRequestCalls, 1);
    expect(gateway.exactAlarmRequestCalls, 1);
    expect(gateway.openNotificationSettingsCalls, 1);
  });

  test('uses distinct sound channels and Shanghai schedule times', () {
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
  final pending = <int>{};
  final failedIds = <int>{};
  final calls = <String>[];
  bool failPendingAfterSchedule = false;
  bool rejectExactOnce = false;
  bool pauseFirstSchedule = false;
  var scheduleCalls = 0;
  int notificationRequestCalls = 0;
  int exactAlarmRequestCalls = 0;
  int openNotificationSettingsCalls = 0;
  final firstScheduleStarted = Completer<void>();
  final releaseFirstSchedule = Completer<void>();

  void allowNotifications() {
    permission = const ReminderPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  Future<void> cancel(int id) async {
    calls.add('cancel:' + id.toString());
    pending.remove(id);
  }

  @override
  Future<void> initialize() async {}

  Future<Set<int>> pendingIds() async {
    calls.add('pending');
    if (failPendingAfterSchedule && scheduleCalls > 0) {
      throw const PlatformException(code: 'pending_failed');
    }
    return Set.of(pending);
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
    scheduleCalls++;
    calls.add(
      'schedule:' +
          reminder.id.toString() +
          ':' +
          (exact ? 'exact' : 'inexact'),
    );
    if (pauseFirstSchedule && !firstScheduleStarted.isCompleted) {
      firstScheduleStarted.complete();
      await releaseFirstSchedule.future;
    }
    if (rejectExactOnce && exact) {
      rejectExactOnce = false;
      throw const PlatformException(code: 'exact_alarm_denied');
    }
    if (failedIds.contains(reminder.id)) {
      throw const PlatformException(code: 'schedule_failed');
    }
    pending.add(reminder.id);
  }

  Future<void> showTest(CourseReminder reminder) async {
    calls.add('show:' + reminder.id.toString());
    pending.add(reminder.id);
  }
}
