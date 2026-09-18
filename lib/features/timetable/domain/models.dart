enum WeekPattern { everyWeek, oddWeeks, evenWeeks }

enum CourseSource { manual, cdcasKingo }

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
  }) : assert(weekday >= DateTime.monday && weekday <= DateTime.sunday),
       assert(startSection > 0),
       assert(endSection >= startSection),
       assert(startWeek > 0),
       assert(endWeek >= startWeek);

  final int weekday;
  final int startSection;
  final int endSection;
  final int startWeek;
  final int endWeek;
  final WeekPattern pattern;
  final String room;

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
