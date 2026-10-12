import 'package:flutter/material.dart';
import '../domain/school_schedule.dart';
import '../domain/time_slot_resolver.dart';

/// Original ranges stay in the snapshot as evidence; confirmed single slots are scoped.
Future<SchoolSchedule?> confirmSectionSplits(
  BuildContext context,
  SchoolSchedule original,
  String id, {
  bool useDefaultMissing = false,
  Set<String>? rangeKeys,
  Set<String>? freshKeys,
}) async {
  final values = <int, SectionTime>{
    for (final v
        in original.semesterSections[id] ??
            (useDefaultMissing ? original.sections : <SectionTime>[]))
      v.section: v,
  };
  final ranges =
      original.rangeTimes
          .where(
            (r) =>
                r.semesterId == id &&
                (rangeKeys == null || rangeKeys.contains(r.key)),
          )
          .toList()
        ..sort((a, b) {
          final span = (a.endSection - a.startSection).compareTo(
            b.endSection - b.startSection,
          );
          return span != 0 ? span : a.startSection.compareTo(b.startSection);
        });
  for (final r in ranges.where((r) => r.startSection == r.endSection)) {
    values[r.startSection] = SectionTime(
      r.startSection,
      r.startMinute,
      r.endMinute,
    );
  }
  var schedule = original.withSemesterSections(
    id,
    values.values.toList()..sort((a, b) => a.section.compareTo(b.section)),
  );
  final pending = <SectionRangeTime>[];
  for (final r in ranges.where((r) => r.startSection != r.endSection)) {
    final slots = [
      for (var i = r.startSection; i <= r.endSection; i++) values[i],
    ];
    if (slots.every((s) => s != null) &&
        ((freshKeys != null && !freshKeys.contains(r.key)) ||
            (slots.first!.startMinute == r.startMinute &&
                slots.last!.endMinute == r.endMinute))) {
      continue;
    }
    final rule = TimeSlotResolver.split(
      r.startSection,
      r.endSection,
      r.startMinute,
      r.endMinute,
      lessonMinutes: original.lessonMinutesFor(id),
    );
    if (rule.status == SlotStatus.suggested &&
        rule.breakMinutes == original.breakMinutesFor(id) &&
        rule.sections.every(
          (v) =>
              values[v.section] == null ||
              (values[v.section]!.startMinute == v.startMinute &&
                  values[v.section]!.endMinute == v.endMinute),
        )) {
      for (final v in rule.sections) {
        values[v.section] = v;
      }
    } else {
      pending.add(r);
    }
  }
  schedule = schedule.withSemesterSections(
    id,
    values.values.toList()..sort((a, b) => a.section.compareTo(b.section)),
  );
  if (pending.isEmpty) return schedule;
  if (!context.mounted) return null;
  return Navigator.push<SchoolSchedule>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          SectionSplitPage(schedule: schedule, semesterId: id, ranges: pending),
    ),
  );
}

class SectionSplitPage extends StatefulWidget {
  const SectionSplitPage({
    super.key,
    required this.schedule,
    required this.semesterId,
    required this.ranges,
  });
  final SchoolSchedule schedule;
  final String semesterId;
  final List<SectionRangeTime> ranges;
  @override
  State<SectionSplitPage> createState() => _SectionSplitPageState();
}

