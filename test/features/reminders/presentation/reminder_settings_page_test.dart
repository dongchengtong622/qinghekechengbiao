import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_settings_repository.dart';
import 'package:qinghe_timetable/features/reminders/presentation/reminder_settings_page.dart';

void main() {
  late FakeReminderSettingsRepository repository;
  late FakeReminderScheduler scheduler;

  setUp(() {
    repository = FakeReminderSettingsRepository();
    scheduler = FakeReminderScheduler();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReminderSettingsPage(
          repository: repository,
          scheduler: scheduler,
          onChanged: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('does not request permission before a user enables reminders', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(scheduler.requestCalls, 0);
    expect(find.text('提前 30 分钟'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('persists enabled state after permission is granted', (
    tester,
  ) async {
    scheduler.requestResult = ReminderPermissionState.grantedExact;
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(scheduler.requestCalls, 1);
    expect(await repository.watchRemindersEnabled().first, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('shows delayed warning when only inexact alarms are available', (
    tester,
  ) async {
    scheduler.requestResult = ReminderPermissionState.grantedInexact;
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('提醒可能因系统限制而延迟'), findsOneWidget);
    expect(await repository.watchRemindersEnabled().first, isTrue);
  });

  testWidgets('keeps reminders disabled when notifications are denied', (
    tester,
  ) async {
    scheduler.requestResult = ReminderPermissionState.denied;
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(await repository.watchRemindersEnabled().first, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('通知权限未开启，无法启用课程提醒'), findsOneWidget);
  });
}

class FakeReminderSettingsRepository implements ReminderSettingsRepository {
  bool enabled = false;

  @override
  Future<void> setRemindersEnabled(bool enabled) async {
    this.enabled = enabled;
  }

  @override
  Stream<bool> watchRemindersEnabled() => Stream.value(enabled);
}

class FakeReminderScheduler implements ReminderScheduler {
  ReminderPermissionState state = ReminderPermissionState.denied;
  ReminderPermissionState requestResult = ReminderPermissionState.denied;
  int requestCalls = 0;

  @override
  Future<ReminderPermissionState> permissionState() async => state;

  @override
  Future<void> replaceAll(List<CourseReminder> reminders) async {}

  @override
  Future<ReminderPermissionState> requestPermissions() async {
    requestCalls++;
    state = requestResult;
    return requestResult;
  }
}
