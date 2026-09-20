import 'package:flutter/material.dart';

import '../data/course_repository.dart';
import '../data/excel_timetable_importer.dart';
import '../data/timetable_import.dart';
import 'import_preview_page.dart';

typedef LoadImportPreview = Future<ImportPreview?> Function();
typedef PreviewTimetableImport =
    Future<ImportSummary> Function(ImportPreview preview);

class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({
    super.key,
    required this.loadPreview,
    required this.onPreview,
    required this.onImport,
  });

  final LoadImportPreview loadPreview;
  final PreviewTimetableImport onPreview;
  final ConfirmTimetableImport onImport;

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  bool _loading = false;

  Future<void> _selectFile() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final preview = await widget.loadPreview();
      if (preview == null || !mounted) return;
      final changes = await widget.onPreview(preview);
      if (!mounted) return;
      final result = await Navigator.of(context).push<ImportSummary>(
        MaterialPageRoute(
          builder: (_) => ImportPreviewPage(
            preview: preview,
            changes: changes,
            onConfirm: widget.onImport,
          ),
        ),
      );
      if (result != null && mounted) Navigator.of(context).pop(result);
    } on ExcelImportException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('读取 Excel 失败，请换一个文件后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excel 导入课表')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.table_view_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              '从 Excel 导入',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              '选择一个 .xlsx 文件。文件需要包含学期、第一周日期以及课程名称、星期、节次和周次等列；开始时间和结束时间可选填。',
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _loading ? null : _selectFile,
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_rounded),
              label: Text(_loading ? '正在读取…' : '选择 Excel 文件'),
            ),
          ],
        ),
      ),
    );
  }
}
