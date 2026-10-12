import 'package:flutter/material.dart';
import '../domain/school_schedule.dart';

class SchedulePreviewPage extends StatefulWidget {
  const SchedulePreviewPage({
    super.key,
    required this.schedule,
    required this.onSave,
  });
  final SchoolSchedule schedule;
  final Future<void> Function(SchoolSchedule) onSave;
  @override
  State<SchedulePreviewPage> createState() => _SchedulePreviewPageState();
}

class _SchedulePreviewPageState extends State<SchedulePreviewPage> {
  final _form = GlobalKey<FormState>();
  final _starts = <TextEditingController>[], _ends = <TextEditingController>[];
  bool _saving = false;
  String? _error;
  String _time(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    for (final s in widget.schedule.sections) {
      _starts.add(TextEditingController(text: _time(s.startMinute)));
      _ends.add(TextEditingController(text: _time(s.endMinute)));
    }
  }

  @override
  void dispose() {
    for (final c in [..._starts, ..._ends]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _minute(String text) {
    final m = RegExp(r'^(\d{1,2})[:：](\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    final h = int.parse(m[1]!), n = int.parse(m[2]!);
    return h < 24 && n < 60 ? h * 60 + n : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final schedule = SchoolSchedule(
        id: 'custom',
        sections: [
          for (var i = 0; i < _starts.length; i++)
            SectionTime(
              i + 1,
              _minute(_starts[i].text)!,
              _minute(_ends[i].text)!,
            ),
        ],
        prepPeriods: widget.schedule.prepPeriods,
      );
      await widget.onSave(schedule);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException ? e.message : '保存失败，请重试。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('核对作息时间')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('核对并修正每节课的开始与结束时间。应用后，已有按节次安排的课程和未来提醒会一起更新。'),
          const SizedBox(height: 16),
          for (var i = 0; i < _starts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(width: 52, child: Text('第${i + 1}节')),
                  Expanded(
                    child: TextFormField(
                      key: Key('section_start_${i + 1}'),
                      controller: _starts[i],
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: '开始'),
                      keyboardType: TextInputType.datetime,
                      validator: (v) =>
                          _minute(v ?? '') == null ? '如 08:25' : null,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.all(8), child: Text('—')),
                  Expanded(
                    child: TextFormField(
                      key: Key('section_end_${i + 1}'),
                      controller: _ends[i],
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: '结束'),
                      keyboardType: TextInputType.datetime,
                      validator: (v) =>
                          _minute(v ?? '') == null ? '如 09:10' : null,
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _saving || _starts.length >= 30
                    ? null
                    : () => setState(() {
                        _starts.add(TextEditingController());
                        _ends.add(TextEditingController());
                      }),
                icon: const Icon(Icons.add),
                label: const Text('补充节次'),
              ),
              if (_starts.length > 1)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _starts.removeLast().dispose();
                          _ends.removeLast().dispose();
                        }),
                  child: const Text('删除末节'),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在应用…' : '应用作息时间'),
          ),
        ],
      ),
    ),
  );
}
