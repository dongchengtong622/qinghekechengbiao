import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../domain/models.dart';
import 'timetable_import.dart';

class ExcelImportException implements Exception {
  const ExcelImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExcelTimetableImporter {
  const ExcelTimetableImporter();

  static final _semesterPattern = RegExp(
    r'(\d{4})\s*[-–—]\s*(\d{4})\s*学年\s*第?\s*([12])\s*学期',
  );
  static const _colors = <int>[
    0xFF2E7D66,
    0xFF6366A8,
    0xFFD77855,
    0xFF9A6BB5,
    0xFF3978A8,
    0xFFB46A7A,
  ];

  ImportPreview parseBytes(Uint8List bytes) {
    try {
      final workbook = Excel.decodeBytes(bytes);
      for (final sheet in workbook.tables.values) {
        if (sheet.rows.any((row) => row.any((cell) => cell?.value != null))) {
          return parseRows(
            sheet.rows
                .map(
                  (row) => row
                      .map((cell) => _cellValue(cell?.value))
                      .toList(growable: false),
                )
                .toList(growable: false),
          );
        }
      }
      throw const ExcelImportException('Excel 文件中没有可读取的课表数据。');
    } on ExcelImportException {
      rethrow;
    } catch (_) {
      throw const ExcelImportException('无法读取该 Excel 文件，请确认文件为 .xlsx 格式。');
    }
  }

  ImportPreview parseRows(List<List<Object?>> rows) {
    final semesterName = _metadata(rows, '学期');
    final firstWeekValue = _metadataValue(rows, '第一周日期');
    if (semesterName == null || semesterName.isEmpty) {
      throw const ExcelImportException('Excel 中缺少“学期”信息。');
    }
    final semesterMatch = _semesterPattern.firstMatch(semesterName);
    if (semesterMatch == null) {
      throw const ExcelImportException('“学期”格式应为：2026-2027学年第1学期。');
    }
    final firstWeekStart = _date(firstWeekValue);
    if (firstWeekStart == null) {
      throw const ExcelImportException('Excel 中缺少有效的“第一周日期”，格式应为 2026-09-07。');
    }

    final headerIndex = rows.indexWhere(
      (row) => row.any((value) => _text(value) == '课程名称'),
    );
    if (headerIndex < 0) {
      throw const ExcelImportException('Excel 中没有找到“课程名称”表头。');
    }
    final headers = <String, int>{};
    for (var index = 0; index < rows[headerIndex].length; index++) {
      final header = _text(rows[headerIndex][index]);
      if (header.isNotEmpty) headers[header] = index;
    }
    const required = [
      '课程名称',
      '星期',
      '开始节次',
      '结束节次',
      '开始周',
      '结束周',
    ];
    final missing = required.where((header) => !headers.containsKey(header));
    if (missing.isNotEmpty) {
      throw ExcelImportException('Excel 缺少必要列：${missing.join('、')}。');
    }

    final semesterId =
        'excel-${semesterMatch.group(1)}-${semesterMatch.group(2)}-'
        '${semesterMatch.group(3)}';
    final grouped = <String, _CourseBuilder>{};
    var largestEndWeek = 0;
    for (final row in rows.skip(headerIndex + 1)) {
      final name = _field(row, headers, '课程名称');
      if (name.isEmpty) continue;
      final teacher = _field(row, headers, '教师');
      final weekday = _weekday(_field(row, headers, '星期'));
      final startSection = _integer(_fieldValue(row, headers, '开始节次'));
      final endSection = _integer(_fieldValue(row, headers, '结束节次'));
      final startWeek = _integer(_fieldValue(row, headers, '开始周'));
      final endWeek = _integer(_fieldValue(row, headers, '结束周'));
      if (weekday == null ||
          startSection == null ||
          endSection == null ||
          startWeek == null ||
          endWeek == null ||
          endSection < startSection ||
          endWeek < startWeek) {
        throw ExcelImportException('课程“$name”的星期、节次或周次格式不正确。');
      }
      final startMinute = _time(_fieldValue(row, headers, '开始时间'));
      final endMinute = _time(_fieldValue(row, headers, '结束时间'));
      if ((startMinute == null) != (endMinute == null) ||
          (startMinute != null && endMinute! <= startMinute)) {
        throw ExcelImportException('课程“$name”的开始时间和结束时间不正确。');
      }
      largestEndWeek = endWeek > largestEndWeek ? endWeek : largestEndWeek;
      final key = '$name\u0000$teacher';
      final builder = grouped.putIfAbsent(
        key,
        () => _CourseBuilder(name: name, teacher: teacher),
      );
      builder.sessions.add(
        CourseSession(
          weekday: weekday,
          startSection: startSection,
          endSection: endSection,
          startWeek: startWeek,
          endWeek: endWeek,
          pattern: _pattern(_field(row, headers, '单双周')),
          room: _field(row, headers, '教室'),
          startMinute: startMinute,
          endMinute: endMinute,
        ),
      );
    }
    if (grouped.isEmpty) {
      throw const ExcelImportException('Excel 中没有可导入的课程。');
    }
    final configuredWeeks = _integer(_metadataValue(rows, '总周数'));
    final totalWeeks = configuredWeeks ?? largestEndWeek;
    final courses = grouped.entries.map((entry) {
      final externalId = _stableId(entry.key);
      return Course(
        id: 'excel-$externalId-$semesterId',
        semesterId: semesterId,
        source: CourseSource.cdcasKingo,
        externalId: externalId,
        name: entry.value.name,
        teacher: entry.value.teacher,
        colorValue: _colors[_positiveHash(entry.key) % _colors.length],
        sessions: List.unmodifiable(entry.value.sessions),
      );
    }).toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));
    return ImportPreview(
      semester: Semester(
        id: semesterId,
        name: semesterName,
        firstWeekStart: firstWeekStart,
        totalWeeks: totalWeeks,
      ),
      courses: courses,
    );
  }

  Object? _cellValue(CellValue? value) => switch (value) {
    null => null,
    TextCellValue() => value.value,
    IntCellValue() => value.value,
    DoubleCellValue() => value.value,
    BoolCellValue() => value.value,
    DateCellValue() => value.asDateTimeLocal(),
    DateTimeCellValue() => value.asDateTimeLocal(),
    TimeCellValue() => value.asDuration(),
    FormulaCellValue() => value.formula,
  };

  String? _metadata(List<List<Object?>> rows, String key) =>
      _text(_metadataValue(rows, key)).trim().isEmpty
      ? null
      : _text(_metadataValue(rows, key)).trim();

  Object? _metadataValue(List<List<Object?>> rows, String key) {
    for (final row in rows) {
      if (row.isNotEmpty && _text(row.first).trim() == key) {
        return row.length > 1 ? row[1] : null;
      }
    }
    return null;
  }

  Object? _fieldValue(
    List<Object?> row,
    Map<String, int> headers,
    String name,
  ) {
    final index = headers[name];
    return index == null || index >= row.length ? null : row[index];
  }

  String _field(
    List<Object?> row,
    Map<String, int> headers,
    String name,
  ) => _text(_fieldValue(row, headers, name)).trim();

  String _text(Object? value) => value?.toString() ?? '';

  int? _integer(Object? value) => switch (value) {
    int() => value,
    double() => value.round(),
    _ => int.tryParse(_text(value).trim()),
  };

  DateTime? _date(Object? value) {
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    return DateTime.tryParse(_text(value).trim());
  }

  int? _time(Object? value) {
    if (value == null || _text(value).trim().isEmpty) return null;
    if (value is Duration) return value.inMinutes;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_text(value).trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  int? _weekday(String value) => switch (
    value.replaceFirst(RegExp(r'^(星期|周)'), ''),
  ) {
    '一' || '1' => DateTime.monday,
    '二' || '2' => DateTime.tuesday,
    '三' || '3' => DateTime.wednesday,
    '四' || '4' => DateTime.thursday,
    '五' || '5' => DateTime.friday,
    '六' || '6' => DateTime.saturday,
    '日' || '天' || '7' => DateTime.sunday,
    _ => null,
  };

  WeekPattern _pattern(String value) {
    if (value.contains('单')) return WeekPattern.oddWeeks;
    if (value.contains('双')) return WeekPattern.evenWeeks;
    return WeekPattern.everyWeek;
  }

  String _stableId(String value) => _positiveHash(value).toRadixString(16);

  int _positiveHash(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}

class _CourseBuilder {
  _CourseBuilder({required this.name, required this.teacher});

  final String name;
  final String teacher;
  final sessions = <CourseSession>[];
}
