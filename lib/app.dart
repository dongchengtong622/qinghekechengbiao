import 'dart:async';

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/timetable/data/app_database.dart';
import 'features/reminders/data/reminder_scheduler.dart';
import 'features/reminders/domain/reminder_planner.dart';
import 'features/reminders/presentation/reminder_settings_page.dart';
import 'features/timetable/data/cdcas_kingo_importer.dart';
import 'features/timetable/data/course_repository.dart';
import 'features/timetable/domain/models.dart';
import 'features/timetable/presentation/course_editor_page.dart';
import 'features/timetable/presentation/timetable_page.dart';
import 'features/timetable/presentation/timetable_import_page.dart';

class QingheApp extends StatefulWidget {
  const QingheApp({
    super.key,
    required this.database,
    this.reminderScheduler,
    this.reminderPlanner = const ReminderPlanner(),
  });

  final AppDatabase database;
  final ReminderScheduler? reminderScheduler;
  final ReminderPlanner reminderPlanner;

  @override
  State<QingheApp> createState() => _QingheAppState();
}

class _QingheAppState extends State<QingheApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  late final CourseRepository repository;
  late final ReminderScheduler reminderScheduler;

  @override
  void initState() {
    super.initState();
    repository = CourseRepository(widget.database);
    reminderScheduler =
        widget.reminderScheduler ??
        AndroidReminderScheduler(
          FlutterLocalNotificationGateway(
            onNotificationTap: (_) {
              navigatorKey.currentState?.popUntil((route) => route.isFirst);
            },
          ),
        );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await repository.seedIfEmpty();
    await _rescheduleReminders();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_rescheduleReminders());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.database.close());
    super.dispose();
  }

  Future<void> _openEditor(
    BuildContext context,
    String semesterId, [
    Course? course,
  ]) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourseEditorPage(
          semesterId: semesterId,
          initialCourse: course,
          onSave: (saved) async {
            await repository.saveCourse(saved);
            await _rescheduleReminders();
          },
        ),
      ),
    );
  }

  Future<void> _rescheduleReminders({bool? enabled}) async {
    final remindersEnabled =
        enabled ?? await repository.watchRemindersEnabled().first;
    if (!remindersEnabled) {
      await reminderScheduler.replaceAll(const []);
      return;
    }
    final semester = await repository.watchActiveSemester().first;
    final courses = await repository
        .watchCoursesForSemester(semester.id)
        .first;
    await reminderScheduler.replaceAll(
      widget.reminderPlanner.plan(
        semester: semester,
        courses: courses,
        now: DateTime.now(),
      ),
    );
  }

  Future<void> _openImport(BuildContext context) async {
    final summary = await Navigator.of(context).push<ImportSummary>(
      MaterialPageRoute(
        builder: (_) => TimetableImportPage(
          importer: const CdcasKingoImporter(),
          onImport: repository.importTimetable,
          onPreview: repository.previewTimetableImport,
        ),
      ),
    );
    if (summary != null) await _rescheduleReminders();
  }

  Future<void> _openReminders(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReminderSettingsPage(
          repository: repository,
          scheduler: reminderScheduler,
          onChanged: (enabled) => _rescheduleReminders(enabled: enabled),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '青禾课表',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => StreamBuilder<Semester>(
          stream: repository.watchActiveSemester(),
          builder: (context, semesterSnapshot) {
            if (!semesterSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return StreamBuilder<List<Course>>(
              stream: repository.watchCoursesForSemester(
                semesterSnapshot.data!.id,
              ),
              builder: (context, courseSnapshot) {
                if (!courseSnapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final semester = semesterSnapshot.data!;
                return StreamBuilder<bool>(
                  stream: repository.watchRemindersEnabled(),
                  initialData: false,
                  builder: (context, reminderSnapshot) => TimetablePage(
                    semester: semester,
                    courses: courseSnapshot.data!,
                    displayWeek: semester.weekFor(DateTime.now()) ?? 1,
                    remindersEnabled: reminderSnapshot.data ?? false,
                    onAdd: () => _openEditor(context, semester.id),
                    onImport: () => unawaited(_openImport(context)),
                    onReminders: () => unawaited(_openReminders(context)),
                    onEdit: (course) =>
                        _openEditor(context, semester.id, course),
                    onDelete: (course) => unawaited(() async {
                      await repository.deleteCourse(course.id);
                      await _rescheduleReminders();
                    }()),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
