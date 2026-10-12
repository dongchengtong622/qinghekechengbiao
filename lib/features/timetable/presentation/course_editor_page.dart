import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/school_schedule.dart';

typedef CourseTimePicker =
    Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initialTime);

class CourseEditorPage extends StatefulWidget {
  const CourseEditorPage({
    super.key,
    required this.semesterId,
    this.initialCourse,
    this.timePicker,
    this.maxScheduleSection = 12,
    this.schedule,
    this.onSaveSharedTimes,
    required this.onSave,
  });

  final String semesterId;
  final int maxScheduleSection;
  final Course? initialCourse;
  final CourseTimePicker? timePicker;
  final SchoolSchedule? schedule;
  final Future<void> Function(Course course)? onSaveSharedTimes;
  final Future<void> Function(Course course) onSave;

  @override
  State<CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<CourseEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _room;
  late final TextEditingController _startSection;
  late final TextEditingController _endSection;
  late final TextEditingController _startWeek;
  late final TextEditingController _endWeek;
  late int _weekday;
  late WeekPattern _pattern;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _saving = false;
  bool _timeChanged = false;
  bool _sectionsChanged = false;
  CourseTimeSource get _source => _sectionsChanged
      ? CourseTimeSource.schedule
      : _initialSession?.timeSource ?? CourseTimeSource.schedule;
  int _colorValue = 0xFF2E7D66;

  CourseSession? get _initialSession =>
      widget.initialCourse?.sessions.isNotEmpty == true
      ? widget.initialCourse!.sessions.first
      : null;

  @override
  void initState() {
    super.initState();
    final course = widget.initialCourse;
    _colorValue = course?.colorValue ?? 0xFF2E7D66;
    final session = _initialSession;
    _name = TextEditingController(text: course?.name ?? '');
    _teacher = TextEditingController(text: course?.teacher ?? '');
    _room = TextEditingController(text: session?.room ?? '');
    _startSection = TextEditingController(
      text: '${session?.startSection ?? 1}',
    );
    _endSection = TextEditingController(text: '${session?.endSection ?? 2}');
    _startWeek = TextEditingController(text: '${session?.startWeek ?? 1}');
    _endWeek = TextEditingController(text: '${session?.endWeek ?? 18}');
    _weekday = session?.weekday ?? DateTime.monday;
    _pattern = session?.pattern ?? WeekPattern.everyWeek;
    _startTime =
        session != null && session.timeSource != CourseTimeSource.schedule
        ? _timeOfDay(session.startMinute)
        : null;
    _endTime =
        session != null && session.timeSource != CourseTimeSource.schedule
        ? _timeOfDay(session.endMinute)
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    _startSection.dispose();
    _endSection.dispose();
    _startWeek.dispose();
    _endWeek.dispose();
    super.dispose();
  }

