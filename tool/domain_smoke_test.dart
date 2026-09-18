import '../lib/features/timetable/domain/models.dart';

void main() {
  final semester = Semester(
    name: '2026 秋季学期',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 18,
  );
  assert(semester.weekFor(DateTime(2026, 9, 21)) == 3);
  assert(semester.weekFor(DateTime(2026, 9, 6)) == null);

  const oddSession = CourseSession(
    weekday: DateTime.monday,
    startSection: 1,
    endSection: 2,
    startWeek: 1,
    endWeek: 18,
    pattern: WeekPattern.oddWeeks,
    room: 'A302',
  );
  assert(oddSession.occursInWeek(3));
  assert(!oddSession.occursInWeek(4));

  print('Domain smoke tests passed.');
}
