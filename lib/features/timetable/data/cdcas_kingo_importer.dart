import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../domain/models.dart';

abstract interface class TimetableImporter {
  ImportPreview parse(String html);
}

class ImportPreview {
  const ImportPreview({
    required this.semester,
    required this.courses,
    this.warnings = const [],
  });

  final Semester semester;
  final List<Course> courses;
  final List<String> warnings;
}

enum TimetableImportErrorCode { notTimetablePage, emptyTimetable }

class TimetableImportException implements Exception {
  const TimetableImportException(this.code, this.message);

  final TimetableImportErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class CdcasKingoImporter implements TimetableImporter {
  const CdcasKingoImporter();

  static final _weekRange = RegExp(
    r'(?:第)?(\d{1,2})\s*[-–~]\s*(\d{1,2})\s*周?\s*(?:[（(]\s*([单双])\s*周?\s*[)）])?',
  );
  static final _sectionRange = RegExp(
    r'第?\s*(\d{1,2})\s*[-–~]\s*(\d{1,2})\s*节',
  );
  static final _semesterPattern = RegExp(
    r'(\d{4})\s*[-–—]\s*(\d{4})\s*学年\s*第?\s*([12])\s*学期',
  );
  static final _teacherPattern = RegExp(r'^[\u4e00-\u9fff]{2,6}(?:老师)?$');

  static const _colors = <int>[
    0xFF2E7D66,
    0xFF6366A8,
    0xFFD77855,
    0xFF9A6BB5,
    0xFF3978A8,
    0xFFB46A7A,
  ];

  @override
  ImportPreview parse(String html) {
    final document = html_parser.parse(html);
    final tableMatch = _findTimetable(document);
    if (tableMatch == null) {
      throw const TimetableImportException(
        TimetableImportErrorCode.notTimetablePage,
        '当前页面不是个人课表，请先登录并打开个人课表页面。',
      );
    }

    final parsed = <_ParsedSession>[];
    final warnings = <String>[];
    final rows = tableMatch.table.querySelectorAll('tr');
    for (
      var rowIndex = tableMatch.headerRow + 1;
      rowIndex < rows.length;
      rowIndex++
    ) {
      final cells = rows[rowIndex].querySelectorAll('td, th');
      if (cells.isEmpty) continue;
      final rowSections = _sectionsFrom(_cellLines(cells.first));
      var logicalColumn = 0;
      for (final cell in cells) {
        final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        final weekday = tableMatch.weekdays[logicalColumn];
        logicalColumn += span;
        if (weekday == null) continue;
        final session = _parseCell(cell, weekday, rowSections);
        if (session != null) {
          parsed.add(session);
        } else if (_cellLines(cell).isNotEmpty) {
          warnings.add('第 ${rowIndex + 1} 行存在无法识别的课程信息');
        }
      }
    }

    if (parsed.isEmpty) {
      throw const TimetableImportException(
        TimetableImportErrorCode.emptyTimetable,
        '已找到课表，但没有识别到可导入的课程。',
      );
    }

    final semester = _semester(document, tableMatch.table);
    final grouped = <String, List<_ParsedSession>>{};
    for (final item in parsed) {
      grouped
          .putIfAbsent('${item.name}\u0000${item.teacher}', () => [])
          .add(item);
    }

    final courses = <Course>[];
    for (final entry in grouped.entries) {
      final first = entry.value.first;
      final externalId = _stableId(entry.key);
      courses.add(
        Course(
          id: 'cdcas-$externalId',
          semesterId: semester.id,
          source: CourseSource.cdcasKingo,
          externalId: externalId,
          name: first.name,
          teacher: first.teacher,
          colorValue: _colors[_positiveHash(entry.key) % _colors.length],
          sessions: entry.value.map((item) => item.session).toList(),
        ),
      );
    }
    courses.sort((a, b) => a.name.compareTo(b.name));
    return ImportPreview(
      semester: semester,
      courses: courses,
      warnings: warnings,
    );
  }

  _TimetableMatch? _findTimetable(Document document) {
    for (final table in document.querySelectorAll('table')) {
      final rows = table.querySelectorAll('tr');
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final weekdays = <int, int>{};
        var logicalColumn = 0;
        for (final cell in rows[rowIndex].querySelectorAll('td, th')) {
          final weekday = _weekday(cell.text.trim());
          if (weekday != null) weekdays[logicalColumn] = weekday;
          logicalColumn += int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        }
        if (weekdays.length >= 5) {
          return _TimetableMatch(table, rowIndex, weekdays);
        }
      }
    }
    return null;
  }

