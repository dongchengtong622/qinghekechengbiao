import '../../../core/time/shanghai_time.dart';
import '../../timetable/domain/models.dart';
import 'reminder_models.dart';

const cdcasSectionStarts = <int, TimeOfDayParts>{
  1: TimeOfDayParts(8, 25),
  2: TimeOfDayParts(9, 15),
  3: TimeOfDayParts(10, 15),
  4: TimeOfDayParts(11, 5),
  5: TimeOfDayParts(13, 40),
  6: TimeOfDayParts(14, 30),
  7: TimeOfDayParts(15, 30),
  8: TimeOfDayParts(16, 20),
  9: TimeOfDayParts(17, 10),
  10: TimeOfDayParts(18, 45),
  11: TimeOfDayParts(19, 35),
  12: TimeOfDayParts(20, 25),
};

class ReminderPlanner {
  const ReminderPlanner();

  List<CourseReminder> plan({
    required Semester semester,
    required List<Course> courses,
    required DateTime now,
    Duration leadTime = const Duration(minutes: 30),
    ReminderSound sound = ReminderSound.systemDefault,
  }) {
    final reminders = <CourseReminder>[];
    final shanghaiNow = ShanghaiTime.fromUtc(now.toUtc());
    for (final course in courses) {
      for (final session in course.sessions) {
        final startTime = cdcasSectionStarts[session.startSection];
        if (startTime == null && session.startMinute == null) continue;
        final classStartMinute =
            session.startMinute ?? startTime!.hour * 60 + startTime.minute;
        for (var week = 1; week <= semester.totalWeeks; week++) {
          if (!session.occursInWeek(week)) continue;
          final date = semester.firstWeekStart.add(
            Duration(
              days:
                  (week - 1) * DateTime.daysPerWeek +
                  session.weekday -
                  DateTime.monday,
            ),
          );
          final classStart = ShanghaiTime.dateTime(
            date.year,
            date.month,
            date.day,
            classStartMinute ~/ 60,
            classStartMinute % 60,
          );
          final scheduledAt = classStart.subtract(leadTime);
          if (!scheduledAt.isAfter(shanghaiNow)) continue;
          final details = <String>[
            '第${session.startSection}-${session.endSection}节',
            if (session.room.trim().isNotEmpty) session.room.trim(),
            if (course.teacher.trim().isNotEmpty) course.teacher.trim(),
          ];
          reminders.add(
            CourseReminder(
              id: _notificationId(course.id, session, week),
              scheduledAt: scheduledAt,
              title: '${leadTime.inMinutes}分钟后上课：${course.name}',
              body: details.join(' · '),
              payload: course.id,
              sound: sound,
            ),
          );
        }
      }
    }
    reminders.sort((left, right) {
      final byTime = left.scheduledAt.compareTo(right.scheduledAt);
      return byTime == 0 ? left.id.compareTo(right.id) : byTime;
    });
    return reminders;
  }

  int _notificationId(String courseId, CourseSession session, int week) {
    final value = [
      courseId,
      session.weekday,
      session.startSection,
      session.endSection,
      session.room.trim(),
      session.startWeek,
      session.endWeek,
      session.pattern.name,
      week,
    ].join('|');
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return (hash % maxCourseNotificationId) + 1;
  }
}
