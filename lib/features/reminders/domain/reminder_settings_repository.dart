abstract interface class ReminderSettingsRepository {
  Stream<bool> watchRemindersEnabled();

  Future<void> setRemindersEnabled(bool enabled);
}
