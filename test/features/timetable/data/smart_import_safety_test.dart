import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  test(
    'adding another recognized file preserves existing imported courses',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CourseRepository(db);
      final term = Semester(
        id: 'term',
        name: '学期',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 18,
      );
      Course course(String id) => Course(
        id: id,
        semesterId: term.id,
        source: CourseSource.cdcasKingo,
        externalId: id,
        name: id,
        teacher: '',
        colorValue: 0xFF2E7D66,
        sessions: const [
          CourseSession(
            weekday: 1,
            startSection: 1,
            endSection: 2,
            startWeek: 1,
            endWeek: 18,
            pattern: WeekPattern.everyWeek,
            room: 'A302',
          ),
        ],
      );
      await repo.importTimetable(
        ImportPreview(semester: term, courses: [course('first')]),
      );
      final draft = ImportPreview(
        semester: term,
        courses: [course('second')],
        replaceExisting: false,
      );
      expect((await repo.previewTimetableImport(draft)).removed, 0);
      expect((await repo.watchCoursesForSemester(term.id).first).length, 1);
      await repo.importTimetable(draft);
      expect((await repo.watchCoursesForSemester(term.id).first).length, 2);
      await repo.importTimetable(draft);
      expect((await repo.watchCoursesForSemester(term.id).first).length, 2);
    },
  );
}
