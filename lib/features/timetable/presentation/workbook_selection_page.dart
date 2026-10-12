import 'package:flutter/material.dart';

import '../data/smart_timetable_importer.dart';
import '../data/timetable_import.dart';
import '../domain/models.dart';
import 'excel_manual_mapping_page.dart';

class WorkbookSelectionPage extends StatefulWidget {
  const WorkbookSelectionPage({
    super.key,
    required this.workbook,
    required this.semester,
  });

  final WorkbookImportPreview workbook;
  final Semester semester;

  @override
  State<WorkbookSelectionPage> createState() => _WorkbookSelectionPageState();
}

class _WorkbookSelectionPageState extends State<WorkbookSelectionPage> {
  final _selected = <int>{};
  final _manuallyParsed = <int, ImportPreview>{};

  Future<void> _mapSheet(int index) async {
    final sheet = widget.workbook.sheets[index];
    final preview = await Navigator.of(context).push<ImportPreview>(
      MaterialPageRoute(
        builder: (_) => ExcelManualMappingPage(
          mapping: ExcelMappingRequiredException([sheet.grid]),
          semester: widget.semester,
        ),
      ),
    );
    if (!mounted || preview == null) return;
    setState(() {
      _manuallyParsed[index] = preview;
      _selected.add(index);
    });
  }

  void _confirm() {
    try {
      final selected = [
        for (var index = 0; index < widget.workbook.sheets.length; index++)
          if (_selected.contains(index))
            SheetImportResult(
              name: widget.workbook.sheets[index].name,
              grid: widget.workbook.sheets[index].grid,
              preview:
                  _manuallyParsed[index] ??
                  widget.workbook.sheets[index].preview,
            ),
      ];
      final merged = const SmartTimetableImporter().mergeSelectedSheets(
        selected,
      );
      Navigator.of(context).pop(merged);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择工作表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('请选择要导入的工作表。合并时会跳过完全重复的课程，并在预览中提示时间冲突。'),
          const SizedBox(height: 12),
          for (var index = 0; index < widget.workbook.sheets.length; index++)
            _sheetCard(index),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _selected.isEmpty ? null : _confirm,
          child: const Text('导入所选工作表'),
        ),
      ),
    );
  }

  Widget _sheetCard(int index) {
    final sheet = widget.workbook.sheets[index];
    final preview = _manuallyParsed[index] ?? sheet.preview;
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            title: Text(sheet.name),
            subtitle: Text(
              preview == null
                  ? sheet.error ?? '尚未识别出课程'
                  : '${preview.courses.length} 门课程 · '
                        '${preview.warnings.length} 条警告 · '
                        '${sheet.duplicateCount} 条重复 · '
                        '${sheet.conflictCount} 条冲突',
            ),
            value: _selected.contains(index),
            onChanged: preview == null
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(index);
                    } else {
                      _selected.remove(index);
                    }
                  }),
          ),
          if (preview == null && sheet.grid.cells.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _mapSheet(index),
                child: const Text('手动定位'),
              ),
            ),
        ],
      ),
    );
  }
}
