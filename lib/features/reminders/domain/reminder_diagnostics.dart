enum ReminderStage {
  settings,
  permissions,
  planning,
  registration,
  verification,
}

class ReminderFailure {
  const ReminderFailure({
    required this.stage,
    required this.code,
    required this.message,
  });

  final ReminderStage stage;
  final String code;
  final String message;
}

class ReminderSyncReport {
  ReminderSyncReport({
    required this.requested,
    required Set<int> registeredIds,
    required this.nextAt,
    required List<ReminderFailure> failures,
  }) : registeredIds = Set.unmodifiable(registeredIds),
       failures = List.unmodifiable(failures);

  final int requested;
  final Set<int> registeredIds;
  final DateTime? nextAt;
  final List<ReminderFailure> failures;

  bool get succeeded => failures.isEmpty;
}
