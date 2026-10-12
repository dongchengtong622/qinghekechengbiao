import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import '../../timetable/domain/school_schedule.dart';
import '../../timetable/domain/models.dart';

class ScopedSchedulePage extends StatefulWidget {
  const ScopedSchedulePage({
    super.key,
    required this.semester,
    required this.schedule,
    required this.onSave,
    this.minimumSectionCount = 1,
  });
  final Semester semester;
  final SchoolSchedule schedule;
  final Future<void> Function(SchoolSchedule) onSave;
  final int minimumSectionCount;
  @override
  State<ScopedSchedulePage> createState() => _ScopedSchedulePageState();
}

class _ScopedSchedulePageState extends State<ScopedSchedulePage> {
  final starts = <TextEditingController>[], ends = <TextEditingController>[];
  final length = TextEditingController();
  bool busy = false, fixed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    fixed = widget.schedule.fixedLessonDurationFor(widget.semester.id);
    final confirmed = widget.schedule.semesterSections[widget.semester.id];
    final imported = widget.schedule.rangeTimes
        .where((r) => r.semesterId == widget.semester.id)
        .toList();
    final values = <int, SectionTime>{
      if (confirmed != null)
        for (final v in confirmed) v.section: v,
      if (confirmed == null && imported.isEmpty)
        for (final v in widget.schedule.sections) v.section: v,
      if (confirmed == null)
        for (final r in imported.where((r) => r.startSection == r.endSection))
          r.startSection: SectionTime(
            r.startSection,
            r.startMinute,
            r.endMinute,
          ),
    };
    final durations = values.values
        .map((v) => v.endMinute - v.startMinute)
        .toSet();
    length.text =
        '${widget.schedule.lessonMinutesFor(widget.semester.id) ?? (durations.length == 1 ? durations.single : 45)}';
    // Imported evidence is displayed unchanged, even after a previous fixed-duration setting.
    if (durations.any((d) => d != int.tryParse(length.text))) fixed = false;
    final configuredCount = widget.schedule.sectionCountFor(widget.semester.id);
    final n = configuredCount > widget.minimumSectionCount
        ? configuredCount
        : widget.minimumSectionCount;
    for (var i = 1; i <= n; i++) {
      final s = values[i];
      starts.add(
        TextEditingController(
          text: s == null ? '' : SectionRangeTime.minuteLabel(s.startMinute),
        ),
      );
      ends.add(
        TextEditingController(
          text: s == null ? '' : SectionRangeTime.minuteLabel(s.endMinute),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final c in [...starts, ...ends, length]) {
      c.dispose();
    }
    super.dispose();
  }

  int? minute(String v) {
    final m = RegExp(
      r'^(\d{1,2}):([0-5]\d)$',
    ).firstMatch(v.trim().replaceAll('：', ':'));
    if (m == null) return null;
    final h = int.parse(m[1]!);
    return h < 24 ? h * 60 + int.parse(m[2]!) : null;
  }

  void calculateEnd(int i) {
    final start = minute(starts[i].text),
        duration = int.tryParse(length.text.trim());
    final value =
        start != null &&
            duration != null &&
            duration > 0 &&
            duration <= 180 &&
            start + duration < 1440
        ? SectionRangeTime.minuteLabel(start + duration)
        : '';
    if (ends[i].text != value) ends[i].text = value;
  }

  void calculateAll() {
    for (var i = 0; i < starts.length; i++) {
      calculateEnd(i);
    }
  }

  void removeLast() {
    if (starts.length <= widget.minimumSectionCount) {
      setState(
        () => error = starts.length == 1
            ? '至少保留一节作息。'
            : '第${starts.length}节仍有课程使用，请先调整课程后再删除。',
      );
      return;
    }
    final start = starts.removeLast(), end = ends.removeLast();
    setState(() => error = null);
    // Dispose after the removed text fields have detached from their controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      start.dispose();
      end.dispose();
    });
  }

  Future<void> pickDuration() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ScheduleWheelSheet(
        title: '每节课时长',
        initial: [(int.tryParse(length.text) ?? 45) - 1],
        maximum: [180],
        duration: true,
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      length.text = '$value';
      calculateAll();
      error = null;
    });
  }

  Future<void> pickTime(int i, bool start) async {
    final controller = start ? starts[i] : ends[i];
    final current = minute(controller.text) ?? 480;
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ScheduleWheelSheet(
        title: '第${i + 1}节${start ? '开始' : '结束'}时间',
        initial: [current ~/ 60, current % 60],
        maximum: [24, 60],
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      controller.text = SectionRangeTime.minuteLabel(value);
      if (start && fixed) calculateEnd(i);
      error = null;
    });
  }

  Widget timeButton(int i, bool start) {
    final value = (start ? starts[i] : ends[i]).text;
    final disabled = busy || (!start && fixed);
    return OutlinedButton(
      key: Key('section_${start ? 'start' : 'end'}_${i + 1}'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        side: BorderSide.none,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      onPressed: disabled ? null : () => pickTime(i, start),
      child: Text(
        value.isEmpty ? '选择时间' : value,
        style: TextStyle(
          fontSize: 17,
          color: disabled
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
      ),
    );
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final duration = fixed ? int.tryParse(length.text.trim()) : null;
      if (fixed && (duration == null || duration < 1 || duration > 180)) {
        throw const FormatException('每节课时长请输入 1–180 的整数分钟。');
      }
      if (fixed) calculateAll();
      final values = <SectionTime>[];
      for (var i = 0; i < starts.length; i++) {
        if (starts[i].text.trim().isEmpty && ends[i].text.trim().isEmpty) {
          continue;
        }
        final a = minute(starts[i].text), b = minute(ends[i].text);
        if (a == null || b == null) {
          throw const FormatException('请填写完整的 24 小时制 HH:mm 时间；结束时间不能跨到次日。');
        }
        values.add(SectionTime(i + 1, a, b));
      }
      final next = widget.schedule.withSemesterSections(
        widget.semester.id,
        values,
        sectionCount: starts.length,
        fixedLessonDuration: fixed,
        lessonMinutes: duration,
        replaceRules: true,
      );
      await widget.onSave(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is FormatException ? e.message : '保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('作息时间')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.semester.name),
        const Text('这里与导入课表共用同一份作息。导入并确认的时间会同步更新这里；尚未导入时间时使用初始作息。留空节次保持待确认。'),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('fixed_lesson_duration'),
                title: const Text('固定上课时长'),
                subtitle: Text(fixed ? '只需填写开始时间，结束时间自动计算' : '每节开始和结束时间可分别修改'),
                value: fixed,
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        fixed = v;
                        error = null;
                        if (v) calculateAll();
                      }),
              ),
              if (fixed)
                ListTile(
                  key: const Key('lesson_minutes'),
                  title: const Text('每节课时长（分钟）'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${length.text} 分钟'),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: busy ? null : pickDuration,
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('时间使用 24 小时制。点击时间使用滚轮选择，选好后点“保存”。课间由相邻节次的时间自然形成。'),
        ),
        for (var i = 0; i < starts.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text('第${i + 1}节')),
                Expanded(child: timeButton(i, true)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–'),
                ),
                Expanded(child: timeButton(i, false)),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: busy || starts.length >= 30
                    ? null
                    : () => setState(() {
                        starts.add(TextEditingController());
                        ends.add(TextEditingController());
                        error = null;
                      }),
                child: const Text('补充节次'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: busy ? null : removeLast,
                child: const Text('删除最后一节'),
              ),
            ),
          ],
        ),
        if (error != null)
          Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? '正在保存…' : '保存作息'),
        ),
      ],
    ),
  );
}

