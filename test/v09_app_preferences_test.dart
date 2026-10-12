import 'dart:async';
import 'package:drift/native.dart';
import 'package:qinghe_timetable/features/reminders/data/holiday_calendar_service.dart';
import 'package:qinghe_timetable/features/reminders/domain/china_holiday_calendar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/app.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_diagnostics.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/sample_schedule.dart';

void main() {
  Future<void> flush(
    WidgetTester tester,
    _CapabilityScheduler scheduler,
    int calls,
  ) async {
    for (
      var attempt = 0;
      attempt < 50 && scheduler.replacements.length < calls;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(scheduler.replacements.length, greaterThanOrEqualTo(calls));
  }

  Future<CourseRepository> mount(
    WidgetTester tester,
    _CapabilityScheduler scheduler,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repository = CourseRepository(db);
    await tester.runAsync(() async {
      await repository.seedIfEmpty();
      final old = await repository.watchActiveSemester().first;
      final future = DateTime.now().add(const Duration(days: 14));
      await repository.saveSemester(
        Semester(
          id: old.id,
          name: old.name,
          firstWeekStart: DateTime(
            future.year,
            future.month,
            future.day,
          ).subtract(Duration(days: future.weekday - 1)),
          totalWeeks: old.totalWeeks,
        ),
        makeActive: true,
      );
      // These tests exercise real desired reminders, not first-run demos.
      for (final course in sampleCourses) {
        await repository.saveCourse(course);
      }
      await repository.setRemindersEnabled(true);
      await repository.setHolidaySilenceEnabled(false);
    });
    await tester.pumpWidget(
      QingheApp(database: db, reminderScheduler: scheduler),
    );
    await flush(tester, scheduler, 1);
    return repository;
  }

  testWidgets(
    'notification denial retains desired journal and user choice; restoration registers future plans',
    (tester) async {
      final scheduler = _CapabilityScheduler(
        notifications: false,
        exact: false,
      );
      final repository = await mount(tester, scheduler);
      expect(
        (await tester.runAsync(
          () => repository.watchReminderPreferences().first,
        ))!.enabled,
        isTrue,
      );
      expect(scheduler.replacements.last, isNotEmpty);
      // The native scheduler owns platform cancellation and keeps desired events.
      // This app-level boundary fake models that contract; real cancellation is
      // separately verified through Android/device tests, not claimed here.
      expect(scheduler.desired, isNotEmpty);
      expect(scheduler.registered, isEmpty);
      scheduler.notifications = true;
      final next = scheduler.replacements.length + 1;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester, scheduler, next);
      expect(scheduler.registered, isNotEmpty);
      expect(scheduler.mode, 'inexact');
      expect(
        (await tester.runAsync(
          () => repository.watchReminderPreferences().first,
        ))!.enabled,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'exact permission missing still submits course plans; permission recovery changes scheduling mode',
    (tester) async {
      final scheduler = _CapabilityScheduler(notifications: true, exact: false);
      await mount(tester, scheduler);
      expect(scheduler.desired, isNotEmpty);
      expect(scheduler.registered, isNotEmpty);
      expect(scheduler.mode, 'inexact');
      scheduler.exact = true;
      final next = scheduler.replacements.length + 1;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester, scheduler, next);
      expect(scheduler.mode, 'exact');
      expect(scheduler.registered, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'late holiday lookup cannot resurrect reminders after user turns them off',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = CourseRepository(db);
      final scheduler = _CapabilityScheduler(notifications: true, exact: true);
      final holiday = _DelayedHolidayCalendar();
      await tester.runAsync(() async {
        await repo.seedIfEmpty();
        await repo.setRemindersEnabled(true);
        await repo.setHolidaySilenceEnabled(true);
      });
      await tester.pumpWidget(
        QingheApp(
          database: db,
          reminderScheduler: scheduler,
          holidayCalendarService: holiday,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 50 && !holiday.started; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(holiday.started, isTrue);
      await tester.runAsync(() => repo.setRemindersEnabled(false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flush(tester, scheduler, 1);
      expect(scheduler.replacements.last, isEmpty);
      holiday.release.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(scheduler.replacements.every((items) => items.isEmpty), isTrue);
      expect(
        (await tester.runAsync(
          () => repo.watchReminderPreferences().first,
        ))!.enabled,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _CapabilityScheduler implements ReminderScheduler {
  _CapabilityScheduler({required this.notifications, required this.exact});
  bool notifications, exact;
  final replacements = <List<CourseReminder>>[];
  List<CourseReminder> desired = [];
  Set<int> registered = {999};
  String mode = '';
  @override
  Future<ReminderPermissionStatus> permissionStatus() async =>
      ReminderPermissionStatus(
        notificationsAllowed: notifications,
        exactAlarmsAllowed: exact,
      );
  @override
  Future<ReminderPermissionStatus> requestNotificationPermission() =>
      permissionStatus();
  @override
  Future<ReminderPermissionStatus> requestExactAlarmPermission() =>
      permissionStatus();
  @override
  Future<void> openNotificationSettings() async {}
  @override
  Future<void> sendTest({
    required RingtoneSelection sound,
    required Duration delay,
  }) async {}
  @override
  Future<ReminderSyncReport> replaceAll(List<CourseReminder> items) async {
    replacements.add(items);
    desired = List.of(items);
    registered = notifications ? items.map((e) => e.id).toSet() : {};
    mode = exact ? 'exact' : 'inexact';
    return ReminderSyncReport(
      requested: items.length,
      registeredIds: registered,
      nextAt: registered.isEmpty ? null : items.first.scheduledAt,
      failures: [],
    );
  }
}

class _DelayedHolidayCalendar extends HolidayCalendarService {
  final release = Completer<void>();
  bool started = false;
  @override
  Future<ChinaHolidayCalendar> load(int year) async {
    started = true;
    await release.future;
    return ChinaHolidayCalendar.fromJson('{"code":0,"holiday":{}}', year: year);
  }
}
