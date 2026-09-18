import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  late AppDatabase database;
  late CourseRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CourseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Course course({String name = '高等数学', String room = 'A302'}) {
    return Course(
      id: 'math',
      name: name,
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
          room: room,
        ),
      ],
    );
  }

  test('saves and watches a course with its session', () async {
    await repository.saveCourse(course());

    final courses = await repository.watchCourses().first;

    expect(courses, hasLength(1));
    expect(courses.single.name, '高等数学');
    expect(courses.single.sessions.single.room, 'A302');
  });

  test('updates a course and replaces its sessions', () async {
    await repository.saveCourse(course());
    await repository.saveCourse(course(name: '高等数学 A', room: 'B201'));

    final courses = await repository.watchCourses().first;

    expect(courses, hasLength(1));
    expect(courses.single.name, '高等数学 A');
    expect(courses.single.sessions, hasLength(1));
    expect(courses.single.sessions.single.room, 'B201');
  });

  test('deletes a course and its sessions', () async {
    await repository.saveCourse(course());

    await repository.deleteCourse('math');

    expect(await repository.watchCourses().first, isEmpty);
  });

  test('seeds sample courses only once', () async {
    await repository.seedIfEmpty();
    final seeded = await repository.watchCourses().first;
    expect(seeded, hasLength(3));

    for (final item in seeded) {
      await repository.deleteCourse(item.id);
    }
    await repository.seedIfEmpty();

    expect(await repository.watchCourses().first, isEmpty);
  });
}