class _SectionSplitPageState extends State<SectionSplitPage> {
  int? duration;
  String? error;
  bool manual = false;
  final starts = <String, TextEditingController>{},
      ends = <String, TextEditingController>{};
  String key(SectionRangeTime r, int i) => '${r.key}:$i';
  @override
  void initState() {
    super.initState();
    for (final r in widget.ranges) {
      for (var i = r.startSection; i <= r.endSection; i++) {
        final v = widget.schedule.sectionFor(widget.semesterId, i);
        starts[key(r, i)] = TextEditingController(
          text: v == null ? '' : SectionRangeTime.minuteLabel(v.startMinute),
        );
        ends[key(r, i)] = TextEditingController(
          text: v == null ? '' : SectionRangeTime.minuteLabel(v.endMinute),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [...starts.values, ...ends.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<SectionRangeTime> get orderedRanges =>
      List.of(widget.ranges)..sort((a, b) {
        final span = (a.endSection - a.startSection).compareTo(
          b.endSection - b.startSection,
        );
        return span != 0 ? span : a.startSection.compareTo(b.startSection);
      });

  List<SectionTime>? covered(SectionRangeTime r, Map<int, SectionTime> values) {
    final slots = [
      for (var i = r.startSection; i <= r.endSection; i++) values[i],
    ];
    if (slots.any((s) => s == null) ||
        slots.first!.startMinute != r.startMinute ||
        slots.last!.endMinute != r.endMinute) {
      return null;
    }
    return slots.cast<SectionTime>();
  }

  List<SectionTime> proposed(SectionRangeTime r) => manual
      ? [
          for (var i = r.startSection; i <= r.endSection; i++)
            SectionTime(
              i,
              minute(starts[key(r, i)]!.text) ?? -1,
              minute(ends[key(r, i)]!.text) ?? -1,
            ),
        ]
      : TimeSlotResolver.split(
          r.startSection,
          r.endSection,
          r.startMinute,
          r.endMinute,
          lessonMinutes: duration,
        ).sections;

  List<SectionRangeTime> get visibleRanges {
    final values = {
      for (final s
          in widget.schedule.semesterSections[widget.semesterId] ??
              <SectionTime>[])
        s.section: s,
    };
    final visible = <SectionRangeTime>[];
    for (final r in orderedRanges) {
      if (covered(r, values) != null) continue;
      visible.add(r);
      final slots = proposed(r);
      if (slots.isNotEmpty &&
          slots.first.startMinute == r.startMinute &&
          slots.last.endMinute == r.endMinute &&
          slots.every(
            (s) =>
                s.startMinute >= 0 &&
                s.endMinute > s.startMinute &&
                (values[s.section] == null ||
                    (values[s.section]!.startMinute == s.startMinute &&
                        values[s.section]!.endMinute == s.endMinute)),
          )) {
        for (final s in slots) {
          values[s.section] = s;
        }
      }
    }
    return visible;
  }

  int? minute(String s) {
    final m = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!);
    return h < 24 ? h * 60 + int.parse(m[2]!) : null;
  }

  void confirm() {
    try {
      final values = {
        for (final s
            in widget.schedule.semesterSections[widget.semesterId] ??
                <SectionTime>[])
          s.section: s,
      };
      int? consistentGap;
      for (final r in orderedRanges) {
        if (covered(r, values) != null) continue;
        final resolution = TimeSlotResolver.split(
          r.startSection,
          r.endSection,
          r.startMinute,
          r.endMinute,
          lessonMinutes: duration,
        );
        final slots = proposed(r);
        if (slots.isEmpty) {
          throw FormatException(resolution.reason ?? '请选择时长或逐节修改');
        }
        if (slots.first.startMinute != r.startMinute ||
            slots.last.endMinute != r.endMinute) {
          throw const FormatException('拆分后的起止端点必须与原始区间一致');
        }
        for (final s in slots) {
          final previous = values[s.section];
          if (previous != null &&
              (previous.startMinute != s.startMinute ||
                  previous.endMinute != s.endMinute)) {
            throw FormatException('第${s.section}节与明确的小节时间冲突，请核对原始课表');
          }
          values[s.section] = s;
        }
        if (!manual) {
          if (consistentGap != null &&
              consistentGap != resolution.breakMinutes) {
            consistentGap = -1;
          } else {
            consistentGap ??= resolution.breakMinutes;
          }
        }
      }
      final result = widget.schedule.withSemesterSections(
        widget.semesterId,
        values.values.toList()..sort((a, b) => a.section.compareTo(b.section)),
        lessonMinutes: manual ? null : duration,
        breakMinutes: consistentGap != null && consistentGap >= 0
            ? consistentGap
            : null,
      );
      Navigator.pop(context, result);
    } catch (e) {
      setState(() => error = e is FormatException ? e.message : '请核对逐节时间');
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('确认节次时间拆分')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('课程起止时间来自课表。以下只确认每小节如何拆分，不替换成旧作息。未知节长不能自动按45分钟计算。'),
        DropdownButtonFormField<int>(
          initialValue: duration,
          decoration: const InputDecoration(labelText: '单节时长'),
          items: [
            for (final n in [40, 45, 50, 60, 90])
              DropdownMenuItem(value: n, child: Text('$n 分钟')),
          ],
          onChanged: (v) => setState(() {
            duration = v;
            error = null;
          }),
        ),
        SwitchListTile(
          title: const Text('逐节手动修改'),
          subtitle: const Text('用于不同节长、长课间或无法整分钟拆分'),
          value: manual,
          onChanged: (v) => setState(() => manual = v),
        ),
        for (final r in visibleRanges)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '原始：第${r.startSection}–${r.endSection}节 ${r.label}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (manual)
                    for (var i = r.startSection; i <= r.endSection; i++)
                      Row(
                        children: [
                          Text('第$i节 '),
                          Expanded(
                            child: TextField(
                              controller: starts[key(r, i)],
                              onChanged: (_) => setState(() => error = null),
                              decoration: const InputDecoration(
                                labelText: '开始HH:mm',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: ends[key(r, i)],
                              onChanged: (_) => setState(() => error = null),
                              decoration: const InputDecoration(
                                labelText: '结束HH:mm',
                              ),
                            ),
                          ),
                        ],
                      )
                  else
                    ...preview(r),
                ],
              ),
            ),
          ),
        if (error != null)
          Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
        FilledButton(onPressed: confirm, child: const Text('确认拆分并继续导入')),
      ],
    ),
  );
  List<Widget> preview(SectionRangeTime r) {
    final result = TimeSlotResolver.split(
      r.startSection,
      r.endSection,
      r.startMinute,
      r.endMinute,
      lessonMinutes: duration,
    );
    return [
      if (result.sections.isEmpty) Text(result.reason ?? '请核对时间'),
      for (final s in result.sections)
        Text(
          '第${s.section}节 ${SectionRangeTime.minuteLabel(s.startMinute)}–${SectionRangeTime.minuteLabel(s.endMinute)}',
        ),
      if (result.breakMinutes != null)
        Text(
          result.breakMinutes == 0
              ? '课间0分钟；仅在你确认符合学校作息后采用'
              : '课间${result.breakMinutes}分钟；以上为所选时长的拆分建议',
        ),
    ];
  }
}
