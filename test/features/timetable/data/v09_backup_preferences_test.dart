import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/data/backup/timetable_backup_service.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';

void main() {
  late AppDatabase db;
  late CourseRepository repository;
  late TimetableBackupService service;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = CourseRepository(db);
    service = TimetableBackupService(db);
    await repository.saveSemester(
      Semester(
        id: 'v09',
        name: '秋季',
        firstWeekStart: DateTime(2026, 9, 7),
        totalWeeks: 16,
      ),
      makeActive: true,
    );
  });
  tearDown(() => db.close());
  test(
    'silent ringtone and disabled snooze and vibration survive JSON backup restore',
    () async {
      await repository.setReminderSound(RingtoneSelection.none);
      await repository.setReminderSnoozeEnabled(false);
      await repository.setReminderVibration(VibrationSelection.heartbeat);
      final backup = service.previewRestore(await service.exportJson()).backup;
      await repository.setReminderSnoozeEnabled(true);
      await repository.setReminderVibration(VibrationSelection.none);
      await repository.setReminderSound(RingtoneSelection.systemDefault);
      await service.restore(backup);
      final prefs = await repository.watchReminderPreferences().first;
      expect(prefs.sound.isSilent, isTrue);
      expect(prefs.snoozeEnabled, isFalse);
      expect(prefs.vibration, VibrationSelection.heartbeat);
    },
  );
  test(
    'old backup without new preference fields restores compatible defaults',
    () async {
      final data =
          jsonDecode(await service.exportJson()) as Map<String, dynamic>;
      (data['reminderPreferences'] as Map).remove('reminder_snooze_enabled');
      (data['reminderPreferences'] as Map).remove('reminder_vibration');
      await repository.setReminderSnoozeEnabled(false);
      await repository.setReminderVibration(VibrationSelection.urgent);
      await service.restore(service.previewRestore(jsonEncode(data)).backup);
      final prefs = await repository.watchReminderPreferences().first;
      expect(prefs.snoozeEnabled, isTrue);
      expect(prefs.vibration, VibrationSelection.standard);
    },
  );
  test(
    'invalid new preference values reject the backup before any restore',
    () async {
      for (final bad in [
        {'reminder_snooze_enabled': 'yes'},
        {'reminder_vibration': 'not-a-pattern'},
      ]) {
        final data =
            jsonDecode(await service.exportJson()) as Map<String, dynamic>;
        (data['reminderPreferences'] as Map).addAll(bad);
        expect(
          () => service.previewRestore(jsonEncode(data)),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
