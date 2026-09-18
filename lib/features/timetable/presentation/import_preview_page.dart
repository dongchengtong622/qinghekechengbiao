import 'package:flutter/material.dart';

import '../data/cdcas_kingo_importer.dart';
import '../data/course_repository.dart';

typedef ConfirmTimetableImport = Future<ImportSummary> Function(
  ImportPreview preview,
);

class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({
    super.key,
    required this.preview,
    required this.onConfirm,
  });

  final ImportPreview preview;
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
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$error')),
      );
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${preview.courses.length} 门课程 · $sessionCount 个上课时段',
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
                  '${course.teacher.isEmpty ? '教师待确认' : course.teacher} · '
                  '${course.sessions.length} 个时段',
                ),
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
}
