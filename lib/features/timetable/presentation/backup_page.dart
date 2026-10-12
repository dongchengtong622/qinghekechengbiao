import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/backup/timetable_backup_service.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.service,
    required this.onRestored,
  });

  final TimetableBackupService service;
  final Future<void> Function() onRestored;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final source = await widget.service.exportJson();
      final path = await FilePicker.saveFile(
        fileName: '青禾课表备份.json',
        bytes: Uint8List.fromList(utf8.encode(source)),
        mimeType: 'application/json',
      );
      if (path != null) _message('备份已保存，请妥善保管文件。');
    } catch (_) {
      _message('备份保存失败，请重试或选择其他位置。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final source = utf8.decode(await file.readAsBytes());
      final preview = widget.service.previewRestore(source);
      final diff = await widget.service.compare(preview.backup);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认恢复备份'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前 ${diff.currentCourseCount} 门课程；备份包含 ${preview.courseCount} 门课程、${preview.semesterCount} 个学期。',
                ),
                const SizedBox(height: 8),
                Text(
                  '将新增 ${diff.added} 门、覆盖 ${diff.replaced} 门、移除 ${diff.removed} 门课程。',
                ),
                const SizedBox(height: 8),
                const Text('恢复将覆盖当前课表、学期、作息和提醒设置。'),
                for (final warning in preview.warnings) ...[
                  const SizedBox(height: 8),
                  Text(warning),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('覆盖并恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.service.restore(preview.backup);
      try {
        await widget.onRestored();
        _message('课表已恢复，提醒已重新安排。');
      } catch (_) {
        _message('课表已恢复，提醒重新安排失败，请到提醒设置检查。');
      }
    } on FormatException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('恢复失败，现有课表未更改。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('备份与恢复')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('备份保存在你选择的位置，包含课程、学期、作息和提醒设置。请妥善保管备份文件。'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.save_alt),
          label: const Text('导出 JSON 备份'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.restore),
          label: const Text('从 JSON 备份恢复'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    ),
  );
}
