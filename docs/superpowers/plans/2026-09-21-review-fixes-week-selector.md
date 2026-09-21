# Qinghe Timetable Reliability And Week Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add selectable timetable weeks, harden Excel import and Android reminders, and produce version 0.4.0+4 release artifacts.

**Architecture:** Continue on the existing `codex/course-import-reminders` draft PR branch. Add one shared Shanghai-time boundary, keep week selection inside the timetable presentation state, extend the importer through canonical column resolution and row-level warnings, and expose Android permission details through the existing scheduler abstraction.

**Tech Stack:** Flutter, Dart, Drift, excel, flutter_local_notifications, timezone, GitHub Actions

**Spec:** `docs/superpowers/specs/2026-09-21-review-fixes-week-selector-design.md`

## Global Constraints

- Application version is exactly `0.4.0+4`.
- User-selectable weeks span `1..semester.totalWeeks`.
- Shanghai time is authoritative for current week and reminder scheduling.
- Invalid Excel course rows produce warnings; workbook-level structural failures remain errors.
- Notification permission denial disables reminders; exact-alarm denial uses inexact scheduling.
- Build outputs include a universal release APK, arm64 release APK, and release AAB.
- Do not merge `main` or publish to an app store.

## Review Focus

- Date near Shanghai midnight while the device uses another time zone must select the Shanghai calendar day and week.
- A workbook whose first Sheet is instructions and second Sheet is the timetable must import the second Sheet.
- A malformed course row between valid rows must become one warning without discarding valid courses.
- Two sessions sharing course, weekday, start section, and week but differing in room or end section must receive different IDs.
- Returning from Android settings after changing permissions must refresh status and reschedule using the effective mode.

---

### Task 1: Shanghai Time Boundary

**Files:**
- Create: `lib/core/time/shanghai_time.dart`
- Modify: `lib/app.dart`
- Test: `test/core/time/shanghai_time_test.dart`

**Interfaces:**
- Produces: `ShanghaiTime.now()`, `ShanghaiTime.dateTime(...)`, and `ShanghaiTime.location`.
- Consumers: timetable current-week calculation, reminder planning, notification scheduling.

- [ ] **Step 1: Write failing Shanghai-time tests**

Create tests that initialize a UTC instant near midnight, convert it through a testable `ShanghaiTime.fromUtc(DateTime)`, and assert the Shanghai date and `timezone.Location.name == 'Asia/Shanghai'`.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/core/time/shanghai_time_test.dart --reporter expanded`  
Expected: FAIL because `ShanghaiTime` does not exist.

- [ ] **Step 3: Implement the shared time boundary**

Implement a static, idempotently initialized helper using `timezone/data/latest_10y.dart` and `timezone/timezone.dart`:

```dart
abstract final class ShanghaiTime {
  static late final timezone.Location location;
  static bool _initialized = false;

  static void ensureInitialized() { /* initialize once and load Asia/Shanghai */ }
  static timezone.TZDateTime now() { /* TZDateTime.now(location) */ }
  static timezone.TZDateTime fromUtc(DateTime value) { /* TZDateTime.from(value.toUtc(), location) */ }
  static timezone.TZDateTime dateTime(int year, int month, int day, int hour, int minute) {
    /* construct in location */
  }
}
```

Update `QingheApp._rescheduleReminders` to pass `ShanghaiTime.now()`.

- [ ] **Step 4: Run focused tests and existing app tests**

Run: `flutter test test/core/time/shanghai_time_test.dart test/app_test.dart --reporter expanded`  
Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: centralize Shanghai time handling`

### Task 2: Selectable Timetable Weeks

**Files:**
- Modify: `lib/features/timetable/presentation/timetable_page.dart`
- Modify: `lib/app.dart`
- Test: `test/features/timetable/presentation/timetable_page_test.dart`

