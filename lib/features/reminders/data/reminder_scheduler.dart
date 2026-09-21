import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../core/time/shanghai_time.dart';
import '../domain/reminder_models.dart';

abstract interface class ReminderScheduler {
  Future<void> replaceAll(List<CourseReminder> reminders);

  Future<ReminderPermissionStatus> requestNotificationPermission();

  Future<ReminderPermissionStatus> requestExactAlarmPermission();

  Future<void> openNotificationSettings();

  Future<ReminderPermissionStatus> permissionStatus();
}

abstract interface class NotificationGateway {
  Future<void> initialize();

  Future<void> cancelAll();

  Future<ReminderPermissionStatus> requestNotificationPermission();

  Future<ReminderPermissionStatus> requestExactAlarmPermission();

  Future<void> openNotificationSettings();

  Future<ReminderPermissionStatus> permissionStatus();

  Future<void> schedule(CourseReminder reminder, {required bool exact});
}

class AndroidReminderScheduler implements ReminderScheduler {
  AndroidReminderScheduler(this.gateway);

  final NotificationGateway gateway;
  Future<void>? _initialization;
  Future<void> _replacementQueue = Future.value();

  Future<void> _ensureInitialized() {
    return _initialization ??= gateway.initialize();
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async {
    await _ensureInitialized();
    return gateway.permissionStatus();
  }

  @override
  Future<void> replaceAll(List<CourseReminder> reminders) {
    final replacement = _replacementQueue.then(
      (_) => _replaceAllNow(List.unmodifiable(reminders)),
    );
    _replacementQueue = replacement.catchError((Object _) {});
    return replacement;
  }

  Future<void> _replaceAllNow(List<CourseReminder> reminders) async {
    await _ensureInitialized();
    await gateway.cancelAll();
    final permission = await gateway.permissionStatus();
    if (!permission.notificationsAllowed) return;
    final exact = permission.exactAlarmsAllowed;
    for (final reminder in reminders) {
      await gateway.schedule(reminder, exact: exact);
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

  static timezone.TZDateTime toShanghaiSchedule(DateTime value) {
    return ShanghaiTime.fromUtc(value.toUtc());
  }
}
