import 'package:flutter/services.dart';
import '../domain/reminder_diagnostics.dart';
import '../domain/reminder_models.dart';
import 'reminder_scheduler.dart';

class NativeAlarmScheduler implements ReminderScheduler {
  NativeAlarmScheduler({this.migrateLegacy});
  static const channel = MethodChannel('com.qinghe.timetable/alarms');
  final Future<void> Function()? migrateLegacy;
  final _legacy = FlutterLocalNotificationGateway();
  bool _migrated = false;
  Future<void> _queue = Future.value();

  @override
  Future<ReminderSyncReport> replaceAll(List<CourseReminder> reminders) {
    final result = _queue.then((_) async {
      // Retire the old plugin before native cards can be published. The native
      // marker avoids cancelling a live native alarm on each application start.
      if (!_migrated) {
        if (migrateLegacy != null) {
          await migrateLegacy!();
        } else if (await channel.invokeMethod<bool>(
              'legacyMigrationRequired',
            ) ??
            false) {
          await _legacy.initialize();
          await _legacy.cancelAll();
          await channel.invokeMethod<void>('markLegacyMigrated');
        }
        _migrated = true;
      }
      final payload = reminders
          .map(
            (r) => <String, Object?>{
              'key':
                  r.occurrenceKey ??
                  '${r.payload}|${r.scheduledAt.millisecondsSinceEpoch}',
              'id': r.id,
              'at': r.scheduledAt.millisecondsSinceEpoch,
              'deadline':
                  r.classStartAt?.millisecondsSinceEpoch ??
                  r.scheduledAt
                      .add(const Duration(minutes: 1))
                      .millisecondsSinceEpoch,
              'title': r.title,
              'body': r.body,
              'resource': r.sound.resourceName,
              'uri': r.sound.contentUri,
              'interval': r.snoozeMinutes,
              'limit': r.snoozeEnabled ? r.maxRings : 1,
              'snoozeEnabled': r.snoozeEnabled,
              'silent': r.sound.isSilent,
              'vibration': r.vibration.name,
              'courseName': r.courseName,
              'teacher': r.teacher,
              'room': r.room,
              'dateLabel': r.dateLabel,
              'timeLabel': r.timeLabel,
              'sectionLabel': r.sectionLabel,
              'weekLabel': r.weekLabel,
              'classEndAt': r.classEndAt?.millisecondsSinceEpoch,
            },
          )
          .toList();
      final reply =
          await channel.invokeMapMethod<String, dynamic>(
            'replaceAll',
            payload,
          ) ??
          {};
      return ReminderSyncReport(
        requested: reminders.length,
        nextId: reply['nextId'] as int?,
        registeredIds: Set<int>.from(reply['ids'] as List? ?? []),
        nextAt: reply['nextAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(reply['nextAt'] as int),
        failures: [
          for (final failure in (reply['failures'] as List? ?? []))
            ReminderFailure(
              stage: ReminderStage.registration,
              code: (failure as Map)['code'] as String? ?? 'register_failed',
              message: failure['message'] as String? ?? '注册提醒失败',
            ),
        ],
      );
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<ReminderPermissionStatus> permissionStatus() async {
    final s = await channel.invokeMapMethod<String, dynamic>('status') ?? {};
    return ReminderPermissionStatus(
      notificationsAllowed: s['notificationsAllowed'] == true,
      exactAlarmsAllowed: s['exactAlarmsAllowed'] == true,
      fullScreenAllowed: s['fullScreenAllowed'] == true,
      batteryUnrestricted: s['batteryUnrestricted'] == true,
      channelHighImportance: s['channelHighImportance'] == true,
      channelAllowed: s['channelAllowed'] == true,
      sdkInt: s['sdkInt'] as int? ?? 0,
      backgroundRestricted: s['backgroundRestricted'] == true,
      channelUserSilenced: s['channelUserSilenced'] == true,
      channelSilent: s['channelSilent'] == true,
      channelUserSoundSet: s['channelUserSoundSet'] == true,
      explicitAudioConsent: s['explicitAudioConsent'] == true,
      diagnostics: s['diagnostics'] as String? ?? '',
    );
  }

  @override
  Future<ReminderPermissionStatus> requestNotificationPermission() async {
    await _legacy.initialize();
    await _legacy.requestNotificationPermission();
    return permissionStatus();
  }

  @override
  Future<ReminderPermissionStatus> requestExactAlarmPermission() async {
    await openSettings('exact');
    return permissionStatus();
  }

  Future<bool> configureAlert(
    RingtoneSelection sound,
    VibrationSelection vibration,
  ) async {
    final reply = await channel
        .invokeMapMethod<String, dynamic>('configureAlert', {
          'resource': sound.resourceName,
          'uri': sound.contentUri,
          'silent': sound.isSilent,
          'vibration': vibration.name,
          'name': sound.name,
        });
    return reply?['soundFallback'] == true;
  }

  Future<void> openSettings(String kind) =>
      channel.invokeMethod<void>('settings', kind);
  @override
  Future<void> openNotificationSettings() => openSettings('notifications');
  @override
  Future<void> sendTest({
    required RingtoneSelection sound,
    required Duration delay,
  }) => channel.invokeMethod<void>('test', {
    'delay': delay.inMilliseconds,
    'resource': sound.resourceName,
    'uri': sound.contentUri,
    'silent': sound.isSilent,
  });
}
