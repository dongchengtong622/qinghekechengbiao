import 'reminder_models.dart';

abstract interface class ReminderSettingsRepository {
  Stream<bool> watchRemindersEnabled();

  Future<void> setRemindersEnabled(bool enabled);

  Stream<ReminderPreferences> watchReminderPreferences();

  Future<void> setReminderLeadMinutes(int minutes);

  Future<void> setReminderSound(RingtoneSelection sound);
}
