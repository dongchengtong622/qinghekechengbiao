import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/app.dart';
import 'package:qinghe_timetable/features/reminders/data/reminder_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';

void main() {
  testWidgets('seeds and displays courses from the local database', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      QingheApp(database: database, reminderScheduler: _FakeScheduler()),
    );
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('大学英语'), 300);
    expect(find.text('大学英语'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _FakeScheduler implements ReminderScheduler {
  @override
  Future<ReminderPermissionState> permissionState() async =>
      ReminderPermissionState.denied;

  @override
  Future<void> replaceAll(List<CourseReminder> reminders) async {}

  @override
  Future<ReminderPermissionState> requestPermissions() async =>
      ReminderPermissionState.denied;
}
