import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/timetable/data/app_database.dart';
import 'features/timetable/data/course_repository.dart';
import 'features/timetable/data/sample_schedule.dart';
import 'features/timetable/domain/models.dart';
import 'features/timetable/presentation/course_editor_page.dart';
import 'features/timetable/presentation/timetable_page.dart';

class QingheApp extends StatefulWidget {
  const QingheApp({super.key, required this.database});

  final AppDatabase database;

  @override
  State<QingheApp> createState() => _QingheAppState();
}

class _QingheAppState extends State<QingheApp> {
  late final CourseRepository repository;

  @override
  void initState() {
    super.initState();
    repository = CourseRepository(widget.database);
    unawaited(repository.seedIfEmpty());
  }

  @override
  void dispose() {
    unawaited(widget.database.close());
    super.dispose();
  }

  Future<void> _openEditor(BuildContext context, [Course? course]) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourseEditorPage(
          initialCourse: course,
          onSave: repository.saveCourse,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青禾课表',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => StreamBuilder<List<Course>>(
          stream: repository.watchCourses(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return TimetablePage(
              semester: sampleSemester,
              courses: snapshot.data!,
              displayWeek: sampleSemester.weekFor(DateTime.now()) ?? 1,
              onAdd: () => _openEditor(context),
              onEdit: (course) => _openEditor(context, course),
              onDelete: (course) =>
                  unawaited(repository.deleteCourse(course.id)),
            );
          },
        ),
      ),
    );
  }
}
