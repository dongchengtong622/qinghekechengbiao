import 'package:flutter/material.dart';

import '../data/smart_timetable_importer.dart';
import '../data/timetable_import.dart';
import '../domain/models.dart';

class ExcelManualMappingPage extends StatefulWidget {
  const ExcelManualMappingPage({
    super.key,
    required this.mapping,
    required this.semester,
  });

  final ExcelMappingRequiredException mapping;
  final Semester semester;

  @override
  State<ExcelManualMappingPage> createState() => _ExcelManualMappingPageState();
}

class _ExcelManualMappingPageState extends State<ExcelManualMappingPage> {
  int _sheetIndex = 0;
  int _headerRow = 0;
  int _periodColumn = 0;

  ExcelSheetGrid get _sheet => widget.mapping.sheets[_sheetIndex];

  String _rowSummary(int row) => _sheet.cells
      .where((cell) => cell.row == row)
      .take(5)
      .map((cell) => cell.text.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((text) => text.isNotEmpty)
      .join(' · ');

  String _columnName(int col) {
    var value = col + 1;
    var name = '';
    while (value > 0) {
      value--;
      name = '${String.fromCharCode(65 + value % 26)}$name';
      value ~/= 26;
    }
    return name;
  }

  void _confirm() {
    try {
      final preview = const SmartTimetableImporter().parseGrid(
        _sheet.cells,
        widget.semester,
        headerRow: _headerRow,
        periodColumn: _periodColumn,
      );
      Navigator.of(context).pop<ImportPreview>(preview);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sheet.rowCount.clamp(1, 100);
    final columns = _sheet.columnCount.clamp(1, 52);
    return Scaffold(
      appBar: AppBar(title: const Text('Excel 手动定位')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('自动识别未找到完整课表。请按下方表格预览选择星期表头所在行和节次所在列。识别结果仍需在下一页逐门核对。'),
          const SizedBox(height: 16),
          if (widget.mapping.sheets.length > 1)
            DropdownButtonFormField<int>(
              initialValue: _sheetIndex,
              decoration: const InputDecoration(labelText: '工作表'),
              items: [
                for (var i = 0; i < widget.mapping.sheets.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(widget.mapping.sheets[i].name),
                  ),
              ],
              onChanged: (value) => setState(() {
                _sheetIndex = value ?? 0;
                _headerRow = 0;
                _periodColumn = 0;
              }),
            ),
          KeyedSubtree(
            key: ValueKey('weekday_sheet_$_sheetIndex'),
            child: DropdownButtonFormField<int>(
              key: const Key('excel_weekday_row'),
              initialValue: _headerRow.clamp(0, rows - 1),
              decoration: const InputDecoration(labelText: '星期表头所在行'),
              isExpanded: true,
              items: [
                for (var i = 0; i < rows; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '第 ${i + 1} 行 · ${_rowSummary(i)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _headerRow = value ?? 0),
            ),
          ),
          KeyedSubtree(
            key: ValueKey('period_sheet_$_sheetIndex'),
            child: DropdownButtonFormField<int>(
              key: const Key('excel_period_column'),
              initialValue: _periodColumn.clamp(0, columns - 1),
              decoration: const InputDecoration(labelText: '节次所在列'),
              items: [
                for (var i = 0; i < columns; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text('${_columnName(i)} 列'),
                  ),
              ],
              onChanged: (value) => setState(() => _periodColumn = value ?? 0),
            ),
          ),
          const SizedBox(height: 16),
          const Text('表格内容预览'),
          for (var row = 0; row < _sheet.rowCount && row < 20; row++)
            ListTile(
              dense: true,
              selected: row == _headerRow,
              title: Text('第 ${row + 1} 行'),
              subtitle: Text(
                _rowSummary(row),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => setState(() => _headerRow = row),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _confirm, child: const Text('重新识别')),
        ],
      ),
    );
  }
}
