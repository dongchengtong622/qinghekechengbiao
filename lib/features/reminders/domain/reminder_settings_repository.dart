import 'reminder_models.dart';

abstract interface class ReminderSettingsRepository {
  Stream<bool> watchRemindersEnabled();

  Future<void> setRemindersEnabled(bool enabled);

  Stream<ReminderPreferences> watchReminderPreferences();

  Future<void> setReminderLeadMinutes(int minutes);

  Future<void> setReminderSnoozeMinutes(int minutes);

  Future<void> setReminderSnoozeEnabled(bool enabled);

  Future<void> setReminderVibration(VibrationSelection vibration);

  Future<void> setReminderMaxRings(int count);

  Future<void> setHolidaySilenceEnabled(bool enabled);

  Future<void> setReminderSound(RingtoneSelection sound);
}