  int _number(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  String? _positiveNumber(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    return number != null && number > 0 ? null : '请输入大于 0 的数字';
  }

  TimeOfDay? _timeOfDay(int? minute) => minute == null
      ? null
      : TimeOfDay(hour: minute ~/ 60, minute: minute % 60);

  int? _minuteOfDay(TimeOfDay? time) =>
      time == null ? null : time.hour * 60 + time.minute;

  CourseSession? get _effectiveSession {
    final start = _number(_startSection), end = _number(_endSection);
    if (start < 1 || end < start) return null;
    try {
      return (widget.schedule ?? SchoolSchedule.defaults()).resolve(
        CourseSession(
          weekday: _weekday,
          startSection: start,
          endSection: end,
          startWeek: 1,
          endWeek: 1,
          room: '',
          pattern: WeekPattern.everyWeek,
          startMinute: _timeChanged ? null : _minuteOfDay(_startTime),
          endMinute: _timeChanged ? null : _minuteOfDay(_endTime),
          timeSource: _timeChanged ? CourseTimeSource.schedule : _source,
        ),
        semesterId: widget.semesterId,
      );
    } on FormatException {
      return null;
    }
  }

  TimeOfDay? get _displayStart =>
      _startTime ?? _timeOfDay(_effectiveSession?.startMinute);
  TimeOfDay? get _displayEnd =>
      _endTime ?? _timeOfDay(_effectiveSession?.endMinute);

  String _timeLabel(TimeOfDay? time) {
    if (time == null) return '请填写时间';
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _selectTime({required bool start}) async {
    final initial = start
        ? _displayStart ?? const TimeOfDay(hour: 8, minute: 25)
        : _displayEnd ?? const TimeOfDay(hour: 10, minute: 0);
    final selected =
        await (widget.timePicker ??
            (context, initialTime) => showTimePicker(
              context: context,
              initialTime: initialTime,
            ))(context, initial);
    if (selected == null || !mounted) return;
    setState(() {
      _startTime ??= _timeOfDay(_effectiveSession?.startMinute);
      _endTime ??= _timeOfDay(_effectiveSession?.endMinute);
      _timeChanged = true;
      if (start) {
        _startTime = selected;
      } else {
        _endTime = selected;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final startMinute = _minuteOfDay(_startTime);
    final endMinute = _minuteOfDay(_endTime);
    if (_timeChanged && startMinute == null && endMinute != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择开始时间')));
      return;
    }
    if (_timeChanged && (startMinute == null || endMinute == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写完整的开始和结束时间')));
      return;
    }
    if (startMinute != null && endMinute != null && endMinute <= startMinute) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    if (_number(_endSection) > widget.maxScheduleSection &&
        startMinute == null &&
        _effectiveSession?.startMinute == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该节次没有默认作息，请填写开始时间')));
      return;
    }
    setState(() => _saving = true);
    final course = Course(
      id:
          widget.initialCourse?.id ??
          'course-${DateTime.now().microsecondsSinceEpoch}',
      semesterId: widget.initialCourse?.semesterId ?? widget.semesterId,
      source: widget.initialCourse?.source ?? CourseSource.manual,
      externalId: widget.initialCourse?.externalId,
      name: _name.text.trim(),
      teacher: _teacher.text.trim(),
      colorValue: _colorValue,
      sessions: [
        CourseSession(
          weekday: _weekday,
          startSection: _number(_startSection),
          endSection: _number(_endSection),
          startWeek: _number(_startWeek),
          endWeek: _number(_endWeek),
          pattern: _pattern,
          room: _room.text.trim(),
          startMinute: startMinute,
          endMinute: endMinute,
          timeSource: _timeChanged ? CourseTimeSource.custom : _source,
        ),
        ...?widget.initialCourse?.sessions.skip(1),
      ],
    );
    try {
      await (_timeChanged
          ? widget.onSaveSharedTimes ?? widget.onSave
          : widget.onSave)(course);
      if (mounted) await Navigator.of(context).maybePop();
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请重试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialCourse == null ? '添加课程' : '编辑课程'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final color in const [
                  0xFF2E7D66,
                  0xFF6366A8,
                  0xFFD77855,
                  0xFF9A6BB5,
                  0xFF3978A8,
                  0xFFB46A7A,
                ])
                  ChoiceChip(
                    label: const Text(''),
                    avatar: CircleAvatar(
                      backgroundColor: Color(color),
                      radius: 10,
                    ),
                    selected: _colorValue == color,
                    onSelected: (_) => setState(() => _colorValue = color),
                  ),
              ],
            ),
            TextFormField(
              key: const Key('course_name'),
              controller: _name,
              decoration: const InputDecoration(labelText: '课程名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入课程名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('teacher'),
              controller: _teacher,
              decoration: const InputDecoration(labelText: '教师'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('room'),
              controller: _room,
              decoration: const InputDecoration(labelText: '教室'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(labelText: '星期'),
              items: List.generate(
                DateTime.daysPerWeek,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('周${'一二三四五六日'[index]}'),
                ),
              ),
              onChanged: (value) => setState(() => _weekday = value!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    key: const Key('start_time'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开始时间'),
                    subtitle: Text(_timeLabel(_displayStart)),
                    trailing: const Icon(Icons.schedule_rounded),
                    onTap: () => _selectTime(start: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListTile(
                    key: const Key('end_time'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('结束时间'),
                    subtitle: Text(_timeLabel(_displayEnd)),
                    trailing: const Icon(Icons.schedule_rounded),
                    onTap: () => _selectTime(start: false),
                  ),
                ),
              ],
            ),
            const Text('手动修改时间并保存后，本学期相同开始和结束节次的课程会同步。'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('start_section'),
                    controller: _startSection,
                    onChanged: (_) => setState(() {
                      _sectionsChanged = true;
                      _startTime = null;
                      _endTime = null;
                      _timeChanged = false;
                    }),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '开始节次'),
                    validator: _positiveNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('end_section'),
                    controller: _endSection,
                    onChanged: (_) => setState(() {
                      _sectionsChanged = true;
                      _startTime = null;
                      _endTime = null;
                      _timeChanged = false;
                    }),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '结束节次'),
                    validator: (value) {
                      final numberError = _positiveNumber(value);
                      if (numberError != null) return numberError;
                      return int.parse(value!) < _number(_startSection)
                          ? '结束节次不能早于开始节次'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startWeek,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '开始周'),
                    validator: _positiveNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endWeek,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '结束周'),
                    validator: (value) {
                      final numberError = _positiveNumber(value);
                      if (numberError != null) return numberError;
                      return int.parse(value!) < _number(_startWeek)
                          ? '结束周不能早于开始周'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WeekPattern>(
              initialValue: _pattern,
              decoration: const InputDecoration(labelText: '周次规则'),
              items: const [
                DropdownMenuItem(
                  value: WeekPattern.everyWeek,
                  child: Text('每周'),
                ),
                DropdownMenuItem(
                  value: WeekPattern.oddWeeks,
                  child: Text('单周'),
                ),
                DropdownMenuItem(
                  value: WeekPattern.evenWeeks,
                  child: Text('双周'),
                ),
              ],
              onChanged: (value) => setState(() => _pattern = value!),
            ),
          ],
        ),
      ),
    );
  }
}