  _ParsedSession? _parseCell(
    Element cell,
    int weekday,
    ({int start, int end})? rowSections,
  ) {
    final lines = _cellLines(cell);
    if (lines.length < 2) return null;
    final weekLine = lines.firstWhere(
      (line) => _weekRange.hasMatch(line),
      orElse: () => '',
    );
    final weekMatch = _weekRange.firstMatch(weekLine);
    if (weekMatch == null) return null;
    final sections = _sectionsFrom(lines) ?? rowSections;
    if (sections == null) return null;

    final name = lines.first;
    if (name.length > 80 || _weekRange.hasMatch(name)) return null;
    final details = lines
        .skip(1)
        .where(
          (line) => !_weekRange.hasMatch(line) && !_sectionRange.hasMatch(line),
        );
    var teacher = '';
    var room = '';
    for (final detail in details) {
      if (teacher.isEmpty &&
          (_teacherPattern.hasMatch(detail) || detail.endsWith('老师'))) {
        teacher = detail;
      } else if (room.isEmpty) {
        room = detail;
      }
    }

    final startWeek = int.parse(weekMatch.group(1)!);
    final endWeek = int.parse(weekMatch.group(2)!);
    final pattern = switch (weekMatch.group(3)) {
      '单' => WeekPattern.oddWeeks,
      '双' => WeekPattern.evenWeeks,
      _ => WeekPattern.everyWeek,
    };
    return _ParsedSession(
      name: name,
      teacher: teacher,
      session: CourseSession(
        weekday: weekday,
        startSection: sections.start,
        endSection: sections.end,
        startWeek: startWeek,
        endWeek: endWeek,
        pattern: pattern,
        room: room,
      ),
    );
  }

  List<String> _cellLines(Element cell) {
    final withNewlines = cell.innerHtml.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    final text = html_parser.parseFragment(withNewlines).text ?? '';
    return text
        .replaceAll('\u00a0', ' ')
        .split(RegExp(r'[\n\r]+'))
        .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((line) => line.isNotEmpty)
        .toList();
  }

  ({int start, int end})? _sectionsFrom(Iterable<String> lines) {
    for (final line in lines) {
      final match = _sectionRange.firstMatch(line);
      if (match != null) {
        return (
          start: int.parse(match.group(1)!),
          end: int.parse(match.group(2)!),
        );
      }
    }
    return null;
  }

  int? _weekday(String text) {
    final normalized = text.replaceFirst(RegExp(r'^(星期|周)'), '');
    return switch (normalized) {
      '一' => DateTime.monday,
      '二' => DateTime.tuesday,
      '三' => DateTime.wednesday,
      '四' => DateTime.thursday,
      '五' => DateTime.friday,
      '六' => DateTime.saturday,
      '日' || '天' => DateTime.sunday,
      _ => null,
    };
  }

  Semester _semester(Document document, Element table) {
    final match = _semesterPattern.firstMatch(document.body?.text ?? '');
    final start =
        DateTime.tryParse(table.attributes['data-first-week-start'] ?? '') ??
        DateTime(2026, 9, 7);
    final totalWeeks =
        int.tryParse(table.attributes['data-total-weeks'] ?? '') ?? 18;
    if (match == null) {
      return Semester(
        id: 'cdcas-2026-2027-1',
        name: '2026-2027学年第1学期',
        firstWeekStart: start,
        totalWeeks: totalWeeks,
      );
    }
    final id = 'cdcas-${match.group(1)}-${match.group(2)}-${match.group(3)}';
    return Semester(
      id: id,
      name: '${match.group(1)}-${match.group(2)}学年第${match.group(3)}学期',
      firstWeekStart: start,
      totalWeeks: totalWeeks,
    );
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

class _TimetableMatch {
  const _TimetableMatch(this.table, this.headerRow, this.weekdays);

  final Element table;
  final int headerRow;
  final Map<int, int> weekdays;
}

class _ParsedSession {
  const _ParsedSession({
    required this.name,
    required this.teacher,
    required this.session,
  });

  final String name;
  final String teacher;
  final CourseSession session;
}
