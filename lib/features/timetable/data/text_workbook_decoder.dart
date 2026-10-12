import 'dart:convert';
import 'dart:typed_data';
import 'package:enough_convert/enough_convert.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// Reads text-based exports that Excel can open despite an .xls suffix.
/// Rebuilds cell values and merges; never evaluates formulas or embedded scripts.
class WorkbookReadException extends FormatException {
  const WorkbookReadException(super.message);
}

class TextWorkbookDecoder {
  static String decodeText(List<int> bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255) ||
            (bytes[0] == 60 && bytes[1] == 0) ||
            (bytes[0] == 0 && bytes[1] == 60))) {
      final little = bytes[0] == 255 || bytes[0] == 60;
      final start = bytes[0] == 255 || bytes[0] == 254 ? 2 : 0;
      if ((bytes.length - start).isOdd) {
        throw const WorkbookReadException('UTF-16 文件内容不完整');
      }
      return String.fromCharCodes([
        for (var i = start; i < bytes.length; i += 2)
          little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      ]);
    }
    final head = latin1.decode(bytes.take(1024).toList());
    final charset = RegExp(
      r'''(?:charset\s*=\s*["']?|encoding\s*=\s*["'])([\w-]+)''',
      caseSensitive: false,
    ).firstMatch(head)?.group(1)?.toLowerCase();
    if (charset != null &&
        [
          'gbk',
          'gb2312',
          'gb-2312',
          'cp936',
          'windows-936',
          'gb18030',
        ].contains(charset)) {
      // GBK covers GB2312; four-byte GB18030 characters are not silently replaced.
      return const GbkCodec().decode(bytes);
    }
    if (charset == 'big5' || charset == 'big-5') {
      return const Big5Codec().decode(bytes);
    }
    try {
      return utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
    } on FormatException {
      return const GbkCodec().decode(bytes);
    }
  }

  static Excel? tryDecode(Uint8List bytes) {
    if (bytes.isEmpty) throw const WorkbookReadException('选择的文件为空，请重新下载后导入。');
    // Native workbooks are handled by the existing binary/ZIP parser.
    if (bytes[0] == 0x50 || bytes[0] == 0xD0) return null;
    final text = decodeText(bytes).trimLeft();
    if (RegExp(r'<(?:\w+:)?Workbook\b', caseSensitive: false).hasMatch(text) &&
        text.contains('urn:schemas-microsoft-com:office:spreadsheet')) {
      return _xml(text);
    }
    if (RegExp(r'<table\b', caseSensitive: false).hasMatch(text)) {
      return _html(text);
    }
    if (RegExp(
      r'^(?:<!doctype\s+html|<html\b)',
      caseSensitive: false,
    ).hasMatch(text)) {
      throw const WorkbookReadException('文件实际是网页，里面没有表格；请重新下载课表导出文件。');
    }
    return null;
  }

  static Excel _book(List<void Function(Excel)> writers) {
    if (writers.isEmpty) throw const WorkbookReadException('导出文件没有可读取的表格。');
    if (writers.length > 64) {
      throw const WorkbookReadException('工作表数量过多，请选择课表工作簿。');
    }
    final book = Excel.createExcel();
    for (final writer in writers) {
      writer(book);
    }
    if (book.tables.length > 1 && book.tables['Sheet1']?.maxRows == 0) {
      book.delete('Sheet1');
    }
    return book;
  }

  static String _sheetName(Excel book, String proposed) {
    var name = proposed.replaceAll(RegExp(r'[\\/\[\]:*?]'), '_').trim();
    if (name.isEmpty) name = '课表';
    if (name.length > 25) name = name.substring(0, 25);
    var candidate = name, count = 2;
    while (book.tables.containsKey(candidate) &&
        book.tables[candidate]!.maxRows > 0) {
      candidate = '$name ${count++}';
    }
    return candidate;
  }

  static void _put(
    Sheet sheet,
    Set<(int, int)> occupied,
    int row,
    int column,
    String value,
    int rows,
    int columns,
  ) {
    if (row < 0 ||
        column < 0 ||
        rows < 1 ||
        columns < 1 ||
        row + rows > 10000 ||
        column + columns > 256 ||
        rows * columns > 1000000 ||
        occupied.length + rows * columns > 1000000) {
      throw const WorkbookReadException('表格行列或合并范围过大，请选择课表文件。');
    }
    for (var r = row; r < row + rows; r++) {
      for (var c = column; c < column + columns; c++) {
        if (!occupied.add((r, c))) {
          throw const WorkbookReadException('表格包含重叠的合并单元格，无法安全读取课程位置。');
        }
      }
    }
    final start = CellIndex.indexByColumnRow(
      columnIndex: column,
      rowIndex: row,
    );
    sheet.cell(start).value = TextCellValue(value);
    if (rows > 1 || columns > 1) {
      sheet.merge(
        start,
        CellIndex.indexByColumnRow(
          columnIndex: column + columns - 1,
          rowIndex: row + rows - 1,
        ),
      );
    }
  }

  static String _htmlText(html.Node node) {
    if (node is html.Text) return node.text;
    if (node is html.Element && ['script', 'style'].contains(node.localName)) {
      return '';
    }
    if (node is html.Element && node.localName == 'br') return '\n';
    final content = node.nodes.map(_htmlText).join();
    if (node is html.Element &&
        ['p', 'div', 'li', 'tr', 'td', 'th'].contains(node.localName)) {
      return '$content\n';
    }
    return content;
  }

  static html.Element? _parentTable(html.Element element) {
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName == 'table') {
        return parent;
      }
      parent = parent.parent;
    }
    return null;
  }

  static Iterable<html.Element> _tableRows(html.Element table) =>
      table.querySelectorAll('tr').where((row) => _parentTable(row) == table);
  static Excel _html(String text) {
    final document = html_parser.parse(text);
    // Keep outer data coordinates. Only a single-column layout wrapper is
    // unwrapped; nested course detail tables remain part of the cell text.
    final tables = <html.Element>[];
    void collect(html.Element table) {
      final rows = _tableRows(table).toList();
      final nested = table
          .querySelectorAll('table')
          .where((child) => _parentTable(child) == table)
          .toList();
      final wrapper =
          nested.isNotEmpty &&
          rows.isNotEmpty &&
          rows.every(
            (row) =>
                row.children
                    .where((c) => c.localName == 'td' || c.localName == 'th')
                    .length <=
                1,
          );
      if (wrapper) {
        for (final child in nested) {
          collect(child);
        }
      } else {
        tables.add(table);
      }
    }

    for (final table
        in document
            .querySelectorAll('table')
            .where((t) => _parentTable(t) == null)) {
      collect(table);
    }
    return _book([
      for (var index = 0; index < tables.length; index++)
        (book) {
          final table = tables[index];
          final caption = table.querySelector('caption')?.text.trim();
          final sheet =
              book[_sheetName(
                book,
                caption?.isNotEmpty == true ? caption! : '课表 ${index + 1}',
              )];
          final occupied = <(int, int)>{};
          var row = 0;
          for (final tr in _tableRows(table)) {
            var column = 0;
            for (final cell in tr.children.where(
              (e) => e.localName == 'td' || e.localName == 'th',
            )) {
              while (occupied.contains((row, column))) {
                column++;
              }
              _put(
                sheet,
                occupied,
                row,
                column,
                _htmlText(cell).replaceAll('\u00a0', ' ').trim(),
                int.tryParse(cell.attributes['rowspan'] ?? '1') ?? 1,
                int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1,
              );
              column += (int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1);
            }
            row++;
          }
        },
    ]);
  }

  static String? _attribute(XmlElement e, String name) =>
      e.attributes.where((a) => a.name.local == name).firstOrNull?.value;
  static Iterable<XmlElement> _children(XmlElement e, String name) =>
      e.childElements.where((c) => c.name.local == name);
  static Excel _xml(String text) {
    final document = XmlDocument.parse(text);
    final worksheets = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Worksheet')
        .toList();
    return _book([
      for (var index = 0; index < worksheets.length; index++)
        (book) {
          final worksheet = worksheets[index];
          final sheet =
              book[_sheetName(
                book,
                _attribute(worksheet, 'Name') ?? '课表 ${index + 1}',
              )];
          final occupied = <(int, int)>{};
          var row = 0;
          for (final table in _children(worksheet, 'Table')) {
            for (final rowNode in _children(table, 'Row')) {
              row =
                  (int.tryParse(_attribute(rowNode, 'Index') ?? '') ??
                      row + 1) -
                  1;
              var column = 0;
              for (final cell in _children(rowNode, 'Cell')) {
                final explicit = int.tryParse(_attribute(cell, 'Index') ?? '');
                if (explicit != null) {
                  column = explicit - 1;
                } else {
                  while (occupied.contains((row, column))) {
                    column++;
                  }
                }
                final data = _children(cell, 'Data').firstOrNull;
                _put(
                  sheet,
                  occupied,
                  row,
                  column,
                  data?.innerText ?? '',
                  1 + (int.tryParse(_attribute(cell, 'MergeDown') ?? '0') ?? 0),
                  1 +
                      (int.tryParse(_attribute(cell, 'MergeAcross') ?? '0') ??
                          0),
                );
                column +=
                    1 +
                    (int.tryParse(_attribute(cell, 'MergeAcross') ?? '0') ?? 0);
              }
              row++;
            }
          }
        },
    ]);
  }
}
