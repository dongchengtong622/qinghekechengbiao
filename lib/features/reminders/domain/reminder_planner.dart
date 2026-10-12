import '../../../core/time/shanghai_time.dart';
import '../../timetable/domain/models.dart';
import '../../timetable/domain/school_schedule.dart';
import 'china_holiday_calendar.dart';
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
    RingtoneSelection sound = RingtoneSelection.systemDefault,
    int snoozeMinutes = 5,
    int maxRings = 2,
    bool snoozeEnabled = true,
    VibrationSelection vibration = VibrationSelection.standard,
    bool includeStarted = false,
    SchoolSchedule? schedule,
    Map<int, ChinaHolidayCalendar> holidayCalendars = const {},
    bool holidaySilenceEnabled = true,
  }) {
    final reminders = <CourseReminder>[];
    if (leadTime <= Duration.zero) return reminders;
    final shanghaiNow = ShanghaiTime.fromUtc(now.toUtc());
    for (final course in courses) {
      for (final session in course.sessions) {
        final resolved = schedule != null
            ? schedule.resolve(session, semesterId: course.semesterId)
            : session;
        final classStartMinute =
            resolved.startMinute ??
            (schedule ?? SchoolSchedule.defaults())
                .sectionFor(course.semesterId, session.startSection)
                ?.startMinute;
        if (classStartMinute == null) continue;
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
          if (holidaySilenceEnabled &&
              (holidayCalendars[date.year]?.shouldSilence(date) ?? false)) {
            continue;
          }
          final classStart = ShanghaiTime.dateTime(
            date.year,
            date.month,
            date.day,
            classStartMinute ~/ 60,
            classStartMinute % 60,
          );
          final endMinute =
              resolved.endMinute ??
              (schedule ?? SchoolSchedule.defaults())
                  .sectionFor(course.semesterId, session.endSection)
                  ?.endMinute;
          final classEnd = endMinute == null
              ? null
              : ShanghaiTime.dateTime(
                  date.year,
                  date.month,
                  date.day,
                  endMinute ~/ 60,
                  endMinute % 60,
                );
          String clock(int minute) =>
              '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
          final timeLabel =
              '${clock(classStartMinute)}–${endMinute == null ? '结束时间待补全' : clock(endMinute)}';
          const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
          final dateLabel =
              '${date.year}年${date.month}月${date.day}日 星期${weekdays[session.weekday - 1]}';
          final scheduledAt = classStart.subtract(leadTime);
          if (!classStart.isAfter(shanghaiNow)) continue;
          if (!includeStarted && !scheduledAt.isAfter(shanghaiNow)) continue;
          final details = <String>[
            '第${session.startSection}-${session.endSection}节',
            if (session.room.trim().isNotEmpty) session.room.trim(),
            if (course.teacher.trim().isNotEmpty) course.teacher.trim(),
          ];
          reminders.add(
            CourseReminder(
              id: _notificationId(course.id, session, week),
              scheduledAt: scheduledAt,
              classStartAt: classStart,
              classEndAt: classEnd,
              courseName: course.name,
              teacher: course.teacher.trim(),
              room: session.room.trim(),
              dateLabel: dateLabel,
              timeLabel: timeLabel,
              sectionLabel: '第${session.startSection}-${session.endSection}节',
              weekLabel: '第$week周',
              snoozeEnabled: snoozeEnabled,
              vibration: vibration,
              occurrenceKey:
                  '${semester.id}|${course.id}|${session.weekday}|${session.startSection}-${session.endSection}|${date.year}-${date.month}-${date.day}',
              snoozeMinutes: snoozeMinutes,
              maxRings: snoozeEnabled ? maxRings : 1,
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