**Interfaces:**
- Consumes: `ShanghaiTime.now()`, `Semester.weekFor(DateTime)`.
- Produces: stateful week selection UI with keys `week_selector` and `return_to_current_week`.

- [ ] **Step 1: Add failing widget tests**

Add tests that assert:

```dart
expect(find.text('第 3 周 · 本周'), findsOneWidget);
await tester.tap(find.byKey(const Key('week_selector')));
await tester.pumpAndSettle();
expect(find.text('第 1 周'), findsWidgets);
expect(find.text('第 18 周'), findsOneWidget);
await tester.tap(find.text('第 5 周').last);
await tester.pumpAndSettle();
expect(find.byKey(const Key('return_to_current_week')), findsOneWidget);
```

Also test tapping the return control restores week 3 and that changing semester ID resets/clamps selection.

- [ ] **Step 2: Run the widget test and verify RED**

Run: `flutter test test/features/timetable/presentation/timetable_page_test.dart --reporter expanded`  
Expected: FAIL because the selector and return control are absent.

- [ ] **Step 3: Implement stateful week selection**

Convert `TimetablePage` to a `StatefulWidget`. Keep `_displayWeek` in state, accept `currentWeek`, generate menu entries for `List.generate(semester.totalWeeks, ...)`, label the current week as `本周`, and expose a compact return button only while another week is displayed. Use the selected state in course filtering. Reset when `semester.id` changes.

- [ ] **Step 4: Pass Shanghai current week from the app**

Compute:

```dart
final currentWeek = semester.weekFor(ShanghaiTime.now());
```

Pass `currentWeek` and `initialDisplayWeek: currentWeek ?? 1` to `TimetablePage`.

- [ ] **Step 5: Run widget and app tests**

Run: `flutter test test/features/timetable/presentation/timetable_page_test.dart test/app_test.dart --reporter expanded`  
Expected: PASS.

- [ ] **Step 6: Commit**

Commit message: `feat: add selectable timetable weeks`

### Task 3: Time-Zone-Safe Reminder Planning And Stable IDs

**Files:**
- Modify: `lib/features/reminders/domain/reminder_planner.dart`
- Modify: `lib/features/reminders/data/reminder_scheduler.dart`
- Test: `test/features/reminders/domain/reminder_planner_test.dart`
- Test: `test/features/reminders/data/reminder_scheduler_test.dart`

**Interfaces:**
- Consumes: `ShanghaiTime.dateTime` and TZ-aware `DateTime now`.
- Produces: `CourseReminder.scheduledAt` as `timezone.TZDateTime`; stable full-session notification IDs.

- [ ] **Step 1: Add failing planner tests**

Add a test where `now` represents a Japan-local instant but is converted to Shanghai time, and assert the reminder remains `2026-09-07 07:55 Asia/Shanghai`. Add two same-start sessions differing by `endSection` and `room`, and assert distinct IDs.

- [ ] **Step 2: Run planner tests and verify RED**

Run: `flutter test test/features/reminders/domain/reminder_planner_test.dart --reporter expanded`  
Expected: FAIL on TZ type/location and duplicate IDs.

- [ ] **Step 3: Implement TZ planning and complete session key**

Build class start with `ShanghaiTime.dateTime`. Hash:

```dart
final value = [
  courseId,
  session.weekday,
  session.startSection,
  session.endSection,
  session.room.trim(),
  session.startWeek,
  session.endWeek,
  session.pattern.name,
  week,
].join('|');
```

- [ ] **Step 4: Stop rebuilding scheduled time from device-local fields**

In `FlutterLocalNotificationGateway.schedule`, assert/convert `reminder.scheduledAt` to the Shanghai location through `ShanghaiTime.fromUtc` and pass that value directly to `zonedSchedule`.

- [ ] **Step 5: Run reminder tests**

Run: `flutter test test/features/reminders/domain/reminder_planner_test.dart test/features/reminders/data/reminder_scheduler_test.dart --reporter expanded`  
Expected: PASS.

