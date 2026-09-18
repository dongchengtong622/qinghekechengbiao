import '../domain/models.dart';

final sampleSemester = Semester(
  id: 'sample-2026-autumn',
  name: '2026 秋季学期',
  firstWeekStart: DateTime(2026, 9, 7),
  totalWeeks: 18,
);

const sampleCourses = <Course>[
  Course(
    id: 'math',
    semesterId: 'sample-2026-autumn',
    source: CourseSource.manual,
    name: '高等数学',
    teacher: '陈老师',
    colorValue: 0xFF2E7D66,
    sessions: [
      CourseSession(
        weekday: DateTime.monday,
        startSection: 1,
        endSection: 2,
        startWeek: 1,
        endWeek: 18,
        pattern: WeekPattern.everyWeek,
        room: 'A302',
      ),
    ],
  ),
  Course(
    id: 'design',
    semesterId: 'sample-2026-autumn',
    source: CourseSource.manual,
    name: '设计基础',
    teacher: '李老师',
    colorValue: 0xFF6366A8,
    sessions: [
      CourseSession(
        weekday: DateTime.wednesday,
        startSection: 3,
        endSection: 4,
        startWeek: 1,
        endWeek: 16,
        pattern: WeekPattern.oddWeeks,
        room: '艺术楼 205',
      ),
    ],
  ),
  Course(
    id: 'english',
    semesterId: 'sample-2026-autumn',
    source: CourseSource.manual,
    name: '大学英语',
    teacher: '王老师',
    colorValue: 0xFFD77855,
    sessions: [
      CourseSession(
        weekday: DateTime.friday,
        startSection: 5,
        endSection: 6,
        startWeek: 2,
        endWeek: 18,
        pattern: WeekPattern.everyWeek,
        room: 'B401',
      ),
    ],
  ),
];
