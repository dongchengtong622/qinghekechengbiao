import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/time/shanghai_time.dart';
import 'features/settings/presentation/settings_sections.dart';
import 'features/widgets/domain/widget_snapshot.dart';
import 'features/widgets/data/widget_sync_service.dart';
import 'features/widgets/presentation/widget_settings_page.dart';
import 'core/theme/app_theme.dart';
import 'features/timetable/data/app_database.dart';
import 'features/reminders/data/reminder_scheduler.dart';
import 'features/reminders/data/native_alarm_scheduler.dart';
import 'features/reminders/data/holiday_calendar_service.dart';
import 'features/reminders/domain/china_holiday_calendar.dart';
import 'features/reminders/domain/reminder_planner.dart';
import 'features/reminders/domain/reminder_models.dart';
import 'features/reminders/presentation/reminder_settings_page.dart';
import 'features/timetable/data/course_repository.dart';
import 'features/timetable/data/backup/timetable_backup_service.dart';
import 'features/timetable/data/smart_timetable_importer.dart';
import 'features/timetable/data/timetable_import.dart';
import 'features/timetable/presentation/import_preview_page.dart';
import 'features/timetable/presentation/excel_manual_mapping_page.dart';
import 'features/timetable/presentation/workbook_selection_page.dart';
import 'features/timetable/presentation/backup_page.dart';
import 'features/timetable/domain/models.dart';
import 'features/timetable/domain/school_schedule.dart';
import 'features/timetable/presentation/course_editor_page.dart';
import 'features/timetable/presentation/timetable_page.dart';
import 'features/timetable/presentation/timetable_import_page.dart';

class QingheApp extends StatefulWidget {
  const QingheApp({
    super.key,
    required this.database,
    this.reminderScheduler,
    this.reminderPlanner = const ReminderPlanner(),
    this.holidayCalendarService,
  });

  final AppDatabase database;
  final ReminderScheduler? reminderScheduler;
  final ReminderPlanner reminderPlanner;
  final HolidayCalendarService? holidayCalendarService;

  @override
  State<QingheApp> createState() => _QingheAppState();
}

