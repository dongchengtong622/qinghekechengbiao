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
  static const _headerAliases = <String, Set<String>>{
    '课程名称': {'课程名称', '课程名', '课程'},
    '教师': {'教师', '教师姓名', '任课教师', '老师'},
    '星期': {'星期', '星期几', '周几', '上课星期'},
    '开始节次': {'开始节次', '起始节次', '起始节'},
    '结束节次': {'结束节次', '终止节次', '结束节'},
    '节次': {'节次', '上课节次', '上课节数'},
    '开始周': {'开始周', '起始周'},
    '结束周': {'结束周', '终止周'},
    '周次': {'周次', '上课周次', '教学周'},
    '单双周': {'单双周', '周类型', '周模式'},
    '教室': {'教室', '上课地点', '地点'},
    '开始时间': {'开始时间', '上课时间'},
    '结束时间': {'结束时间', '下课时间'},
  };
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
      List<List<Object?>>? selectedRows;
      var selectedScore = 0;
      for (final sheet in workbook.tables.values) {
        final rows = sheet.rows
            .map(
              (row) => row
                  .map((cell) => _cellValue(cell?.value))
                  .toList(growable: false),
            )
            .toList(growable: false);
        final score = _sheetScore(rows);
        if (score > selectedScore) {
          selectedScore = score;
          selectedRows = rows;
        }
      }
      if (selectedRows == null) {
        throw const ExcelImportException(
          'Excel 中没有找到同时包含课程和星期表头的课表工作表。',
        );
      }
      return parseRows(selectedRows);
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

    final headerIndex = rows.indexWhere(_isTimetableHeader);
    if (headerIndex < 0) {
      throw const ExcelImportException('Excel 中没有找到课程与星期表头。');
    }
    final headers = _resolveHeaders(rows[headerIndex]);
    final missing = <String>[
      if (!headers.containsKey('课程名称')) '课程名称',
      if (!headers.containsKey('星期')) '星期',
      if (!(headers.containsKey('开始节次') &&
              headers.containsKey('结束节次')) &&
          !headers.containsKey('节次'))
        '开始节次/结束节次或上课节次',
      if (!(headers.containsKey('开始周') && headers.containsKey('结束周')) &&
          !headers.containsKey('周次'))
        '开始周/结束周或上课周次',
    ];
    if (missing.isNotEmpty) {
      throw ExcelImportException('Excel 缺少必要列：${missing.join('、')}。');
    }

    final semesterId =
        'excel-${semesterMatch.group(1)}-${semesterMatch.group(2)}-'
        '${semesterMatch.group(3)}';
    final grouped = <String, _CourseBuilder>{};
    final warnings = <String>[];
    var largestEndWeek = 0;
    for (var rowIndex = headerIndex + 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final name = _field(row, headers, '课程名称');
      if (name.isEmpty) continue;
      try {
        final teacher = _field(row, headers, '教师');
        final weekday = _weekday(_field(row, headers, '星期'));
        final sections = _sections(row, headers);
        final weeks = _weeks(row, headers);
        if (weekday == null || sections == null || weeks == null) {
          throw const _RowImportException('星期、节次或周次格式不正确。');
        }
        final startMinute = _time(_fieldValue(row, headers, '开始时间'));
        final endMinute = _time(_fieldValue(row, headers, '结束时间'));
        if ((startMinute == null) != (endMinute == null) ||
            (startMinute != null && endMinute! <= startMinute)) {
          throw const _RowImportException('开始时间和结束时间格式不正确。');
        }
        final pattern = _pattern(
          '${_field(row, headers, '单双周')} ${_field(row, headers, '周次')}',
        );
        final key = '$name\u0000$teacher';
        final builder = grouped.putIfAbsent(
          key,
          () => _CourseBuilder(name: name, teacher: teacher),
        );
        for (final weekRange in weeks) {
          largestEndWeek = weekRange.$2 > largestEndWeek
              ? weekRange.$2
              : largestEndWeek;
          builder.sessions.add(
            CourseSession(
              weekday: weekday,
              startSection: sections.$1,
              endSection: sections.$2,
              startWeek: weekRange.$1,
              endWeek: weekRange.$2,
              pattern: pattern,
              room: _field(row, headers, '教室'),
              startMinute: startMinute,
              endMinute: endMinute,
            ),
          );
        }
      } on _RowImportException catch (error) {
        warnings.add('第 ${rowIndex + 1} 行：课程“$name”${error.message}');
      }
    }
    if (grouped.isEmpty) {
      throw const ExcelImportException('Excel 中没有可导入的课程。');
    }
    final configuredWeeks = _integer(_metadataValue(rows, '总周数'));
    final totalWeeks = configuredWeeks ?? largestEndWeek;
    final courses =
        grouped.entries
            .map((entry) {
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
            })
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    return ImportPreview(
      semester: Semester(
        id: semesterId,
        name: semesterName,
        firstWeekStart: firstWeekStart,
        totalWeeks: totalWeeks,
      ),
      courses: courses,
      warnings: List.unmodifiable(warnings),
    );
  }

  int _sheetScore(List<List<Object?>> rows) {
    var score = 0;
    for (final row in rows) {
      final headers = _resolveHeaders(row);
      if (headers.containsKey('课程名称') && headers.containsKey('星期')) {
        score = 100 + headers.length;
        break;
      }
    }
    if (score == 0) return 0;
    if (_metadataValue(rows, '学期') != null) score += 10;
    if (_metadataValue(rows, '第一周日期') != null) score += 10;
    return score;
  }

  bool _isTimetableHeader(List<Object?> row) {
    final headers = _resolveHeaders(row);
    return headers.containsKey('课程名称') && headers.containsKey('星期');
  }

  Map<String, int> _resolveHeaders(List<Object?> row) {
    final headers = <String, int>{};
    for (var index = 0; index < row.length; index++) {
      final normalized = _normalizeHeader(_text(row[index]));
      if (normalized.isEmpty) continue;
      for (final entry in _headerAliases.entries) {
        if (entry.value.any((alias) => _normalizeHeader(alias) == normalized)) {
          headers.putIfAbsent(entry.key, () => index);
          break;
        }
      }
    }
    return headers;
  }

  String _normalizeHeader(String value) => value
      .trim()
      .replaceAll(RegExp(r'[\s:：()（）]'), '')
      .toLowerCase();

  (int, int)? _sections(List<Object?> row, Map<String, int> headers) {
    final start = _integer(_fieldValue(row, headers, '开始节次'));
    final end = _integer(_fieldValue(row, headers, '结束节次'));
    if (start != null || end != null) {
      if (start == null || end == null || start < 1 || end < start) return null;
      return (start, end);
    }
    final value = _field(
      row,
      headers,
      '节次',
    ).replaceAll(RegExp(r'[第节\s]'), '');
    final match = RegExp(r'^(\d+)(?:[-–—~至](\d+))?$').firstMatch(value);
    if (match == null) return null;
    final parsedStart = int.parse(match.group(1)!);
    final parsedEnd = int.parse(match.group(2) ?? match.group(1)!);
    return parsedStart > 0 && parsedEnd >= parsedStart
        ? (parsedStart, parsedEnd)
        : null;
  }

  List<(int, int)>? _weeks(
    List<Object?> row,
    Map<String, int> headers,
  ) {
    final start = _integer(_fieldValue(row, headers, '开始周'));
    final end = _integer(_fieldValue(row, headers, '结束周'));
    if (start != null || end != null) {
      if (start == null || end == null || start < 1 || end < start) return null;
      return [(start, end)];
    }
    var value = _field(row, headers, '周次');
    value = value
        .replaceAll(RegExp(r'[第周\s()（）]'), '')
        .replaceAll(RegExp(r'[单双每]'), '');
    if (value.isEmpty) return null;
    if (RegExp(r'[,，、]').hasMatch(value)) {
      final weeks = value
          .split(RegExp(r'[,，、]'))
          .map(int.tryParse)
          .toList(growable: false);
      if (weeks.any((week) => week == null || week < 1)) return null;
      return weeks.map((week) => (week!, week)).toList(growable: false);
    }
    final match = RegExp(r'^(\d+)(?:[-–—~至](\d+))?$').firstMatch(value);
    if (match == null) return null;
    final parsedStart = int.parse(match.group(1)!);
    final parsedEnd = int.parse(match.group(2) ?? match.group(1)!);
    return parsedStart > 0 && parsedEnd >= parsedStart
        ? [(parsedStart, parsedEnd)]
        : null;
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

  String _field(List<Object?> row, Map<String, int> headers, String name) =>
      _text(_fieldValue(row, headers, name)).trim();

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
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(_text(value).trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  int? _weekday(String value) =>
      switch (value.replaceFirst(RegExp(r'^(星期|周)'), '')) {
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

class _RowImportException implements Exception {
  const _RowImportException(this.message);

  final String message;
}
