enum ReminderPermissionState { grantedExact, grantedInexact, denied }

enum ReminderSound { systemDefault, chime, soft, alert }

class ReminderPreferences {
  const ReminderPreferences({
    required this.enabled,
    required this.leadMinutes,
    required this.sound,
  });

  final bool enabled;
  final int leadMinutes;
  final ReminderSound sound;
}

class CourseReminder {
  const CourseReminder({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    required this.payload,
    this.sound = ReminderSound.systemDefault,
  });

  final int id;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final String payload;
  final ReminderSound sound;
}

class TimeOfDayParts {
  const TimeOfDayParts(this.hour, this.minute);

  final int hour;
  final int minute;
}
