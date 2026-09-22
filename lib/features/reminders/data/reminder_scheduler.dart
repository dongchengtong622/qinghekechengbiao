import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../core/time/shanghai_time.dart';
import '../domain/reminder_diagnostics.dart';
import '../domain/reminder_models.dart';

abstract interface class ReminderScheduler {
  Future<ReminderSyncReport> replaceAll(List<CourseReminder> reminders);

  Future<void> sendTest({
    required ReminderSound sound,
    required Duration delay,
  });

  Future<ReminderPermissionStatus> requestNotificationPermission();

  Future<ReminderPermissionStatus> requestExactAlarmPermission();

  Future<void> openNotificationSettings();

  Future<ReminderPermissionStatus> permissionStatus();
}

abstract interface class NotificationGateway {
  Future<void> initialize();

  Future<void> cancelAll();

  Future<void> cancel(int id);

  Future<Set<int>> pendingIds();

  Future<ReminderPermissionStatus> requestNotificationPermission();

  Future<ReminderPermissionStatus> requestExactAlarmPermission();

  Future<void> openNotificationSettings();

  Future<ReminderPermissionStatus> permissionStatus();

  Future<void> schedule(CourseReminder reminder, {required bool exact});

  Future<void> showTest(CourseReminder reminder);
}

class AndroidReminderScheduler implements ReminderScheduler {
  AndroidReminderScheduler(this.gateway);

  final NotificationGateway gateway;
  Future<void>? _initialization;
  Future<void> _replacementQueue = Future.value();

  Future<void> _ensureInitialized() async {
    final active = _initialization;
    if (active != null) return active;
    final attempt = gateway.initialize();
    _initialization = attempt;
    try {
      await attempt;
    } catch (_) {
      if (identical(_initialization, attempt)) _initialization = null;
      rethrow;
    }
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async {
    await _ensureInitialized();
    return gateway.permissionStatus();
  }

  @override
  Future<ReminderSyncReport> replaceAll(List<CourseReminder> reminders) {
    final replacement = _replacementQueue.then(
      (_) => _replaceAllNow(List.unmodifiable(reminders)),
    );
    _replacementQueue = replacement.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return replacement;
  }

  Future<ReminderSyncReport> _replaceAllNow(
    List<CourseReminder> reminders,
  ) async {
    await _ensureInitialized();
    final planningFailure = _validate(reminders);
    if (planningFailure != null) {
      return _report(reminders, failures: [planningFailure]);
    }

    Set<int> previous;
    try {
      previous = await gateway.pendingIds();
    } catch (error) {
      return _report(
        reminders,
        failures: [_failure(ReminderStage.verification, error, '无法核对系统提醒')],
      );
    }

    if (reminders.isEmpty) {
      final failures = <ReminderFailure>[];
      for (final id in previous.where(_isCourseId)) {
        try {
          await gateway.cancel(id);
        } catch (error) {
          failures.add(_failure(ReminderStage.registration, error, '关闭课程提醒失败'));
        }
      }
      return _report(reminders, failures: failures);
    }

    final permission = await gateway.permissionStatus();
    if (!permission.notificationsAllowed) {
      return _report(
        reminders,
        failures: const [
          ReminderFailure(
            stage: ReminderStage.permissions,
            code: 'notifications_disabled',
            message: '通知权限未开启',
          ),
        ],
      );
    }

    final failures = <ReminderFailure>[];
    for (final reminder in reminders) {
      try {
        await gateway.schedule(reminder, exact: permission.exactAlarmsAllowed);
      } on PlatformException catch (error) {
        if (permission.exactAlarmsAllowed && _isExactAlarmError(error.code)) {
          try {
            await gateway.schedule(reminder, exact: false);
            failures.add(
              const ReminderFailure(
                stage: ReminderStage.registration,
                code: 'exact_fallback',
                message: '精确闹钟权限发生变化，已改为非精确提醒',
              ),
            );
          } catch (fallbackError) {
            failures.add(
              _failure(ReminderStage.registration, fallbackError, '设置提醒失败'),
            );
          }
        } else {
          failures.add(_failure(ReminderStage.registration, error, '设置提醒失败'));
        }
      } catch (error) {
        failures.add(_failure(ReminderStage.registration, error, '设置提醒失败'));
      }
    }

    Set<int> confirmed;
    try {
      confirmed = await gateway.pendingIds();
    } catch (error) {
      failures.add(_failure(ReminderStage.verification, error, '无法核对系统提醒'));
      return _report(reminders, failures: failures);
    }

    final desiredIds = reminders.map((item) => item.id).toSet();
    final registered = desiredIds.intersection(confirmed);
    final blockingFailures = failures.where(
      (failure) => failure.code != 'exact_fallback',
    );
    if (blockingFailures.isEmpty && registered.length == desiredIds.length) {
      for (final stale in previous.where(
        (id) => _isCourseId(id) && !desiredIds.contains(id),
      )) {
        try {
          await gateway.cancel(stale);
        } catch (error) {
          failures.add(_failure(ReminderStage.registration, error, '清理过期提醒失败'));
        }
      }
    }

    return _report(reminders, registeredIds: registered, failures: failures);
  }

  ReminderFailure? _validate(List<CourseReminder> reminders) {
    final ids = <int>{};
    for (final reminder in reminders) {
      if (!_isCourseId(reminder.id)) {
        return const ReminderFailure(
          stage: ReminderStage.planning,
          code: 'reserved_id',
          message: '提醒编号超出课程范围',
        );
      }
      if (!ids.add(reminder.id)) {
        return const ReminderFailure(
          stage: ReminderStage.planning,
          code: 'duplicate_id',
          message: '课程提醒编号重复',
        );
      }
    }
    return null;
  }

  ReminderSyncReport _report(
    List<CourseReminder> reminders, {
    Set<int> registeredIds = const {},
    List<ReminderFailure> failures = const [],
  }) {
    DateTime? nextAt;
    for (final reminder in reminders) {
      if (!registeredIds.contains(reminder.id)) continue;
      if (nextAt == null || reminder.scheduledAt.isBefore(nextAt)) {
        nextAt = reminder.scheduledAt;
      }
    }
    return ReminderSyncReport(
      requested: reminders.length,
      registeredIds: registeredIds,
      nextAt: nextAt,
      failures: failures,
    );
  }

  bool _isCourseId(int id) => id >= 1 && id <= maxCourseNotificationId;

  bool _isExactAlarmError(String code) {
    final normalized = code.toLowerCase();
    return normalized.contains('exact') && normalized.contains('alarm');
  }

  ReminderFailure _failure(ReminderStage stage, Object error, String message) {
    return ReminderFailure(
      stage: stage,
      code: error is PlatformException ? error.code : 'unexpected',
      message: message,
    );
  }

  @override
  Future<void> sendTest({
    required ReminderSound sound,
    required Duration delay,
  }) async {
    await _ensureInitialized();
    final permission = await gateway.permissionStatus();
    if (!permission.notificationsAllowed) {
      throw PlatformException(
        code: 'notifications_disabled',
        message: '通知权限未开启',
      );
    }
    final immediate = delay <= Duration.zero;
    final reminder = CourseReminder(
      id: immediate ? immediateTestNotificationId : delayedTestNotificationId,
      scheduledAt: ShanghaiTime.now().add(delay),
      title: '青禾课表测试提醒',
      body: immediate ? '立即测试通知' : '1分钟测试通知',
      payload: 'reminder-test',
      sound: sound,
    );
    if (immediate) {
      await gateway.showTest(reminder);
      return;
    }
    try {
      await gateway.schedule(reminder, exact: permission.exactAlarmsAllowed);
    } on PlatformException catch (error) {
      if (!permission.exactAlarmsAllowed || !_isExactAlarmError(error.code)) {
        rethrow;
      }
      await gateway.schedule(reminder, exact: false);
    }
  }

  @override
  Future<ReminderPermissionStatus> requestNotificationPermission() async {
    await _ensureInitialized();
    return gateway.requestNotificationPermission();
  }

  @override
  Future<ReminderPermissionStatus> requestExactAlarmPermission() async {
    await _ensureInitialized();
    return gateway.requestExactAlarmPermission();
  }

  @override
  Future<void> openNotificationSettings() async {
    await _ensureInitialized();
    await gateway.openNotificationSettings();
  }
}

class FlutterLocalNotificationGateway implements NotificationGateway {
  FlutterLocalNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    this.onNotificationTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'qinghe_course_reminders';
  static String channelIdFor(ReminderSound sound) =>
      '${channelId}_${sound.name}';

