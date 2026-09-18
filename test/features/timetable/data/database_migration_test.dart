import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  test('migrates v1 courses as manual courses without data loss', () async {
    final executor = NativeDatabase.memory(
      setup: (database) {
        database.execute('''
          CREATE TABLE course_rows (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            teacher TEXT NOT NULL DEFAULT '',
            color_value INTEGER NOT NULL
          )
        ''');
        database.execute('''
          CREATE TABLE course_session_rows (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            course_id TEXT NOT NULL REFERENCES course_rows(id) ON DELETE CASCADE,
            weekday INTEGER NOT NULL,
            start_section INTEGER NOT NULL,
            end_section INTEGER NOT NULL,
            start_week INTEGER NOT NULL,
            end_week INTEGER NOT NULL,
            pattern TEXT NOT NULL,
            room TEXT NOT NULL
          )
        ''');
        database.execute('''
          CREATE TABLE app_metadata (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        database.execute(
          "INSERT INTO course_rows VALUES "
          "('legacy-math', '高等数学', '陈老师', 4281232742)",
        );
        database.execute(
          "INSERT INTO course_session_rows "
          "(course_id, weekday, start_section, end_section, start_week, end_week, pattern, room) "
          "VALUES ('legacy-math', 1, 1, 2, 1, 18, 'everyWeek', 'A302')",
        );
        database.userVersion = 1;
      },
    );
    final database = AppDatabase(executor);
    final repository = CourseRepository(database);
    addTearDown(database.close);

    final course = (await repository.watchCourses().first).single;
    final semester = await repository.watchActiveSemester().first;

    expect(course.id, 'legacy-math');
    expect(course.source, CourseSource.manual);
    expect(course.externalId, isNull);
    expect(course.semesterId, 'sample-2026-autumn');
    expect(course.sessions.single.room, 'A302');
    expect(semester.id, 'sample-2026-autumn');
  });
}
