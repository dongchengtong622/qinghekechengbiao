# Android Local Course Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an offline Android timetable whose courses can be created, edited, deleted, persisted, and packaged as an installable APK.

**Architecture:** Drift owns the SQLite schema and transactions. A repository maps database rows to the existing domain models and exposes a reactive stream to the presentation layer. UI forms depend on repository methods rather than Drift-generated types.

**Tech Stack:** Flutter, Dart 3.10+, Drift 2.35.0, drift_flutter 0.3.1, SQLite, flutter_test, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-18-android-local-course-management-design.md`

## Global Constraints

- Android is the only platform built and delivered in this phase.
- Database schema version is `1`.
- Empty first launch receives sample courses exactly once.
- All persistence methods are covered by in-memory SQLite tests.
- CI must generate code before analysis and tests.

---

### Task 1: Drift schema and repository

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/timetable/data/app_database.dart`
- Create: `lib/features/timetable/data/course_repository.dart`
- Test: `test/features/timetable/data/course_repository_test.dart`

**Interfaces:**
- Produces: `CourseRepository.watchCourses()`, `saveCourse(Course)`, `deleteCourse(String)`, and `seedIfEmpty()`.
- Consumes: existing `Course`, `CourseSession`, and `WeekPattern` domain models.

- [ ] Write repository tests for empty state, insertion, update, deletion, reactive watching, and one-time seeding.
- [ ] Run the tests in CI and confirm they fail because database classes are missing.
- [ ] Add Drift dependencies, tables, transaction methods, and domain mapping.
- [ ] Generate `app_database.g.dart` and rerun repository tests.
- [ ] Commit the passing persistence slice.

### Task 2: Course editor validation and UI

**Files:**
- Create: `lib/features/timetable/presentation/course_editor_page.dart`
- Modify: `lib/features/timetable/presentation/timetable_page.dart`
- Test: `test/features/timetable/presentation/course_editor_page_test.dart`
- Modify: `test/features/timetable/presentation/timetable_page_test.dart`

**Interfaces:**
- Consumes: `Future<void> Function(Course)` save callback and optional existing `Course`.
- Produces: a validated `Course` containing exactly one `CourseSession`.

- [ ] Write failing widget tests for required name, invalid section range, save callback, edit prefill, and delete confirmation.
- [ ] Run the tests and confirm failures are caused by missing editor behavior.
- [ ] Implement the form, validation, navigation, edit action, and delete confirmation.
- [ ] Rerun widget tests and refactor only after they pass.
- [ ] Commit the presentation slice.

### Task 3: Application wiring and Android delivery

**Files:**
- Modify: `lib/app.dart`
- Modify: `lib/main.dart`
- Modify: `.github/workflows/flutter-ci.yml`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AppDatabase` and `CourseRepository`.
- Produces: application startup that seeds once and displays database-backed courses.

- [ ] Add an app-level test proving seeded courses reach the timetable page.
- [ ] Wire the repository stream into the page and close the database from the app lifecycle owner.
- [ ] Add `dart run build_runner build --delete-conflicting-outputs` before formatting and analysis in CI.
- [ ] Run formatting, analysis, all tests, and `flutter build apk --debug` in CI.
- [ ] Download and verify the generated APK artifact, then deliver it to the user.

