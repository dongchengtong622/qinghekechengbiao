import 'package:flutter/material.dart';

import '../data/cdcas_kingo_importer.dart';
import '../data/course_repository.dart';
import '../domain/models.dart';

typedef ConfirmTimetableImport =
    Future<ImportSummary> Function(ImportPreview preview);

class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({
    super.key,
    required this.preview,
    required this.changes,
    required this.onConfirm,
  });

  final ImportPreview preview;
  final ImportSummary changes;
  final ConfirmTimetableImport onConfirm;

  @override
  State<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends State<ImportPreviewPage> {
  bool _importing = false;

  Future<void> _confirm() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final summary = await widget.onConfirm(widget.preview);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(summary);
      } else {
        setState(() => _importing = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final sessionCount = preview.courses.fold<int>(
      0,
      (total, course) => total + course.sessions.length,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('确认导入')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            preview.semester.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${preview.courses.length} 门课程 · $sessionCount 个上课时段',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '将新增 ${widget.changes.inserted} · 更新 ${widget.changes.updated} · '
            '移除 ${widget.changes.removed}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (preview.warnings.isNotEmpty) ...[
            const SizedBox(height: 18),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('识别提示'),
                    const SizedBox(height: 6),
                    for (final warning in preview.warnings) Text(warning),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          for (final course in preview.courses)
            Card(
              child: ListTile(
                title: Text(course.name),
                subtitle: Text(
                  '${course.teacher.isEmpty ? '教师待确认' : course.teacher}\n'
                  '${course.sessions.map(_sessionDescription).join('\n')}',
                ),
                isThreeLine: course.sessions.length > 1,
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _importing ? null : _confirm,
            icon: _importing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done_rounded),
            label: Text(_importing ? '正在导入…' : '导入课表'),
          ),
        ],
      ),
    );
  }

  String _sessionDescription(CourseSession session) {
    final weekday = '一二三四五六日'[session.weekday - 1];
    final room = session.room.isEmpty ? '教室待确认' : session.room;
    return '周$weekday 第${session.startSection}-${session.endSection}节 · '
        '${session.startWeek}-${session.endWeek}周 · $room';
  }
}
