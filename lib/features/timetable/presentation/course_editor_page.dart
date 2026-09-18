import 'package:flutter/material.dart';

import '../data/sample_schedule.dart';
import '../domain/models.dart';

class CourseEditorPage extends StatefulWidget {
  const CourseEditorPage({super.key, this.initialCourse, required this.onSave});

  final Course? initialCourse;
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
  bool _saving = false;

  CourseSession? get _initialSession =>
      widget.initialCourse?.sessions.isNotEmpty == true
      ? widget.initialCourse!.sessions.first
      : null;

  @override
  void initState() {
    super.initState();
    final course = widget.initialCourse;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final course = Course(
      id:
          widget.initialCourse?.id ??
          'course-${DateTime.now().microsecondsSinceEpoch}',
      semesterId: widget.initialCourse?.semesterId ?? sampleSemester.id,
      source: widget.initialCourse?.source ?? CourseSource.manual,
      externalId: widget.initialCourse?.externalId,
      name: _name.text.trim(),
      teacher: _teacher.text.trim(),
      colorValue: widget.initialCourse?.colorValue ?? 0xFF2E7D66,
      sessions: [
        CourseSession(
          weekday: _weekday,
          startSection: _number(_startSection),
          endSection: _number(_endSection),
          startWeek: _number(_startWeek),
          endWeek: _number(_endWeek),
          pattern: _pattern,
          room: _room.text.trim(),
        ),
      ],
    );
    try {
      await widget.onSave(course);
      if (mounted) await Navigator.of(context).maybePop();
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
                  child: TextFormField(
                    key: const Key('start_section'),
                    controller: _startSection,
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
