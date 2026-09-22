const maxCourseNotificationId = 0x7ffffffd;
const delayedTestNotificationId = 0x7ffffffe;
const immediateTestNotificationId = 0x7fffffff;

class ReminderPermissionStatus {
  const ReminderPermissionStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
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
    name: '提示音',
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
    name: '短钟声',
    resourceName: 'qinghe_bell',
  );

  static const presets = [
    systemDefault,
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

  static RingtoneSelection fromStorage(String? value) {
    if (value != null && value.startsWith('local|')) {
      final parts = value.split('|');
      if (parts.length == 3) {
        return RingtoneSelection(
          id: 'local-' + parts[2].hashCode.toUnsigned(32).toRadixString(16),
          name: Uri.decodeComponent(parts[1]),
          contentUri: Uri.decodeComponent(parts[2]),
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
  });

  final bool enabled;
  final int leadMinutes;
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
  });

  final int id;
  final DateTime scheduledAt;
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
