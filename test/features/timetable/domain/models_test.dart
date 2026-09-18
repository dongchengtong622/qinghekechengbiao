import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  group('WeekPattern', () {
    test('every week accepts all weeks in range', () {
      final session = CourseSession(
        weekday: DateTime.monday,
        startSection: 1,
        endSection: 2,
        startWeek: 1,
        endWeek: 18,
        pattern: WeekPattern.everyWeek,
        room: 'A101',
      );

      expect(session.occursInWeek(1), isTrue);
      expect(session.occursInWeek(10), isTrue);
      expect(session.occursInWeek(18), isTrue);
      expect(session.occursInWeek(19), isFalse);
    });

    test('odd and even patterns select matching teaching weeks', () {
      final odd = CourseSession(
        weekday: DateTime.tuesday,
        startSection: 3,
        endSection: 4,
        startWeek: 1,
        endWeek: 16,
        pattern: WeekPattern.oddWeeks,
        room: 'B202',
      );
      final even = CourseSession(
        weekday: DateTime.tuesday,
        startSection: 3,
        endSection: 4,
        startWeek: 1,
        endWeek: 16,
        pattern: WeekPattern.evenWeeks,
        room: 'B202',
      );

      expect(odd.occursInWeek(3), isTrue);
      expect(odd.occursInWeek(4), isFalse);
      expect(even.occursInWeek(3), isFalse);
      expect(even.occursInWeek(4), isTrue);
    });
  });

  group('Semester', () {
    final semester = Semester(
      name: '2026 秋季学期',
      firstWeekStart: DateTime(2026, 9, 7),
      totalWeeks: 18,
    );

    test('maps dates to teaching weeks', () {
      expect(semester.weekFor(DateTime(2026, 9, 7)), 1);
      expect(semester.weekFor(DateTime(2026, 9, 20)), 2);
      expect(semester.weekFor(DateTime(2026, 9, 21)), 3);
    });

    test('returns null outside the semester', () {
      expect(semester.weekFor(DateTime(2026, 9, 6)), isNull);
      expect(semester.weekFor(DateTime(2027, 1, 11)), isNull);
    });
  });
}
