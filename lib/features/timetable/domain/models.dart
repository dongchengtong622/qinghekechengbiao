enum WeekPattern { everyWeek, oddWeeks, evenWeeks }

enum CourseSource { manual, cdcasKingo }

enum CourseTimeSource { schedule, custom, imported }

class Semester {
  const Semester({
    required this.id,
    required this.name,
    required this.firstWeekStart,
    required this.totalWeeks,
  }) : assert(totalWeeks > 0);

  final String id;
  final String name;
  final DateTime firstWeekStart;
  final int totalWeeks;

  int? weekFor(DateTime date) {
    final normalizedStart = DateTime(
      firstWeekStart.year,
      firstWeekStart.month,
      firstWeekStart.day,
    );
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final dayOffset = normalizedDate.difference(normalizedStart).inDays;
    if (dayOffset < 0) return null;

    final week = dayOffset ~/ DateTime.daysPerWeek + 1;
    return week <= totalWeeks ? week : null;
  }
}

class Course {
  const Course({
    required this.id,
    required this.semesterId,
    required this.source,
    required this.name,
    required this.teacher,
    required this.colorValue,
    required this.sessions,
    this.externalId,
  });

  final String id;
  final String semesterId;
  final CourseSource source;
  final String? externalId;
  final String name;
  final String teacher;
  final int colorValue;
  final List<CourseSession> sessions;
}

class CourseSession {
  const CourseSession({
    required this.weekday,
    required this.startSection,
    required this.endSection,
    required this.startWeek,
    required this.endWeek,
    required this.pattern,
    required this.room,
    this.startMinute,
    this.endMinute,
    CourseTimeSource? timeSource,
  }) : _timeSource = timeSource,
       assert(weekday >= DateTime.monday && weekday <= DateTime.sunday),
       assert(startSection > 0),
       assert(endSection >= startSection),
       assert(startWeek > 0),
       assert(endWeek >= startWeek),
       assert(startMinute == null || startMinute >= 0),
       assert(startMinute == null || startMinute < 24 * 60),
       assert(endMinute == null || endMinute >= 0),
       assert(endMinute == null || endMinute < 24 * 60),
       assert(
         startMinute == null || endMinute == null || endMinute > startMinute,
       );

  final int weekday;
  final int startSection;
  final int endSection;
  final int startWeek;
  final int endWeek;
  final WeekPattern pattern;
  final String room;
  final int? startMinute;
  final int? endMinute;
  final CourseTimeSource? _timeSource;
  CourseTimeSource get timeSource =>
      _timeSource ??
      (startMinute == null
          ? CourseTimeSource.schedule
          : CourseTimeSource.custom);

  String? get timeLabel {
    if (startMinute == null || endMinute == null) return null;
    return '${_formatMinute(startMinute!)}–${_formatMinute(endMinute!)}';
  }

  static String _formatMinute(int minute) {
    final hour = minute ~/ 60;
    final remainder = minute % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }

  bool occursInWeek(int week) {
    if (week < startWeek || week > endWeek) return false;
    return switch (pattern) {
      WeekPattern.everyWeek => true,
      WeekPattern.oddWeeks => week.isOdd,
      WeekPattern.evenWeeks => week.isEven,
    };
  }
}

class ScheduledCourse {
  const ScheduledCourse({required this.course, required this.session});

  final Course course;
  final CourseSession session;
}
