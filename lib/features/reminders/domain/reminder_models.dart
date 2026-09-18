class CourseReminder {
  const CourseReminder({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final DateTime scheduledAt;
  final String title;
  final String body;
  final String payload;
}

class TimeOfDayParts {
  const TimeOfDayParts(this.hour, this.minute);

  final int hour;
  final int minute;
}
