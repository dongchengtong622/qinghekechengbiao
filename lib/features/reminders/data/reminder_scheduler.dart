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

  Future<void> _ensureInitialized() {
    return _initialization ??= gateway.initialize();
  }

  @override
  Future<ReminderPermissionState> permissionState() async {
    await _ensureInitialized();
    return gateway.permissionState();
  }

  @override
  Future<void> replaceAll(List<CourseReminder> reminders) async {
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
  FlutterLocalNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'qinghe_course_reminders';
  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      '课程提醒',
      channelDescription: '在课程开始前 30 分钟提醒',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;
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
      notificationDetails: _notificationDetails,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
    );
  }
}