  static String? resourceNameFor(ReminderSound sound) => switch (sound) {
    ReminderSound.systemDefault => null,
    ReminderSound.chime => 'qinghe_chime',
    ReminderSound.soft => 'qinghe_soft',
    ReminderSound.alert => 'qinghe_alert',
  };

  NotificationDetails _notificationDetails(ReminderSound sound) {
    final resourceName = resourceNameFor(sound);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelIdFor(sound),
        '课程提醒',
        channelDescription: '按设定时间提醒课程',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: resourceName == null
            ? null
            : RawResourceAndroidNotificationSound(resourceName),
        enableVibration: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.reminder,
      ),
    );
  }

  final FlutterLocalNotificationsPlugin _plugin;
  final void Function(String? payload)? onNotificationTap;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize() async {
    ShanghaiTime.ensureInitialized();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response.payload);
      },
    );
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<Set<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((item) => item.id).toSet();
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async {
    final android = _android;
    final notifications = await android?.areNotificationsEnabled() ?? false;
    final exact = await android?.canScheduleExactNotifications() ?? false;
    return ReminderPermissionStatus(
      notificationsAllowed: notifications,
      exactAlarmsAllowed: exact,
    );
  }

  @override
  Future<ReminderPermissionStatus> requestNotificationPermission() async {
    await _android?.requestNotificationsPermission();
    return permissionStatus();
  }

  @override
  Future<ReminderPermissionStatus> requestExactAlarmPermission() async {
    await _android?.requestExactAlarmsPermission();
    return permissionStatus();
  }

  @override
  Future<void> openNotificationSettings() async {
    await _android?.openAppNotificationSettings();
  }

  @override
  Future<void> schedule(CourseReminder reminder, {required bool exact}) async {
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: toShanghaiSchedule(reminder.scheduledAt),
      notificationDetails: _notificationDetails(reminder.sound),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
    );
  }

  @override
  Future<void> showTest(CourseReminder reminder) {
    return _plugin.show(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      notificationDetails: _notificationDetails(reminder.sound),
      payload: reminder.payload,
    );
  }

  static timezone.TZDateTime toShanghaiSchedule(DateTime value) {
    return ShanghaiTime.fromUtc(value.toUtc());
  }
}
