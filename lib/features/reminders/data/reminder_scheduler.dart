import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../domain/reminder_models.dart';

abstract interface class ReminderScheduler {
  Future<void> replaceAll(List<CourseReminder> reminders);

  Future<ReminderPermissionState> requestPermissions();

  Future<ReminderPermissionState> permissionState();
}

abstract interface class NotificationGateway {
  Future<void> initialize();

  Future<void> cancelAll();

  Future<ReminderPermissionState> requestPermissions();

  Future<ReminderPermissionState> permissionState();

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
  Future<ReminderPermissionState> permissionState() async {
    await _ensureInitialized();
    return gateway.permissionState();
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
    final permission = await gateway.permissionState();
    if (permission == ReminderPermissionState.denied) return;
    final exact = permission == ReminderPermissionState.grantedExact;
    for (final reminder in reminders) {
      await gateway.schedule(reminder, exact: exact);
    }
  }

  @override
  Future<ReminderPermissionState> requestPermissions() async {
    await _ensureInitialized();
    return gateway.requestPermissions();
  }
}

class FlutterLocalNotificationGateway implements NotificationGateway {
  FlutterLocalNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    this.onNotificationTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'qinghe_course_reminders';
  NotificationDetails _notificationDetails(ReminderSound sound) {
    final resourceName = switch (sound) {
      ReminderSound.systemDefault => null,
      ReminderSound.chime => 'qinghe_chime',
      ReminderSound.soft => 'qinghe_soft',
      ReminderSound.alert => 'qinghe_alert',
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        '${channelId}_${sound.name}',
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
  late timezone.Location _shanghai;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize() async {
    timezone_data.initializeTimeZones();
    _shanghai = timezone.getLocation('Asia/Shanghai');
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
  Future<ReminderPermissionState> permissionState() async {
    final android = _android;
    final notifications = await android?.areNotificationsEnabled() ?? false;
    if (!notifications) return ReminderPermissionState.denied;
    final exact = await android?.canScheduleExactNotifications() ?? false;
    return exact
        ? ReminderPermissionState.grantedExact
        : ReminderPermissionState.grantedInexact;
  }

  @override
  Future<ReminderPermissionState> requestPermissions() async {
    final android = _android;
    final notifications =
        await android?.requestNotificationsPermission() ?? false;
    if (!notifications) return ReminderPermissionState.denied;
    final exact = await android?.requestExactAlarmsPermission() ?? false;
    return exact
        ? ReminderPermissionState.grantedExact
        : ReminderPermissionState.grantedInexact;
  }

  @override
  Future<void> schedule(CourseReminder reminder, {required bool exact}) async {
    final scheduledAt = reminder.scheduledAt;
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: timezone.TZDateTime(
        _shanghai,
        scheduledAt.year,
        scheduledAt.month,
        scheduledAt.day,
        scheduledAt.hour,
        scheduledAt.minute,
        scheduledAt.second,
      ),
      notificationDetails: _notificationDetails(reminder.sound),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
    );
  }
}
