import 'dart:convert';
import 'models.dart';

class SectionTime {
  const SectionTime(this.section, this.startMinute, this.endMinute);
  final int section, startMinute, endMinute;
}

class PrepPeriod {
  const PrepPeriod(this.startMinute, this.endMinute);
  final int startMinute, endMinute;
}

/// An exact period range shared by courses within one semester.
/// A paired range does not imply the times of its individual periods.
class SectionRangeTime {
  const SectionRangeTime({
    required this.semesterId,
    required this.startSection,
    required this.endSection,
    required this.startMinute,
    required this.endMinute,
    this.source = CourseTimeSource.imported,
  });
  final String semesterId;
  final int startSection, endSection, startMinute, endMinute;
  final CourseTimeSource source;
  String get key => '$semesterId:$startSection:$endSection';
  String get label => '${minuteLabel(startMinute)}–${minuteLabel(endMinute)}';
  static String minuteLabel(int value) =>
      '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
}

class SchoolSchedule {
  SchoolSchedule({
    required this.id,
    required List<SectionTime> sections,
    List<PrepPeriod> prepPeriods = const [],
    List<SectionRangeTime> rangeTimes = const [],
    Map<String, List<SectionTime>> semesterSections = const {},
    Map<String, int> lessonMinutes = const {},
    Map<String, int> breakMinutes = const {},
    Map<String, int> sectionCounts = const {},
    Map<String, bool> fixedLessonDuration = const {},
  }) : semesterSections = Map.unmodifiable({
         for (final e in semesterSections.entries)
           e.key: List<SectionTime>.unmodifiable(e.value),
       }),
       sectionCounts = Map.unmodifiable(sectionCounts),
       fixedLessonDuration = Map.unmodifiable(fixedLessonDuration),
       lessonMinutes = Map.unmodifiable(lessonMinutes),
       breakMinutes = Map.unmodifiable(breakMinutes),
       sections = List.unmodifiable(sections),
       rangeTimes = List.unmodifiable(rangeTimes),
       prepPeriods = List.unmodifiable(prepPeriods) {
    if (sections.isEmpty || sections.length > 30) {
      throw const FormatException('作息表需要包含 1–30 个节次。');
    }
    var previousEnd = -1;
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (s.section != i + 1 ||
          s.startMinute < 0 ||
          s.endMinute >= 1440 ||
          s.endMinute <= s.startMinute ||
          s.startMinute < previousEnd) {
        throw const FormatException('请按顺序填写连续节次，结束时间须晚于开始时间，各节时间不能重叠。');
      }
      previousEnd = s.endMinute;
    }
    for (final entry in this.semesterSections.entries) {
      var end = -1, section = 0;
      for (final value in entry.value) {
        if (entry.key.isEmpty ||
            value.section <= section ||
            value.section > 30 ||
            value.startMinute < end ||
            value.startMinute < 0 ||
            value.endMinute <= value.startMinute ||
            value.endMinute >= 1440) {
          throw const FormatException('逐节作息重复、重叠或顺序无效');
        }
        end = value.endMinute;
        section = value.section;
      }
    }
    if (sectionCounts.entries.any(
      (e) => e.key.isEmpty || e.value < 1 || e.value > 30,
    )) {
      throw const FormatException('作息表需要包含 1–30 个节次。');
    }
    for (final entry in sectionCounts.entries) {
      if ((semesterSections[entry.key] ?? []).any(
            (s) => s.section > entry.value,
          ) ||
          rangeTimes.any(
            (r) => r.semesterId == entry.key && r.endSection > entry.value,
          )) {
        throw const FormatException('作息时间超出已设置的节次范围');
      }
    }
    if (lessonMinutes.values.any((v) => v <= 0 || v > 180) ||
        breakMinutes.values.any((v) => v < 0 || v > 180)) {
      throw const FormatException('节长或课间规则无效');
    }
    for (final p in prepPeriods) {
      if (p.startMinute < 0 ||
          p.endMinute >= 1440 ||
          p.endMinute <= p.startMinute) {
        throw const FormatException('预备时段无效。');
      }
    }
    final keys = <String>{};
    for (final r in rangeTimes) {
      if (r.semesterId.isEmpty ||
          r.startSection < 1 ||
          r.endSection < r.startSection ||
          r.endSection > 30 ||
          r.startMinute < 0 ||
          r.endMinute >= 1440 ||
          r.endMinute <= r.startMinute ||
          r.source == CourseTimeSource.schedule ||
          !keys.add(r.key)) {
        throw const FormatException('同节次时间规则无效或重复。');
      }
    }
  }
  final String id;
  final Map<String, List<SectionTime>> semesterSections;
  final Map<String, int> lessonMinutes, breakMinutes, sectionCounts;
  final Map<String, bool> fixedLessonDuration;
  bool fixedLessonDurationFor(String id) => fixedLessonDuration[id] ?? false;
  int? lessonMinutesFor(String id) => lessonMinutes[id];
  int? breakMinutesFor(String id) => breakMinutes[id];
  int sectionCountFor(String id) =>
      sectionCounts[id] ??
      [
        sections.length,
        ...?semesterSections[id]?.map((s) => s.section),
        ...rangeTimes.where((r) => r.semesterId == id).map((r) => r.endSection),
      ].reduce((a, b) => a > b ? a : b);
  SectionTime? sectionFor(String? id, int number) {
    if (id != null && number > sectionCountFor(id)) return null;
    final scoped = semesterSections[id];
    if (scoped != null) {
      return scoped.where((s) => s.section == number).firstOrNull;
    }
    final explicit = range(id, number, number);
    if (explicit != null) {
      return SectionTime(number, explicit.startMinute, explicit.endMinute);
    }
    return section(number);
  }

  SchoolSchedule withSemesterSections(
    String semesterId,
    List<SectionTime> values, {
    int? lessonMinutes,
    int? breakMinutes,
    int? sectionCount,
    bool? fixedLessonDuration,
    bool replaceRules = false,
  }) {
    final counts = {...sectionCounts};
    if (sectionCount != null) {
      counts[semesterId] = sectionCount;
    } else if (counts.containsKey(semesterId)) {
      for (final value in values) {
        if (value.section > counts[semesterId]!) {
          counts[semesterId] = value.section;
        }
      }
    }
    return SchoolSchedule(
      id: id,
      sections: sections,
      prepPeriods: prepPeriods,
      rangeTimes: [
        for (final r in rangeTimes)
          if (r.semesterId != semesterId ||
              sectionCount == null ||
              r.endSection <= sectionCount)
            r,
      ],
      semesterSections: {...semesterSections, semesterId: values},
      sectionCounts: counts,
      fixedLessonDuration: {
        ...this.fixedLessonDuration,
        if (fixedLessonDuration != null) semesterId: fixedLessonDuration,
      },
      lessonMinutes: {
        for (final e in this.lessonMinutes.entries)
          if (!replaceRules || e.key != semesterId) e.key: e.value,
        if (lessonMinutes != null) semesterId: lessonMinutes,
      },
      breakMinutes: {
        for (final e in this.breakMinutes.entries)
          if (!replaceRules || e.key != semesterId) e.key: e.value,
        if (breakMinutes != null) semesterId: breakMinutes,
      },
    );
  }

  final List<SectionTime> sections;
  final List<PrepPeriod> prepPeriods;
  final List<SectionRangeTime> rangeTimes;
  SchoolSchedule withRangeTime(SectionRangeTime value) =>
      withRangeTimes([value]);
  SchoolSchedule withRangeTimes(Iterable<SectionRangeTime> incoming) {
    final updates = incoming.toList();
    final revised = <String, List<SectionTime>>{
      for (final e in semesterSections.entries) e.key: List.of(e.value),
    };
    for (final value in updates) {
      final original = semesterSections[value.semesterId];
      if (original == null) continue;
      final first = original
          .where((s) => s.section == value.startSection)
          .firstOrNull;
      final last = original
          .where((s) => s.section == value.endSection)
          .firstOrNull;
      if (first?.startMinute != value.startMinute ||
          last?.endMinute != value.endMinute) {
        revised[value.semesterId]!.removeWhere(
          (s) =>
              s.section >= value.startSection && s.section <= value.endSection,
        );
      }
    }
    for (final value in updates.where((v) => v.startSection == v.endSection)) {
      final profile = revised[value.semesterId];
      if (profile != null) {
        profile.removeWhere((s) => s.section == value.startSection);
        profile.add(
          SectionTime(value.startSection, value.startMinute, value.endMinute),
        );
      }
    }
    for (final profile in revised.values) {
      profile.sort((a, b) => a.section.compareTo(b.section));
    }
    final ranges = {
      for (final r in rangeTimes) r.key: r,
      for (final r in updates) r.key: r,
    };
    return SchoolSchedule(
      id: id,
      sections: sections,
      prepPeriods: prepPeriods,
      semesterSections: revised,
      lessonMinutes: lessonMinutes,
      breakMinutes: breakMinutes,
      rangeTimes: ranges.values.toList(),
      sectionCounts: {
        for (final e in sectionCounts.entries)
          e.key: [
            e.value,
            ...updates
                .where((r) => r.semesterId == e.key)
                .map((r) => r.endSection),
          ].reduce((a, b) => a > b ? a : b),
      },
      fixedLessonDuration: {
        ...fixedLessonDuration,
        for (final r in updates)
          if (range(r.semesterId, r.startSection, r.endSection)?.startMinute !=
                  r.startMinute ||
              range(r.semesterId, r.startSection, r.endSection)?.endMinute !=
                  r.endMinute)
            r.semesterId: false,
      },
    );
  }

  SectionRangeTime? range(String? semesterId, int start, int end) {
    for (final r in rangeTimes) {
      if (r.semesterId == semesterId &&
          r.startSection == start &&
          r.endSection == end) {
        return r;
      }
    }
    return null;
  }

  factory SchoolSchedule.defaults() => SchoolSchedule(
    id: 'default',
    sections: const [
      SectionTime(1, 505, 550),
      SectionTime(2, 555, 600),
      SectionTime(3, 615, 660),
      SectionTime(4, 665, 710),
      SectionTime(5, 820, 865),
      SectionTime(6, 870, 915),
      SectionTime(7, 930, 975),
      SectionTime(8, 980, 1025),
      SectionTime(9, 1030, 1075),
      SectionTime(10, 1125, 1170),
      SectionTime(11, 1175, 1220),
      SectionTime(12, 1225, 1270),
    ],
    prepPeriods: const [
      PrepPeriod(495, 505),
      PrepPeriod(810, 820),
      PrepPeriod(1115, 1125),
    ],
  );
  SectionTime? section(int number) =>
      number > 0 && number <= sections.length ? sections[number - 1] : null;
  CourseSession resolve(CourseSession session, {String? semesterId}) {
    final shared = range(semesterId, session.startSection, session.endSection);
    final explicit = session.timeSource != CourseTimeSource.schedule;
    final scoped = semesterSections[semesterId];
    final allConfirmed =
        scoped != null &&
        [
          for (var i = session.startSection; i <= session.endSection; i++)
            scoped.where((s) => s.section == i).firstOrNull,
        ].every((s) => s != null);
    final profileStart = allConfirmed
        ? scoped
              .where((s) => s.section == session.startSection)
              .first
              .startMinute
        : null;
    final profileEnd = allConfirmed
        ? scoped.where((s) => s.section == session.endSection).first.endMinute
        : null;
    final start =
        profileStart ??
        shared?.startMinute ??
        (explicit ? session.startMinute : null) ??
        range(
          semesterId,
          session.startSection,
          session.startSection,
        )?.startMinute ??
        sectionFor(semesterId, session.startSection)?.startMinute;
    final end =
        profileEnd ??
        shared?.endMinute ??
        (explicit ? session.endMinute : null) ??
        range(semesterId, session.endSection, session.endSection)?.endMinute ??
        sectionFor(semesterId, session.endSection)?.endMinute;
    if (start != null && end != null && end <= start) {
      throw const FormatException('上课时间发生冲突，请核对节次和作息时间。');
    }
    return CourseSession(
      weekday: session.weekday,
      startSection: session.startSection,
      endSection: session.endSection,
      startWeek: session.startWeek,
      endWeek: session.endWeek,
      pattern: session.pattern,
      room: session.room,
      timeSource: shared?.source ?? session.timeSource,
      startMinute: start,
      endMinute: end,
    );
  }

  String encode() => jsonEncode({
    'schemaVersion': 2,
    'id': id,
    'semesterSections': {
      for (final e in semesterSections.entries)
        e.key: e.value
            .map((s) => [s.section, s.startMinute, s.endMinute])
            .toList(),
    },
    'sectionCounts': sectionCounts,
    'fixedLessonDuration': fixedLessonDuration,
    'lessonMinutes': lessonMinutes,
    'breakMinutes': breakMinutes,
    'sections': sections
        .map((s) => [s.section, s.startMinute, s.endMinute])
        .toList(),
    'prep': prepPeriods.map((p) => [p.startMinute, p.endMinute]).toList(),
    'ranges': rangeTimes
        .map(
          (r) => [
            r.semesterId,
            r.startSection,
            r.endSection,
            r.startMinute,
            r.endMinute,
            r.source.name,
          ],
        )
        .toList(),
  });
  factory SchoolSchedule.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return SchoolSchedule(
      id: data['id'] as String,
      semesterSections: {
        for (final e
            in (data['semesterSections'] as Map<String, dynamic>? ?? {})
                .entries)
          e.key: (e.value as List)
              .map((s) => SectionTime(s[0] as int, s[1] as int, s[2] as int))
              .toList(),
      },
      sectionCounts: Map<String, int>.from(data['sectionCounts'] as Map? ?? {}),
      fixedLessonDuration: Map<String, bool>.from(
        data['fixedLessonDuration'] as Map? ?? {},
      ),
      lessonMinutes: Map<String, int>.from(data['lessonMinutes'] as Map? ?? {}),
      breakMinutes: Map<String, int>.from(data['breakMinutes'] as Map? ?? {}),
      sections: (data['sections'] as List)
          .map((s) => SectionTime(s[0] as int, s[1] as int, s[2] as int))
          .toList(),
      prepPeriods: (data['prep'] as List? ?? [])
          .map((p) => PrepPeriod(p[0] as int, p[1] as int))
          .toList(),
      rangeTimes: (data['ranges'] as List? ?? [])
          .map(
            (r) => SectionRangeTime(
              semesterId: r[0] as String,
              startSection: r[1] as int,
              endSection: r[2] as int,
              startMinute: r[3] as int,
              endMinute: r[4] as int,
              source: CourseTimeSource.values.byName(r[5] as String),
            ),
          )
          .toList(),
    );
  }
}