- [ ] **Step 6: Commit**

Commit message: `fix: make reminders timezone safe and uniquely identified`

### Task 4: Robust Multi-Sheet Excel Import

**Files:**
- Modify: `lib/features/timetable/data/excel_timetable_importer.dart`
- Modify: `lib/features/timetable/data/timetable_import.dart`
- Create: `test/fixtures/qinghe_timetable_import_template.xlsx`
- Test: `test/features/timetable/data/excel_timetable_importer_test.dart`

**Interfaces:**
- Produces: canonical header lookup, multi-Sheet selection, compound week/section parsing, and row warnings in `ImportPreview.warnings`.

- [ ] **Step 1: Add failing row-parser tests**

Cover aliases and values:

```dart
['课程', '上课星期', '上课节次', '上课周次', '上课地点']
['景观设计', '星期一', '第1-2节', '1-18周', 'A302']
['景观设计', '星期三', '第3-4节', '1,3,5周', 'B201']
```

Assert valid sessions and a warning for a malformed row between them.

- [ ] **Step 2: Run importer tests and verify RED**

Run: `flutter test test/features/timetable/data/excel_timetable_importer_test.dart --reporter expanded`  
Expected: FAIL because aliases and compound values are unsupported.

- [ ] **Step 3: Implement canonical columns and row-level warnings**

Add a constant alias map and helpers that resolve normalized headers. Parse explicit start/end columns first, then compound section/week columns. Represent comma-separated discrete weeks as separate compatible sessions so `CourseSession.occursInWeek` stays unchanged. Catch row-level parse failures, append `第 N 行：原因`, and continue.

- [ ] **Step 4: Add the real xlsx fixture and failing parseBytes test**

Use the previously supplied Qinghe import template. Include an instruction Sheet before the timetable Sheet and verify real date/time cells, empty rows, odd/even patterns, and duplicate course rows.

- [ ] **Step 5: Implement Sheet scoring**

Decode every Sheet, normalize rows, select the highest-scoring Sheet that contains course-name and weekday semantic headers, and produce a clear workbook-level error when none qualifies.

- [ ] **Step 6: Run importer tests**

Run: `flutter test test/features/timetable/data/excel_timetable_importer_test.dart --reporter expanded`  
Expected: PASS.

- [ ] **Step 7: Commit**

Commit message: `feat: broaden Excel timetable compatibility`

### Task 5: Explicit Android Permission And Scheduling Status

**Files:**
- Modify: `lib/features/reminders/domain/reminder_models.dart`
- Modify: `lib/features/reminders/data/reminder_scheduler.dart`
- Modify: `lib/features/reminders/presentation/reminder_settings_page.dart`
- Modify: `tool/configure_android.dart`
- Test: `test/features/reminders/data/reminder_scheduler_test.dart`
- Test: `test/features/reminders/presentation/reminder_settings_page_test.dart`
- Test: `test/tool/configure_android_test.dart`

**Interfaces:**
- Produces: `ReminderPermissionStatus(notificationsAllowed, exactAlarmsAllowed)`, effective scheduling-mode label, and scheduler methods for opening/requesting relevant Android settings.

- [ ] **Step 1: Add failing model, scheduler, and widget tests**

Test the three states: notifications denied, notifications allowed with inexact alarms, and both allowed. Assert separate rows `通知权限`, `精确闹钟权限`, and `当前调度模式`. Assert button callbacks request/open the matching setting and page refresh updates state.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `flutter test test/features/reminders/data/reminder_scheduler_test.dart test/features/reminders/presentation/reminder_settings_page_test.dart --reporter expanded`  
Expected: FAIL because the combined enum cannot represent both statuses.

- [ ] **Step 3: Implement the permission status model**

Replace the combined enum at scheduler boundaries with:

```dart
class ReminderPermissionStatus {
  const ReminderPermissionStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });
  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  bool get canSchedule => notificationsAllowed;
  bool get usesExactScheduling => notificationsAllowed && exactAlarmsAllowed;
}
```