class _QingheAppState extends State<QingheApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  bool _gridView = false;
  final _nextReminderAt = ValueNotifier<DateTime?>(null);
  final _nextReminder = ValueNotifier<CourseReminder?>(null);
  int _reminderRevision = 0;
  Future<void> _reminderCommitQueue = Future.value();
  late final CourseRepository repository;
  late final ReminderScheduler reminderScheduler;
  late final HolidayCalendarService holidayCalendarService;

  @override
  void initState() {
    super.initState();
    repository = CourseRepository(widget.database);
    reminderScheduler = widget.reminderScheduler ?? NativeAlarmScheduler();
    holidayCalendarService =
        widget.holidayCalendarService ?? HolidayCalendarService();
    WidgetsBinding.instance.addObserver(this);
    WidgetSyncService.channel.setMethodCallHandler((call) async {
      if (call.method == 'openLink') {
        await _openWidgetLink(
          Map<Object?, Object?>.from(call.arguments as Map),
        );
      }
    });
    unawaited(_initialize());
  }

  late final Stream<Semester> _activeSemesterStream = repository
      .watchActiveSemester();
  late final Stream<bool> _remindersEnabledStream = repository
      .watchRemindersEnabled();
  late final Stream<SchoolSchedule> _schoolScheduleStream = repository
      .watchSchoolSchedule();
  final _semesterCourseStreams = <String, Stream<List<Course>>>{};
  Stream<List<Course>> _courseStream(String id) => _semesterCourseStreams
      .putIfAbsent(id, () => repository.watchCoursesForSemester(id));

  Future<void> _initialize() async {
    await repository.seedIfEmpty();
    final link = await WidgetSyncService().initialLink();
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_openWidgetLink(link)),
      );
    }
    final grid = await repository.readGridView();
    if (mounted) setState(() => _gridView = grid);
    try {
      await _rescheduleReminders();
    } catch (_) {
      /* Settings page exposes permission and retry state. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_rescheduleReminders().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nextReminderAt.dispose();
    _nextReminder.dispose();
    unawaited(widget.database.close());
    super.dispose();
  }

  Future<void> _openEditor(
    BuildContext context,
    String semesterId, [
    Course? course,
  ]) async {
    final schedule = await repository.watchSchoolSchedule().first;
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CourseEditorPage(
          semesterId: semesterId,
          initialCourse: course,
          schedule: schedule,
          maxScheduleSection: schedule.sectionCountFor(semesterId),
          onSave: (saved) async {
            await repository.saveCourse(saved, synchronizeTimes: false);
            await _rescheduleReminders();
          },
          onSaveSharedTimes: (saved) async {
            await repository.saveCourse(
              saved,
              timeToSynchronize: saved.sessions.first,
            );
            await _rescheduleReminders();
          },
        ),
      ),
    );
  }

  Future<void> _rescheduleReminders({
    bool? enabled,
    bool syncWidgets = true,
  }) async {
    final revision = ++_reminderRevision;
    try {
      if (syncWidgets) await _syncWidgets();
    } on PlatformException catch (error) {
      debugPrint("Widget sync failed: ${error.code}");
    }
    Future<void> commit(List<CourseReminder> reminders) {
      final result = _reminderCommitQueue.then((_) async {
        if (revision != _reminderRevision) return;
        final report = await reminderScheduler.replaceAll(reminders);
        if (revision != _reminderRevision) return;
        if (!report.succeeded) throw StateError('提醒调度未完成');
        _nextReminderAt.value = report.nextAt;
        _nextReminder.value = reminders
            .where(
              (r) =>
                  report.nextAt != null &&
                  (report.nextId != null
                      ? r.id == report.nextId
                      : r.scheduledAt.millisecondsSinceEpoch ==
                            report.nextAt!.millisecondsSinceEpoch),
            )
            .firstOrNull;
      });
      _reminderCommitQueue = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      return result;
    }

    final preferences = await repository.watchReminderPreferences().first;
    if (revision != _reminderRevision || !mounted) return;
    final remindersEnabled = preferences.enabled;
    _nextReminderAt.value = null;
    _nextReminder.value = null;
    if (!remindersEnabled) {
      await commit(const []);
      if (revision == _reminderRevision) _nextReminderAt.value = null;
      return;
    }
    final semester = await repository.watchActiveSemester().first;
    final courses = await repository.watchCoursesForSemester(semester.id).first;
    final schedule = await repository.watchSchoolSchedule().first;
    final calendars = <int, ChinaHolidayCalendar>{};
    if (preferences.holidaySilenceEnabled) {
      final lastDate = semester.firstWeekStart.add(
        Duration(days: semester.totalWeeks * DateTime.daysPerWeek - 1),
      );
      for (
        var year = semester.firstWeekStart.year;
        year <= lastDate.year;
        year++
      ) {
        calendars[year] = await holidayCalendarService.load(year);
      }
    }
    if (revision != _reminderRevision || !mounted) return;
    _nextReminderAt.value = null;
    _nextReminder.value = null;
    try {
      await commit(
        widget.reminderPlanner.plan(
          semester: semester,
          courses: courses,
          schedule: schedule,
          now: ShanghaiTime.now(),
          leadTime: Duration(minutes: preferences.leadMinutes),
          sound: preferences.sound,
          snoozeMinutes: preferences.snoozeMinutes,
          snoozeEnabled: preferences.snoozeEnabled,
          vibration: preferences.vibration,
          maxRings: preferences.maxRings,
          includeStarted: true,
          holidayCalendars: calendars,
          holidaySilenceEnabled: preferences.holidaySilenceEnabled,
        ),
      );
    } catch (_) {
      if (revision == _reminderRevision) _nextReminderAt.value = null;
      rethrow;
    }
  }

  Future<void> _openImport(BuildContext context) async {
    final configured = await repository.hasConfiguredSemester();
    if (!context.mounted) return;
    final summary = await Navigator.of(context).push<ImportSummary>(
      MaterialPageRoute(
        builder: (_) => TimetableImportPage(
          semesterConfigured: configured,
          onConfigureSemester: () async {
            final current = await repository.watchActiveSemester().first;
            if (!context.mounted) return false;
            final term = await askImportSemester(context, current);
            if (term == null) return false;
            await repository.saveSemester(term, makeActive: true);
            await _rescheduleReminders();
            return true;
          },
          loadScheduleSections: () async =>
              (await repository.watchSchoolSchedule().first).sections.length,
          loadSchedule: () => repository.watchSchoolSchedule().first,
          loadUnsharedTimes: repository.readUnsharedTimes,
          loadPreview: () async {
            final active = await repository.watchActiveSemester().first;
            if (!context.mounted) return null;
            final term = active;
            final file = await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: const ['xlsx', 'xls'],
            );
            if (file == null) return null;
            final bytes = await file.readAsBytes();
            try {
              final importer = const SmartTimetableImporter();
              final workbook = importer.parseWorkbook(bytes, term);
              if (workbook.sheets.length > 1) {
                if (!context.mounted) return null;
                return await Navigator.of(context).push<ImportPreview>(
                  MaterialPageRoute(
                    builder: (_) => WorkbookSelectionPage(
                      workbook: workbook,
                      semester: term,
                    ),
                  ),
                );
              }
              return importer.parseExcel(bytes, term);
            } on ExcelMappingRequiredException catch (mapping) {
              if (!context.mounted) return null;
              return Navigator.of(context).push<ImportPreview>(
                MaterialPageRoute(
                  builder: (_) =>
                      ExcelManualMappingPage(mapping: mapping, semester: term),
                ),
              );
            }
          },
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
          onChanged: (enabled) =>
              _rescheduleReminders(enabled: enabled, syncWidgets: false),
          nextReminderAtListenable: _nextReminderAt,
          nextReminderListenable: _nextReminder,
        ),
      ),
    );
  }

  int _widgetRevision = 0;
  Future<void> _syncWidgets() async {
    final revision = ++_widgetRevision;
    final term = await repository.watchActiveSemester().first;
    final courses = await repository.watchCoursesForSemester(term.id).first;
    final schedule = await repository.readSchoolSchedule();
    final configured = await repository.hasConfiguredSemester();
    if (revision != _widgetRevision || !mounted) return;
    await WidgetSyncService().save(
      WidgetSnapshot.generate(
        semester: term,
        courses: courses,
        schedule: schedule,
        now: ShanghaiTime.now(),
        configured: configured,
      ),
    );
  }

  Future<void> _openWidgets(BuildContext context) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => WidgetSettingsPage(onRefresh: _syncWidgets),
    ),
  );
  Future<void> _openWidgetLink(Map<Object?, Object?> link) async {
    final nav = navigatorKey.currentState;
    if (nav == null || !mounted) return;
    if (link['route'] == 'import') {
      await _openImport(nav.context);
      return;
    }
    nav.popUntil((route) => route.isFirst);
    final id = link['courseId'];
    if (id == null) return;
    final term = await repository.watchActiveSemester().first;
    if (link['scheduleId'] != term.id) return;
    final courses = await repository.watchCoursesForSemester(term.id).first;
    final course = courses.where((c) => c.id == id).firstOrNull;
    if (course == null || !mounted) return;
    final index = link['sessionIndex'] is int
        ? link['sessionIndex'] as int
        : int.tryParse('${link['sessionIndex']}') ?? 0;
    if (index < 0 || index >= course.sessions.length) return;
    final s = course.sessions[index];
    await showDialog<void>(
      context: nav.context,
      builder: (c) => AlertDialog(
        title: Text(course.name),
        content: SingleChildScrollView(
          child: Text(
            [
              if (link['date'] != null) '${link['date']}',
              '${s.startSection}–${s.endSection}节 · ${s.timeLabel ?? '时间待确认'}',
              if (course.teacher.isNotEmpty) '教师：${course.teacher}',
              if (s.room.isNotEmpty) '教室：${s.room}',
              '第${s.startWeek}–${s.endWeek}周',
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (settingsContext) => Scaffold(
            appBar: AppBar(title: const Text('设置')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SettingsSections(
                  repository: repository,
                  onChanged: _rescheduleReminders,
                  onReminders: () => Navigator.of(settingsContext).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ReminderSettingsPage(
                        repository: repository,
                        scheduler: reminderScheduler,
                        onChanged: (_) =>
                            _rescheduleReminders(syncWidgets: false),
                        optionsOnly: true,
                      ),
                    ),
                  ),
                  onBackup: () => Navigator.of(settingsContext).push<void>(
                    MaterialPageRoute(
                      builder: (_) => BackupPage(
                        service: TimetableBackupService(widget.database),
                        onRestored: _rescheduleReminders,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '青禾课表',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => StreamBuilder<Semester>(
          stream: _activeSemesterStream,
          builder: (context, semesterSnapshot) {
            if (!semesterSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return StreamBuilder<List<Course>>(
              stream: _courseStream(semesterSnapshot.data!.id),
              builder: (context, courseSnapshot) {
                if (!courseSnapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final semester = semesterSnapshot.data!;
                return StreamBuilder<bool>(
                  stream: _remindersEnabledStream,
                  initialData: false,
                  builder: (context, reminderSnapshot) {
                    final currentWeek = semester.weekFor(ShanghaiTime.now());
                    return StreamBuilder<SchoolSchedule>(
                      stream: _schoolScheduleStream,
                      builder: (context, scheduleSnapshot) => TimetablePage(
                        schedule: scheduleSnapshot.data,
                        scheduleSectionCount:
                            scheduleSnapshot.data?.sectionCountFor(
                              semester.id,
                            ) ??
                            12,
                        semester: semester,
                        initialGridView: _gridView,
                        onViewChanged: (value) {
                          setState(() => _gridView = value);
                          unawaited(repository.setGridView(value));
                        },
                        courses: courseSnapshot.data!,
                        initialDisplayWeek: currentWeek ?? 1,
                        currentWeek: currentWeek,
                        remindersEnabled: reminderSnapshot.data ?? false,
                        onAdd: () => _openEditor(context, semester.id),
                        onImport: () => unawaited(_openImport(context)),
                        onReminders: () => unawaited(_openReminders(context)),
                        onSettings: () => unawaited(_openSettings(context)),
                        onWidgets: () => unawaited(_openWidgets(context)),
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
            );
          },
        ),
      ),
    );
  }
}
