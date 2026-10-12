import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/school_schedule.dart';

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
    this.loadScheduleSections,
    this.loadSchedule,
    this.loadUnsharedTimes,
    this.onBackup,
    this.semesterConfigured = true,
    this.onConfigureSemester,
  });

  final bool semesterConfigured;
  final Future<bool> Function()? onConfigureSemester;
  final LoadImportPreview loadPreview;
  final Future<SchoolSchedule> Function()? loadSchedule;
  final Future<List<SectionRangeTime>> Function(String semesterId)?
  loadUnsharedTimes;
  final Future<int> Function()? loadScheduleSections;
  final VoidCallback? onBackup;
  final PreviewTimetableImport onPreview;
  final ConfirmTimetableImport onImport;

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  bool _loading = false;
  late bool _configured = widget.semesterConfigured;

  Future<void> _selectFile() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final preview = await widget.loadPreview();
      if (preview == null || !mounted) return;
      final changes = await widget.onPreview(preview);
      final sections = await widget.loadScheduleSections?.call() ?? 12;
      final schedule = await widget.loadSchedule?.call();
      final existingTimes =
          await widget.loadUnsharedTimes?.call(preview.semester.id) ??
          <SectionRangeTime>[];
      if (!mounted) return;
      final result = await Navigator.of(context).push<ImportSummary>(
        MaterialPageRoute(
          builder: (_) => ImportPreviewPage(
            preview: preview,
            schedule: schedule,
            existingTimes: existingTimes,
            maxScheduleSection: sections,
            changes: changes,
            onConfirm: widget.onImport,
            onPreview: widget.onPreview,
          ),
        ),
      );
      if (result != null && mounted) Navigator.of(context).pop(result);
    } on ExcelImportException catch (error) {
      _showError(error.message);
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('读取 Excel 失败，请确认是 .xls 或 .xlsx 文件后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _template() async {
    try {
      final data = await rootBundle.load(
        'assets/templates/qinghe_timetable_template.xlsx',
      );
      final saved = await FilePicker.saveFile(
        fileName: '青禾课表导入模板.xlsx',
        bytes: data.buffer.asUint8List(),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (saved != null) _showError('模板已保存，可填写课程后重新导入。');
    } catch (_) {
      _showError('模板保存失败，请选择其他保存位置。');
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
      appBar: AppBar(title: const Text('导入课表')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 112),
        child: ListView(
          children: [
            Icon(
              Icons.table_view_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              '选择导入方式',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              '支持 .xlsx 和 Excel 97–2003 .xls。导入后可修改课程、教师、教室、节次和周次，确认后才保存。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading || !_configured ? null : () => _selectFile(),
              icon: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_rounded),
              label: Text(_loading ? '正在读取…' : '选择 Excel 文件'),
            ),
            TextButton.icon(
              onPressed: _loading ? null : _template,
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载 Excel 模板'),
            ),
            const Text(
              '普通课表可直接导入；格式识别困难时，可使用模板整理。',
              textAlign: TextAlign.center,
            ),
            if (!_configured)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('请先设置学期和第一周星期一，再选择Excel文件。'),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () async {
                                final ok = await widget.onConfigureSemester
                                    ?.call();
                                if (mounted && ok == true) {
                                  setState(() => _configured = true);
                                }
                              },
                        child: const Text('设置学期'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