class _ScheduleWheelSheet extends StatefulWidget {
  const _ScheduleWheelSheet({
    required this.title,
    required this.initial,
    required this.maximum,
    this.duration = false,
  });
  final String title;
  final List<int> initial, maximum;
  final bool duration;
  @override
  State<_ScheduleWheelSheet> createState() => _ScheduleWheelSheetState();
}

class _ScheduleWheelSheetState extends State<_ScheduleWheelSheet> {
  late final List<int> selected = List.of(widget.initial);
  late final List<FixedExtentScrollController> controllers = [
    for (final i in widget.initial) FixedExtentScrollController(initialItem: i),
  ];
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                key: const Key('wheel_cancel'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                for (var col = 0; col < selected.length; col++) ...[
                  if (col > 0) const Text(':', style: TextStyle(fontSize: 26)),
                  Expanded(
                    child: CupertinoPicker(
                      key: Key('wheel_$col'),
                      scrollController: controllers[col],
                      itemExtent: 44,
                      onSelectedItemChanged: (v) => selected[col] = v,
                      children: [
                        for (var item = 0; item < widget.maximum[col]; item++)
                          Center(
                            child: Text(
                              widget.duration
                                  ? '${item + 1} 分钟'
                                  : '$item'.padLeft(2, '0'),
                              style: const TextStyle(fontSize: 23),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('wheel_save'),
              onPressed: () => Navigator.pop(
                context,
                widget.duration
                    ? selected[0] + 1
                    : selected[0] * 60 + selected[1],
              ),
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    ),
  );
}
