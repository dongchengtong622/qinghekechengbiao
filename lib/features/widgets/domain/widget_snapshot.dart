import 'dart:convert';
import '../../../core/time/shanghai_time.dart';
import '../../timetable/domain/models.dart';
import '../../timetable/domain/school_schedule.dart';

class WidgetSnapshot {
  const WidgetSnapshot(this.data);
  final Map<String, Object?> data;
  String encode() => jsonEncode(data);
  factory WidgetSnapshot.generate({
    required Semester semester,
    required List<Course> courses,
    required SchoolSchedule schedule,
    required DateTime now,
    bool configured = true,
  }) {
    final local = ShanghaiTime.fromUtc(now.toUtc());
    final start = ShanghaiTime.dateTime(
      local.year,
      local.month,
      local.day,
      0,
      0,
    );
    final end = start.add(const Duration(days: 14));
    final instances = <Map<String, Object?>>[];
    if (configured) {
      for (var day = 0; day < 14; day++) {
        final date = start.add(Duration(days: day));
        final week = semester.weekFor(date);
        if (week == null) continue;
        for (final course in courses.where(
          (c) => c.semesterId == semester.id,
        )) {
          for (var index = 0; index < course.sessions.length; index++) {
            final session = course.sessions[index];
            if (session.weekday != date.weekday ||
                !session.occursInWeek(week)) {
              continue;
            }
            CourseSession? resolved;
            try {
              resolved = schedule.resolve(session, semesterId: semester.id);
            } on FormatException {
              resolved = null;
            }
            final a = resolved?.startMinute, b = resolved?.endMinute;
            int? instant(int? m) => m == null
                ? null
                : ShanghaiTime.dateTime(
                    date.year,
                    date.month,
                    date.day,
                    m ~/ 60,
                    m % 60,
                  ).millisecondsSinceEpoch;
            instances.add({
              'courseId': course.id,
              'scheduleId': semester.id,
              'sessionIndex': index,
              'courseName': course.name,
              'teacher': course.teacher,
              'room': session.room,
              'date':
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              'week': week,
              'weekday': date.weekday,
              'startSection': session.startSection,
              'endSection': session.endSection,
              'startAt': instant(a),
              'endAt': instant(b),
              'timeLabel': resolved?.timeLabel,
              'sectionLabel': '第${session.startSection}–${session.endSection}节',
              'weekLabel':
                  '第${session.startWeek}–${session.endWeek}周${switch (session.pattern) {
                    WeekPattern.oddWeeks => ' · 单周',
                    WeekPattern.evenWeeks => ' · 双周',
                    WeekPattern.everyWeek => '',
                  }}',
            });
          }
        }
      }
    }
    instances.sort((a, b) {
      final d = (a['date'] as String).compareTo(b['date'] as String);
      return d != 0
          ? d
          : (a['startSection'] as int).compareTo(b['startSection'] as int);
    });
    return WidgetSnapshot({
      'schemaVersion': 1,
      'dataVersion': now.microsecondsSinceEpoch,
      'generatedAt': now.millisecondsSinceEpoch,
      'coverageStart': start.millisecondsSinceEpoch,
      'coverageEnd': end.millisecondsSinceEpoch,
      'timeZone': 'Asia/Shanghai',
      'scheduleId': semester.id,
      'scheduleName': semester.name,
      'configured': configured,
      'firstWeekStart':
          '${semester.firstWeekStart.year}-${semester.firstWeekStart.month.toString().padLeft(2, '0')}-${semester.firstWeekStart.day.toString().padLeft(2, '0')}',
      'totalWeeks': semester.totalWeeks,
      'instances': instances,
    });
  }
}
