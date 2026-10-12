import '../domain/models.dart';
import '../domain/school_schedule.dart';
import 'timetable_import.dart';

/// Keep observed ranges intact; never invent breaks inside a paired range.
class ImportTimePlan {
  ImportTimePlan._(
    this.schedule,
    this.conflicts,
    this.missingCount,
    this.invalidKeys,
  );
  final SchoolSchedule schedule;
  final Map<String, List<SectionRangeTime>> conflicts;
  final int missingCount;
  final Set<String> invalidKeys;
  factory ImportTimePlan(
    ImportPreview preview,
    SchoolSchedule existing, {
    Iterable<SectionRangeTime> existingTimes = const [],
  }) {
    final candidates = <String, List<SectionRangeTime>>{};
    final starts = <String, Set<int>>{}, ends = <String, Set<int>>{};
    final touched = <String>{};
    final partials = <CourseSession>[];
    String key(int start, int end) => '${preview.semester.id}:$start:$end';
    void observe(String key, int? start, int? end) {
      if (start != null) {
        (starts[key] ??= {}).add(start);
      }
      if (end != null) {
        (ends[key] ??= {}).add(end);
      }
    }

    void add(SectionRangeTime value, {bool observed = true}) {
      final list = candidates.putIfAbsent(value.key, () => []);
      if (!list.any(
        (r) =>
            r.startMinute == value.startMinute &&
            r.endMinute == value.endMinute,
      )) {
        list.add(value);
      }
      if (observed) {
        observe(value.key, value.startMinute, value.endMinute);
      }
    }

    for (final value in preview.importedTimes) {
      touched.add(value.key);
      add(value);
    }
    for (final c in preview.courses) {
      for (final s in c.sessions) {
        final group = key(s.startSection, s.endSection);
        touched.add(group);
        final workbookStarts = {
          for (final value in preview.importedTimes)
            if (value.startSection == s.startSection &&
                value.endSection <= s.endSection)
              value.startMinute,
        };
        final workbookEnds = {
          for (final value in preview.importedTimes)
            if (value.endSection == s.endSection &&
                value.startSection >= s.startSection)
              value.endMinute,
        };
        final start =
            s.timeSource != CourseTimeSource.schedule && s.startMinute != null
            ? s.startMinute
            : workbookStarts.length == 1
            ? workbookStarts.single
            : null;
        final end =
            s.timeSource != CourseTimeSource.schedule && s.endMinute != null
            ? s.endMinute
            : workbookEnds.length == 1
            ? workbookEnds.single
            : null;
        if (start != null && end != null && end > start) {
          add(
            SectionRangeTime(
              semesterId: preview.semester.id,
              startSection: s.startSection,
              endSection: s.endSection,
              startMinute: start,
              endMinute: end,
              source: s.timeSource == CourseTimeSource.schedule
                  ? CourseTimeSource.imported
                  : s.timeSource,
            ),
          );
        }
        if (s.timeSource == CourseTimeSource.schedule) continue;
        observe(group, s.startMinute, s.endMinute);
        if (s.startMinute != null && s.endMinute != null) {
          add(
            SectionRangeTime(
              semesterId: preview.semester.id,
              startSection: s.startSection,
              endSection: s.endSection,
              startMinute: s.startMinute!,
              endMinute: s.endMinute!,
              source: s.timeSource,
            ),
          );
        } else if (s.startMinute != null || s.endMinute != null) {
          partials.add(s);
        }
      }
    }
    // Complete times supplied by this workbook take priority over saved times.
    final workbookTimedKeys = candidates.keys.toSet();
    for (final r in [...existing.rangeTimes, ...existingTimes]) {
      if (touched.contains(r.key) && !workbookTimedKeys.contains(r.key)) {
        add(r, observed: false);
      }
    }
    SectionRangeTime? selected(String group, List<SectionRangeTime> values) {
      final choice = preview.timeChoices[group];
      if (choice != null &&
          choice.key == group &&
          values.any(
            (r) =>
                r.startMinute == choice.startMinute &&
                r.endMinute == choice.endMinute,
          )) {
        return choice;
      }
      return values.length == 1 ? values.single : null;
    }

    final incoming = existing.withRangeTimes([
      for (final entry in candidates.entries)
        if (selected(entry.key, entry.value) case final value?) value,
    ]);
    final invalidKeys = <String>{};
    for (final s in partials) {
      final group = key(s.startSection, s.endSection);
      int? start, end;
      try {
        final fallback = incoming.resolve(
          CourseSession(
            weekday: s.weekday,
            startSection: s.startSection,
            endSection: s.endSection,
            startWeek: s.startWeek,
            endWeek: s.endWeek,
            pattern: s.pattern,
            room: s.room,
            timeSource: CourseTimeSource.schedule,
          ),
          semesterId: preview.semester.id,
        );
        start =
            s.startMinute ??
            (starts[group]?.length == 1
                ? starts[group]!.single
                : fallback.startMinute);
        end =
            s.endMinute ??
            (ends[group]?.length == 1
                ? ends[group]!.single
                : fallback.endMinute);
      } on FormatException {
        invalidKeys.add(group);
        continue;
      }
      if (start == null || end == null || end <= start) {
        invalidKeys.add(group);
        continue;
      }
      add(
        SectionRangeTime(
          semesterId: preview.semester.id,
          startSection: s.startSection,
          endSection: s.endSection,
          startMinute: start,
          endMinute: end,
          source: s.timeSource,
        ),
        observed: false,
      );
    }
    final conflicts = <String, List<SectionRangeTime>>{};
    final resolvedRanges = <SectionRangeTime>[];
    for (final entry in candidates.entries) {
      final value = selected(entry.key, entry.value);
      if (value != null) {
        resolvedRanges.add(value);
      } else {
        conflicts[entry.key] = entry.value;
      }
    }
    var result = existing.withRangeTimes(resolvedRanges);
    var missing = 0;
    for (final c in preview.courses) {
      for (final s in c.sessions) {
        final group = key(s.startSection, s.endSection);
        if (!(starts.containsKey(group) ||
                starts.containsKey(key(s.startSection, s.startSection))) ||
            !(ends.containsKey(group) ||
                ends.containsKey(key(s.endSection, s.endSection)))) {
          missing++;
        }
      }
    }
    final confirmed = preview.sectionSchedule;
    if (confirmed != null &&
        confirmed.semesterSections.containsKey(preview.semester.id)) {
      result = result.withSemesterSections(
        preview.semester.id,
        confirmed.semesterSections[preview.semester.id]!,
        lessonMinutes: confirmed.lessonMinutesFor(preview.semester.id),
        breakMinutes: confirmed.breakMinutesFor(preview.semester.id),
      );
    }
    return ImportTimePlan._(result, conflicts, missing, invalidKeys);
  }
}