Update scheduler behavior and fakes accordingly.

- [ ] **Step 4: Implement settings actions and status UI**

Expose separate notification and exact-alarm actions through the gateway. Refresh status after each action and in `didChangeAppLifecycleState` when the page resumes. Display exact or possibly delayed mode. Preserve the rule that inexact permission still enables reminders.

- [ ] **Step 5: Pin notification channels to sound identity**

Keep channel IDs in the form `qinghe_course_reminders_<sound.name>`. Add a pure helper or gateway seam so tests assert system default, chime, soft, and alert select distinct channel/sound combinations.

- [ ] **Step 6: Run permission, channel, and Android configuration tests**

Run: `flutter test test/features/reminders test/tool/configure_android_test.dart --reporter expanded`  
Expected: PASS.

- [ ] **Step 7: Commit**

Commit message: `feat: clarify Android reminder permissions`

### Task 6: Version, Documentation, And Release Artifacts

**Files:**
- Modify: `pubspec.yaml`
- Modify: `.github/workflows/flutter-ci.yml`
- Modify: `README.md`

**Interfaces:**
- Produces: version `0.4.0+4` and three named CI artifacts.

- [ ] **Step 1: Add build-workflow assertions**

Extend an existing tool/configuration test or add `test/tool/release_configuration_test.dart` that reads project files and asserts version `0.4.0+4`, universal APK command, arm64 APK command, appbundle command, and artifact paths.

- [ ] **Step 2: Run the release configuration test and verify RED**

Run: `flutter test test/tool/release_configuration_test.dart --reporter expanded`  
Expected: FAIL against version 0.3.0+3 and missing universal/AAB commands.

- [ ] **Step 3: Update version and CI**

Set `version: 0.4.0+4`. Build universal APK and copy/rename it before the arm64 build so outputs do not overwrite each other. Build AAB and upload all artifacts with versioned names.

- [ ] **Step 4: Update README**

Document:

```bash
flutter create --platforms=android --org com.qinghe --project-name qinghe_timetable .platform_template
cp -R .platform_template/android ./android
dart run tool/configure_android.dart
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release
```

- [ ] **Step 5: Run the release configuration test**

Run: `flutter test test/tool/release_configuration_test.dart --reporter expanded`  
Expected: PASS.

- [ ] **Step 6: Commit**

Commit message: `build: prepare version 0.4.0 Android artifacts`

### Task 7: Full Verification And Delivery

**Files:**
- Review all files changed since `b4381c294577d7838e027a429d6b82a8ada20473`.

- [ ] **Step 1: Run formatting check**

Run: `dart format lib test tool && git diff --exit-code -- '*.dart'`  
Expected: exit 0.

- [ ] **Step 2: Run code generation and static analysis**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter analyze`  
Expected: exit 0 with no analyzer errors.

- [ ] **Step 3: Run the complete test suite**

Run: `flutter test --reporter expanded`  
Expected: all tests pass with zero failures.

- [ ] **Step 4: Push branch and inspect CI**

Push `codex/course-import-reminders`, obtain the exact head SHA, and inspect its GitHub Actions run. Expected: format, analysis, tests, universal APK, arm64 APK, and AAB steps succeed.

- [ ] **Step 5: Perform whole-branch code review**

Review the diff against the approved spec. Fix every Critical or Important finding and repeat Steps 1-4 after any change.

- [ ] **Step 6: Download and validate artifacts**

Download the universal APK artifact, arm64 APK artifact, and AAB artifact. Confirm ZIP integrity, non-zero file sizes, APK package metadata, and version `0.4.0+4`.

- [ ] **Step 7: Deliver**

Provide the universal Release APK as the primary installation package, the arm64 APK as an alternative, the AAB for publishing, the PR link, and a short Android true-device checklist for week selection, four sounds, and permission modes.
