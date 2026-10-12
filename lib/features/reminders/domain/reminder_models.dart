const maxCourseNotificationId = 0x7ffffffd;
const delayedTestNotificationId = 0x7ffffffe;
const immediateTestNotificationId = 0x7fffffff;

class ReminderPermissionStatus {
  const ReminderPermissionStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    this.fullScreenAllowed = true,
    this.batteryUnrestricted = false,
    this.channelHighImportance = true,
    this.channelAllowed = true,
    this.bannersManuallyConfirmed = false,
    this.sdkInt = 0,
    this.backgroundRestricted = false,
    this.channelUserSilenced = false,
    this.channelSilent = false,
    this.channelUserSoundSet = false,
    this.explicitAudioConsent = false,
    this.diagnostics = '',
  });

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  final bool fullScreenAllowed;
  final bool batteryUnrestricted;
  final bool channelHighImportance;
  final bool channelAllowed;
  final bool bannersManuallyConfirmed;
  final int sdkInt;
  final bool backgroundRestricted;
  final bool channelUserSilenced;
  final bool channelSilent;
  final bool channelUserSoundSet;
  final bool explicitAudioConsent;
  final String diagnostics;
  String get capabilityKey =>
      '$notificationsAllowed|$exactAlarmsAllowed|$channelAllowed|$channelHighImportance|$batteryUnrestricted|$backgroundRestricted|$channelUserSilenced|$channelSilent|$channelUserSoundSet|$explicitAudioConsent';
}

class RingtoneSelection {
  const RingtoneSelection({
    required this.id,
    required this.name,
    this.resourceName,
    this.contentUri,
  });

  final String id;
  final String name;
  final String? resourceName;
  final String? contentUri;

  static const systemDefault = RingtoneSelection(
    id: 'systemDefault',
    name: '系统默认',
  );
  static const none = RingtoneSelection(id: 'none', name: '无铃声');
  bool get isSilent => id == 'none';
  static const chime = RingtoneSelection(
    id: 'chime',
    name: '清脆铃声',
    resourceName: 'qinghe_chime',
  );
  static const soft = RingtoneSelection(
    id: 'soft',
    name: '柔和铃声',
    resourceName: 'qinghe_soft',
  );
  static const alert = RingtoneSelection(
    id: 'alert',
    name: '轻快旋律',
    resourceName: 'qinghe_alert',
  );
  static const morning = RingtoneSelection(
    id: 'morning',
    name: '晨光',
    resourceName: 'qinghe_morning',
  );
  static const xylophone = RingtoneSelection(
    id: 'xylophone',
    name: '木琴',
    resourceName: 'qinghe_xylophone',
  );
  static const water = RingtoneSelection(
    id: 'water',
    name: '水滴',
    resourceName: 'qinghe_water',
  );
  static const bell = RingtoneSelection(
    id: 'bell',
    name: '晚风琴音',
    resourceName: 'qinghe_bell',
  );

  static const presets = [
    systemDefault,
    none,
    chime,
    soft,
    alert,
    morning,
    xylophone,
    water,
    bell,
  ];

  String get storageValue => contentUri == null
      ? id
      : 'local|${Uri.encodeComponent(name)}|${Uri.encodeComponent(contentUri!)}';

  static String _safeDecode(String value) => Uri.decodeComponent(value);
  static bool _validEncoded(String value) {
    try {
      return Uri.decodeComponent(value).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static RingtoneSelection fromStorage(String? value) {
    if (value != null && value.startsWith('local|')) {
      final parts = value.split('|');
      if (parts.length == 3 &&
          _validEncoded(parts[1]) &&
          _validEncoded(parts[2])) {
        return RingtoneSelection(
          id: 'local-${parts[2].hashCode.toUnsigned(32).toRadixString(16)}',
          name: _safeDecode(parts[1]),
          contentUri: _safeDecode(parts[2]),
        );
      }
    }
    return presets.firstWhere(
      (item) => item.id == value,
      orElse: () => systemDefault,
    );
  }
}

class ReminderPreferences {
  const ReminderPreferences({
    required this.enabled,
    required this.leadMinutes,
    required this.sound,
    this.snoozeMinutes = 5,
    this.maxRings = 2,
    this.snoozeEnabled = true,
    this.vibration = VibrationSelection.standard,
    this.holidaySilenceEnabled = true,
  });

  final bool enabled;
  final int leadMinutes;
  final int snoozeMinutes;
  final int maxRings;
  final bool snoozeEnabled;
  final VibrationSelection vibration;
  final bool holidaySilenceEnabled;
  final RingtoneSelection sound;
}

class CourseReminder {
  const CourseReminder({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    required this.payload,
    this.sound = RingtoneSelection.systemDefault,
    this.classStartAt,
    this.classEndAt,
    this.courseName = '',
    this.teacher = '',
    this.room = '',
    this.dateLabel = '',
    this.timeLabel = '',
    this.sectionLabel = '',
    this.weekLabel = '',
    this.occurrenceKey,
    this.snoozeMinutes = 5,
    this.maxRings = 2,
    this.snoozeEnabled = true,
    this.vibration = VibrationSelection.standard,
  });

  final int id;
  final DateTime scheduledAt;
  final DateTime? classStartAt;
  final DateTime? classEndAt;
  final String courseName,
      teacher,
      room,
      dateLabel,
      timeLabel,
      sectionLabel,
      weekLabel;
  final String? occurrenceKey;
  final int snoozeMinutes;
  final int maxRings;
  final bool snoozeEnabled;
  final VibrationSelection vibration;
  final String title;
  final String body;
  final String payload;
  final RingtoneSelection sound;
}

class TimeOfDayParts {
  const TimeOfDayParts(this.hour, this.minute);

  final int hour;
  final int minute;
}

/// Independent device vibration; no audio-derived synchronisation is claimed.
enum VibrationSelection {
  none('无振动', <int>[]),
  standard('标准', <int>[0, 500, 800]),
  gentle('轻柔', <int>[0, 150, 1000]),
  heartbeat('心跳', <int>[0, 120, 120, 250, 900]),
  urgent('急促', <int>[0, 200, 100, 200, 100, 200, 600]);

  const VibrationSelection(this.label, this.pattern);
  final String label;
  final List<int> pattern;
  static VibrationSelection fromStorage(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => standard);
}