class TimetableTimeText {
  static const clock = r'(\d{1,2})\s*[:：]\s*(\d{2})';
  static final pattern = RegExp(
    '(?<!\\d)$clock\\s*(?:[-–—~～至]|到)\\s*$clock(?!\\d)',
  );
  static final startPattern = RegExp('(?:开始(?:时间)?|上课(?:时间)?)[：:\\s]*$clock');
  static final endPattern = RegExp('(?:结束(?:时间)?|下课(?:时间)?)[：:\\s]*$clock');
  static final trailing = RegExp('(?<!\\d)$clock\\s*[-–—~～至]');
  static final leading = RegExp('[-–—~～至]\\s*$clock(?!\\d)');
  static int? _minute(RegExpMatch? match, [int offset = 0]) {
    if (match == null) return null;
    final h = int.parse(match[1 + offset]!), m = int.parse(match[2 + offset]!);
    return h < 24 && m < 60 ? h * 60 + m : null;
  }

  static (int?, int?) bounds(String text) {
    final pair = pattern.firstMatch(text);
    if (pair != null) {
      final start = _minute(pair), end = _minute(pair, 2);
      return start != null && end != null && end > start
          ? (start, end)
          : (null, null);
    }
    return (
      _minute(startPattern.firstMatch(text)) ??
          _minute(trailing.firstMatch(text)),
      _minute(endPattern.firstMatch(text)) ?? _minute(leading.firstMatch(text)),
    );
  }

  static (int, int)? range(String text) {
    final result = bounds(text);
    return result.$1 != null && result.$2 != null
        ? (result.$1!, result.$2!)
        : null;
  }

  static String strip(String text) => text
      .replaceAll(pattern, ' ')
      .replaceAll(startPattern, ' ')
      .replaceAll(endPattern, ' ')
      .replaceAll(trailing, ' ')
      .replaceAll(leading, ' ')
      .replaceAll(RegExp(clock), ' ');
}
