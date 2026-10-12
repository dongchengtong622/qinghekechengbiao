import 'dart:typed_data';
import 'package:excel_plus/excel_plus.dart';
import '../domain/models.dart';
import 'excel_timetable_importer.dart';
import 'text_workbook_decoder.dart';
import 'timetable_import.dart';
import 'section_number_parser.dart';
import 'import_time_plan.dart';
import '../domain/school_schedule.dart';

class GridCell {
  const GridCell(
    this.text,
    this.row,
    this.column, {
    this.rowSpan = 1,
    this.columnSpan = 1,
  });
  final String text;
  final int row, column, rowSpan, columnSpan;
}

class ExcelSheetGrid {
  const ExcelSheetGrid({
    required this.name,
    required this.cells,
    required this.rowCount,
    required this.columnCount,
  });

  final String name;
  final List<GridCell> cells;
  final int rowCount;
  final int columnCount;
}

class ExcelMappingRequiredException implements Exception {
  const ExcelMappingRequiredException(this.sheets);

  final List<ExcelSheetGrid> sheets;

  @override
  String toString() => '自动识别未找到可导入课程，请手动指定星期行和节次列。';
}

class SheetImportResult {
  const SheetImportResult({
    required this.name,
    required this.grid,
    this.preview,
    this.error,
    this.duplicateCount = 0,
    this.conflictCount = 0,
  });

  final String name;
  final ExcelSheetGrid grid;
  final ImportPreview? preview;
  final String? error;
  final int duplicateCount;
  final int conflictCount;
}

class WorkbookImportPreview {
  const WorkbookImportPreview(this.sheets);

  final List<SheetImportResult> sheets;

  List<SheetImportResult> get available =>
      sheets.where((sheet) => sheet.preview != null).toList(growable: false);
}

class SmartTimetableImporter {
  const SmartTimetableImporter();
  static int? weekday(String text) {
    final normalized = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    for (var i = 0; i < 7; i++) {
      if (normalized == '周${names[i]}' ||
          normalized == '星期${names[i]}' ||
          normalized == '呈期${names[i]}' ||
          normalized == '礼拜${names[i]}' ||
          normalized == '周${i + 1}' ||
          normalized == '星期${i + 1}' ||
          normalized == ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'][i] ||
          normalized ==
              [
                'monday',
                'tuesday',
                'wednesday',
                'thursday',
                'friday',
                'saturday',
                'sunday',
              ][i]) {
        return i + 1;
      }
    }
    if (normalized == '星期天' ||
        normalized == '周天' ||
        normalized == '礼拜天' ||
        normalized == '礼拜日') {
      return 7;
    }
    return null;
  }

  static (int, int)? sections(String text) {
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final value = TimetableTimeText.strip(line).trim();
      if (RegExp(r'\d\s*[:：]\s*\d').hasMatch(value)) continue;
      if (value.isEmpty ||
          weekday(value) != null ||
          (text.contains(RegExp(r'[\r\n]')) &&
              RegExp(r'^[一二三四五六日天]$').hasMatch(value))) {
        continue;
      }
      final chinesePair = RegExp(
        r'^(?:第)?\s*([一二三四五六七八九])\s*([一二三四五六七八九])\s*节$',
      ).firstMatch(value);
      if (chinesePair != null) {
        final start = SectionNumberParser.periodNumber(chinesePair[1]!);
        final end = SectionNumberParser.periodNumber(chinesePair[2]!);
        if (start != null && end != null && end >= start) return (start, end);
      }
      final paired = RegExp(
        r'(?<!\d)(\d{1,2})\s*[、,，]\s*(\d{1,2})\s*小节',
      ).firstMatch(value);
      if (paired != null) {
        final start = int.parse(paired[1]!), end = int.parse(paired[2]!);
        return start > 0 && end >= start && end <= 30 ? (start, end) : null;
      }
      final range = RegExp(
        r'(?<!\d)(\d{1,2})\s*[-–—~至]\s*(\d{1,2})\s*节?',
      ).firstMatch(value);
      if (range != null && !value.contains('周')) {
        final start = int.parse(range[1]!), end = int.parse(range[2]!);
        return start > 0 && end >= start && end <= 30 ? (start, end) : null;
      }
      final single = RegExp(r'^(?:第)?\s*(\d{1,2})\s*节?$').firstMatch(value);
      if (single != null) {
        final section = int.parse(single[1]!);
        return section > 0 && section <= 30 ? (section, section) : null;
      }
      final chinese = RegExp(
        r'^(?:第)?\s*([一二三四五六七八九十]{1,3})\s*节?$',
      ).firstMatch(value);
      final section = chinese == null
          ? null
          : SectionNumberParser.periodNumber(chinese[1]!);
      if (section != null) return (section, section);
    }
    return null;
  }

  ImportPreview parseExcel(Uint8List bytes, Semester semester) {
    final workbook = parseWorkbook(bytes, semester);
    final available = workbook.available;
    if (available.isEmpty) {
      final grids = workbook.sheets
          .where((sheet) => sheet.grid.cells.isNotEmpty)
          .map((sheet) => sheet.grid)
          .toList(growable: false);
      if (grids.isNotEmpty) {
        throw ExcelMappingRequiredException(grids);
      }
      throw const FormatException('Excel 工作簿没有可读取的课程内容。');
    }
    if (available.length == 1) return available.single.preview!;
    return mergeSelectedSheets(available);
  }

  WorkbookImportPreview parseWorkbook(Uint8List bytes, Semester semester) {
    final rowImporter = const ExcelTimetableImporter();
    final Excel workbook;
    try {
      workbook = rowImporter.decodeWorkbook(bytes);
    } on WorkbookReadException catch (error) {
      throw FormatException(error.message);
    } catch (error) {
      throw const FormatException(
        '无法解析这份表格的内部格式。支持 Excel 工作簿及常见网页、XML表格导出；请确认文件下载完整。',
      );
    }
    final results = <SheetImportResult>[];
    final workbookTimes = <SectionRangeTime>[];
    final priorCourses = <Course>[];
    for (final entry in workbook.tables.entries) {
      final sheet = entry.value;
      final spans = <String, (int, int)>{};
      for (final range in sheet.spannedItems) {
        final parts = range.split(':');
        if (parts.length != 2) continue;
        final a = CellIndex.indexByString(parts[0]),
            b = CellIndex.indexByString(parts[1]);
        spans['${a.rowIndex}:${a.columnIndex}'] = (
          b.rowIndex - a.rowIndex + 1,
          b.columnIndex - a.columnIndex + 1,
        );
      }
      final cells = <GridCell>[];
      for (var row = 0; row < sheet.rows.length; row++) {
        for (var col = 0; col < sheet.rows[row].length; col++) {
          final value = sheet.rows[row][col]?.value;
          final text = value is TextCellValue
              ? value.value.toString()
              : value?.toString() ?? '';
          if (text.trim().isEmpty) continue;
          final span = spans['$row:$col'];
          cells.add(
            GridCell(
              text,
              row,
              col,
              rowSpan: span?.$1 ?? 1,
              columnSpan: span?.$2 ?? 1,
            ),
          );
        }
      }
      final grid = ExcelSheetGrid(
        name: entry.key,
        cells: List.unmodifiable(cells),
        rowCount: sheet.rows.length,
        columnCount: sheet.rows.fold<int>(
          0,
          (max, row) => row.length > max ? row.length : max,
        ),
      );
      workbookTimes.addAll(readTimes(cells, semester.id));
      ImportPreview? preview;
      String? error;
      try {
        preview = rowImporter.parseRows(
          rowImporter.sheetRows(sheet),
          fallbackSemester: semester,
        );
      } on ExcelImportException catch (failure) {
        try {
          preview = parseGrid(cells, semester);
        } on FormatException catch (gridFailure) {
          try {
            preview = _parseDaySectionRecords(cells, semester);
          } on FormatException catch (recordFailure) {
            error = recordFailure.message.isEmpty
                ? (gridFailure.message.isEmpty
                      ? failure.message
                      : gridFailure.message)
                : recordFailure.message;
          }
        }
      }
      final duplicates = preview == null
          ? 0
          : preview.courses
                .where(
                  (course) => priorCourses.any(
                    (prior) =>
                        _courseSignature(prior) == _courseSignature(course),
                  ),
                )
                .length;
      final conflicts = preview == null
          ? 0
          : preview.courses
                .where(
                  (course) => priorCourses.any(
                    (prior) => _coursesConflict(prior, course),
                  ),
                )
                .length;
      results.add(
        SheetImportResult(
          name: entry.key,
          grid: grid,
          preview: preview,
          error: error,
          duplicateCount: duplicates,
          conflictCount: conflicts,
        ),
      );
      if (preview != null) priorCourses.addAll(preview.courses);
    }
    return WorkbookImportPreview(
      List.unmodifiable(
        results.map((r) {
          final p = r.preview;
          return SheetImportResult(
            name: r.name,
            grid: r.grid,
            error: r.error,
            duplicateCount: r.duplicateCount,
            conflictCount: r.conflictCount,
            preview: p == null
                ? null
                : ImportPreview(
                    semester: p.semester,
                    courses: p.courses,
                    warnings: p.warnings,
                    replaceExisting: p.replaceExisting,
                    courseReviews: p.courseReviews,
                    importedTimes: [...p.importedTimes, ...workbookTimes],
                  ),
          );
        }),
      ),
    );
  }

  static List<SectionRangeTime> readTimes(
    List<GridCell> cells,
    String semesterId,
  ) {
    final result = <SectionRangeTime>[];
    for (final cell in cells) {
      final span = sections(cell.text);
      if (span == null) continue;
      final nearby =
          cells
              .where(
                (c) =>
                    c.row == cell.row &&
                    c.column > cell.column &&
                    c.column <= cell.column + 2 &&
                    RegExp(r'^[\d\s:：\-–—~～至到]+$').hasMatch(c.text),
              )
              .toList()
            ..sort((a, b) => a.column.compareTo(b.column));
      final time =
          TimetableTimeText.range(cell.text) ??
          TimetableTimeText.range(nearby.map((c) => c.text).join(' - '));
      if (time != null) {
        result.add(
          SectionRangeTime(
            semesterId: semesterId,
            startSection: span.$1,
            endSection: span.$2,
            startMinute: time.$1,
            endMinute: time.$2,
          ),
        );
      }
    }
    return result;
  }

  ImportPreview _parseDaySectionRecords(
    List<GridCell> cells,
    Semester semester,
  ) {
    final byRow = <int, List<GridCell>>{};
    for (final cell in cells) {
      (byRow[cell.row] ??= []).add(cell);
    }
    final records = <({int day, (int, int) sections, String details})>[];
    for (final row in byRow.values) {
      row.sort((a, b) => a.column.compareTo(b.column));
      for (var dayIndex = 0; dayIndex < row.length; dayIndex++) {
        final day = weekday(row[dayIndex].text);
        if (day == null) continue;
        for (
          var sectionIndex = dayIndex + 1;
          sectionIndex < row.length;
          sectionIndex++
        ) {
          final section = sections(row[sectionIndex].text);
          if (section == null) continue;
          final details = row.skip(sectionIndex + 1).firstOrNull;
          if (details == null) break;
          records.add((day: day, sections: section, details: details.text));
          break;
        }
      }
    }
    if (records.isEmpty) {
      throw const FormatException('没有找到“星期、节次、课程内容”同行排列的课程记录。');
    }
    return _parseRecordCells(records, semester);
  }

  ImportPreview _parseRecordCells(
    List<({int day, (int, int) sections, String details})> records,
    Semester semester,
  ) {
    final courses = <Course>[];
    final warnings = <String>[];
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final time = TimetableTimeText.bounds(record.details);
      final rawLines = TimetableTimeText.strip(record.details)
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (rawLines.isEmpty) {
        warnings.add('第 ${index + 1} 条记录缺少课程内容。');
        continue;
      }
      final weeks = <int>{};
      var pattern = WeekPattern.everyWeek;
      for (final line in rawLines.skip(1)) {
        final match = RegExp(
          r'第?\s*(\d+)\s*[-~–—至]\s*(\d+)\s*周(?:\s*[（(]?\s*(单周|双周)\s*[）)]?)?',
        ).firstMatch(line);
        if (match == null) continue;
        final start = int.parse(match[1]!);
        final end = int.parse(match[2]!);
        if (start < 1 || end < start || end > 60) {
          warnings.add('“${rawLines.first}”的周次超出可支持范围（1–60周），请在预览中核对。');
          weeks.clear();
          break;
        }
        if (end > semester.totalWeeks) {
          warnings.add('“${rawLines.first}”安排到第 $end 周，已保留完整周次，请调整学期总周数后导入。');
        }
        if (match[3] == '单周') pattern = WeekPattern.oddWeeks;
        if (match[3] == '双周') pattern = WeekPattern.evenWeeks;
        for (var week = start; week <= end; week++) {
          if (pattern == WeekPattern.oddWeeks && week.isEven) continue;
          if (pattern == WeekPattern.evenWeeks && week.isOdd) continue;
          weeks.add(week);
        }
      }
      if (weeks.isEmpty) {
        weeks.addAll(List.generate(semester.totalWeeks, (i) => i + 1));
        warnings.add('“${rawLines.first}”缺少有效周次，暂按全学期，请核对。');
      }
      String? room;
      String? teacher;
      for (final line in rawLines.skip(1)) {
        if (line.contains('周')) continue;
        if (teacher == null &&
            RegExp(r'^[\u4e00-\u9fff]{2,4}$').hasMatch(line)) {
          teacher = line;
        } else if (room == null &&
            RegExp(
              r'楼|室|栋|馆|区|场地|机房|画室|摄影棚|实验室|工作室|温室|苗圃|集合|中心|操场|体育馆|A\d{2,}|B\d{2,}|C\d{2,}',
            ).hasMatch(line)) {
          room = line;
        }
      }
      final sortedWeeks = weeks.toList()..sort();
      final ranges = <(int, int)>[];
      for (final week in sortedWeeks) {
        if (ranges.isNotEmpty && ranges.last.$2 + 1 == week) {
          final previous = ranges.removeLast();
          ranges.add((previous.$1, week));
        } else {
          ranges.add((week, week));
        }
      }
      final id =
          'record-${_hash('${rawLines.first}|${record.day}|${record.sections}|${rawLines.join('|')}')}';
      courses.add(
        Course(
          id: id,
          semesterId: semester.id,
          source: CourseSource.cdcasKingo,
          externalId: id,
          name: rawLines.first,
          teacher: teacher ?? '',
          colorValue: const [
            0xFF2E7D66,
            0xFF6366A8,
            0xFFD77855,
            0xFF9A6BB5,
          ][_hash(rawLines.first) % 4],
          sessions: [
            for (final range in ranges)
              CourseSession(
                weekday: record.day,
                startSection: record.sections.$1,
                endSection: record.sections.$2,
                startWeek: range.$1,
                endWeek: range.$2,
                pattern: pattern,
                room: room ?? '',
                startMinute: time.$1,
                endMinute: time.$2,
                timeSource: time.$1 == null && time.$2 == null
                    ? CourseTimeSource.schedule
                    : CourseTimeSource.imported,
              ),
          ],
        ),
      );
    }
    if (courses.isEmpty) throw const FormatException('没有识别到有效的课程记录。');
    return ImportPreview(
      semester: semester,
      courses: List.unmodifiable(courses),
      warnings: List.unmodifiable(warnings),
      replaceExisting: false,
    );
  }

  ImportPreview mergeSelectedSheets(List<SheetImportResult> selected) {
    final previews = selected
        .map((sheet) => sheet.preview)
        .whereType<ImportPreview>()
        .toList(growable: false);
    if (previews.isEmpty) throw const FormatException('请至少选择一张可导入的工作表。');
    final semester = previews.first.semester;
    if (previews.any((preview) => preview.semester.id != semester.id)) {
      throw const FormatException('所选工作表属于不同学期，请分开导入。');
    }
    final courses = <Course>[];
    final signatures = <String>{};
    final byExternalId = <String, int>{};
    final warnings = <String>[];
    var duplicateCount = 0;
    var conflictCount = 0;
    for (final sheet in selected) {
      final preview = sheet.preview;
      if (preview == null) continue;
      warnings.addAll(
        preview.warnings.map((warning) => '${sheet.name}：$warning'),
      );
      for (final course in preview.courses) {
        if (!signatures.add(_courseSignature(course))) {
          duplicateCount++;
          continue;
        }
        final externalId = course.externalId;
        final existingIndex = externalId == null
            ? null
            : byExternalId[externalId];
        if (existingIndex != null) {
          final existing = courses[existingIndex];
          if (existing.name != course.name ||
              existing.teacher != course.teacher) {
            throw const FormatException('工作表中的课程标识发生冲突，请分开导入并核对课程。');
          }
          final sessions = [...existing.sessions];
          for (final session in course.sessions) {
            if (sessions.any(
              (value) => _sessionSignature(value) == _sessionSignature(session),
            )) {
              duplicateCount++;
            } else {
              sessions.add(session);
            }
          }
          courses[existingIndex] = Course(
            id: existing.id,
            semesterId: existing.semesterId,
            source: existing.source,
            externalId: existing.externalId,
            name: existing.name,
            teacher: existing.teacher,
            colorValue: existing.colorValue,
            sessions: List.unmodifiable(sessions),
          );
          continue;
        }
        if (courses.any((prior) => _coursesConflict(prior, course))) {
          conflictCount++;
        }
        if (externalId != null) byExternalId[externalId] = courses.length;
        courses.add(course);
      }
    }
    if (duplicateCount > 0) warnings.add('跨工作表跳过 $duplicateCount 门完全重复的课程。');
    if (conflictCount > 0) {
      warnings.add('跨工作表发现 $conflictCount 门时间重叠的课程，请在预览中核对。');
    }
    return ImportPreview(
      semester: semester,
      courses: List.unmodifiable(courses),
      warnings: List.unmodifiable(warnings),
      replaceExisting: previews.every((preview) => preview.replaceExisting),
      importedTimes: previews.expand((p) => p.importedTimes).toList(),
    );
  }

  String _courseSignature(Course course) => [
    course.name.trim(),
    course.teacher.trim(),
    for (final session in course.sessions) _sessionSignature(session),
  ].join('|');

  String _sessionSignature(CourseSession session) =>
      '${session.weekday}:${session.startSection}:${session.endSection}:'
      '${session.startWeek}:${session.endWeek}:${session.pattern.name}:'
      '${session.room}:${session.startMinute}:${session.endMinute}:'
      '${session.timeSource.name}';

  bool _coursesConflict(Course left, Course right) {
    if (left.name == right.name && left.teacher == right.teacher) return false;
    for (final a in left.sessions) {
      for (final b in right.sessions) {
        if (a.weekday != b.weekday ||
            a.startSection > b.endSection ||
            b.startSection > a.endSection) {
          continue;
        }
        final start = a.startWeek > b.startWeek ? a.startWeek : b.startWeek;
        final end = a.endWeek < b.endWeek ? a.endWeek : b.endWeek;
        for (var week = start; week <= end; week++) {
          if (a.occursInWeek(week) && b.occursInWeek(week)) return true;
        }
      }
    }
    return false;
  }

  List<GridCell>? _transposeWeekdayRows(List<GridCell> cells) {
    final weekdays = cells
        .where((cell) => weekday(cell.text) != null)
        .toList(growable: false);
    final byColumn = <int, List<GridCell>>{};
    for (final cell in weekdays) {
      (byColumn[cell.column] ??= []).add(cell);
    }
    final dayColumn =
        byColumn.entries
            .where(
              (entry) =>
                  entry.value.map((cell) => cell.row).toSet().length >= 2,
            )
            .toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (dayColumn.isEmpty) return null;

    for (final candidate in dayColumn) {
      final days = candidate.value..sort((a, b) => a.row.compareTo(b.row));
      final firstDayRow = days.first.row;
      final sectionHeadersByRow = <int, List<GridCell>>{};
      for (final cell in cells) {
        if (cell.row >= firstDayRow ||
            cell.column <= candidate.key ||
            sections(cell.text) == null) {
          continue;
        }
        (sectionHeadersByRow[cell.row] ??= []).add(cell);
      }
      final headerRows =
          sectionHeadersByRow.entries
              .where(
                (entry) =>
                    entry.value.map((cell) => cell.column).toSet().length >= 2,
              )
              .toList()
            ..sort((a, b) => b.key.compareTo(a.key));
      if (headerRows.isEmpty) continue;
      final sectionHeaders = headerRows.first.value
        ..sort((a, b) => a.column.compareTo(b.column));
      final uniqueDays = <int>{};
      for (final day in days) {
        final value = weekday(day.text);
        if (value != null) uniqueDays.add(value);
      }
      if (uniqueDays.length < 2 || sectionHeaders.length < 2) continue;

      final transformed = <GridCell>[
        for (var index = 0; index < days.length; index++)
          GridCell(days[index].text, 0, index + 1),
        for (var index = 0; index < sectionHeaders.length; index++)
          GridCell(sectionHeaders[index].text, index + 1, 0, rowSpan: 1),
      ];
      for (final cell in cells) {
        final dayIndex = days.indexWhere(
          (day) => cell.row >= day.row && cell.row < day.row + day.rowSpan,
        );
        final sectionIndex = sectionHeaders.indexWhere(
          (header) =>
              cell.column >= header.column &&
              cell.column < header.column + header.columnSpan,
        );
        if (dayIndex < 0 ||
            sectionIndex < 0 ||
            cell.row < firstDayRow ||
            cell.column == candidate.key ||
            weekday(cell.text) != null ||
            sections(cell.text) != null) {
          continue;
        }
        transformed.add(
          GridCell(
            cell.text,
            sectionIndex + 1,
            dayIndex + 1,
            rowSpan: cell.columnSpan,
            columnSpan: cell.rowSpan,
          ),
        );
      }
      return transformed;
    }
    return null;
  }

  ImportPreview parseGrid(
    List<GridCell> cells,
    Semester semester, {
    int? headerRow,
    int? periodColumn,
  }) {
    if ((headerRow == null) != (periodColumn == null)) {
      throw ArgumentError('星期行和节次列必须同时指定');
    }
    final headerRows = <int, List<GridCell>>{};
    for (final c in cells) {
      if (weekday(c.text) != null) (headerRows[c.row] ??= []).add(c);
    }
    final candidates =
        headerRows.values
            .where((v) => v.map((c) => weekday(c.text)).toSet().length >= 2)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    if (candidates.isEmpty && headerRow == null) {
      final transposed = _transposeWeekdayRows(cells);
      if (transposed != null) return parseGrid(transposed, semester);
      throw const FormatException('没有识别到星期列，请保留完整星期表头。');
    }
    final headers = headerRow == null
        ? candidates.first
        : cells
              .where((c) => c.row == headerRow && c.column > periodColumn!)
              .toList();
    if (headerRow != null && periodColumn != null) {
      final lastColumn = cells.fold<int>(
        periodColumn,
        (max, cell) => cell.column > max ? cell.column : max,
      );
      for (
        var column = periodColumn + 1;
        column <= lastColumn && column <= periodColumn + 7;
        column++
      ) {
        if (!headers.any((h) => h.column == column)) {
          headers.add(GridCell('', headerRow, column));
        }
      }
    }
    headers.sort((a, b) => a.column.compareTo(b.column));
    if (headers.isEmpty) throw const FormatException('所选星期行没有课程列，请重新选择。');
    final days = <int, int>{};
    var inferredDays = false;
    for (var index = 0; index < headers.length; index++) {
      final h = headers[index];
      final day =
          weekday(h.text) ??
          (headerRow != null && index < DateTime.daysPerWeek
              ? index + 1
              : null);
      if (day == null) continue;
      if (weekday(h.text) == null) inferredDays = true;
      for (var col = h.column; col < h.column + h.columnSpan; col++) {
        days[col] = day;
      }
    }
    final periods = <int, (int, int)>{};
    final periodTimes = <int, (int?, int?)>{};
    for (final c in cells.where(
      (c) =>
          (periodColumn == null
              ? c.column < headers.first.column
              : c.column == periodColumn) &&
          c.row > headers.first.row,
    )) {
      final section = sections(c.text);
      if (section != null) {
        final headingTimes = TimetableTimeText.bounds(c.text);
        final separateTimes = TimetableTimeText.bounds(
          cells
              .where(
                (p) =>
                    p.row == c.row && p.column < headers.first.column && p != c,
              )
              .map((p) => p.text)
              .join(' - '),
        );
        final time = (
          headingTimes.$1 ?? separateTimes.$1,
          headingTimes.$2 ?? separateTimes.$2,
        );
        for (var row = c.row; row < c.row + c.rowSpan; row++) {
          periods[row] = section;
          if (time.$1 != null || time.$2 != null) periodTimes[row] = time;
        }
      }
    }
    final courses = <Course>[];
    final warnings = <String>['请核对第一周日期、节次和周次后再导入。'];
    if (inferredDays) warnings.add('已按所选星期行从左到右推断星期，请逐门核对。');
    final sectionPattern = RegExp(
      r'[\[【（(]?\s*(?:第)?(\d{1,2})(?:\s*[-–—~至]\s*(\d{1,2}))?\s*节[\]】）)]?',
    );
    final weekPattern = RegExp(
      r'[\[【（(]?[ \t]*(?:第)?(\d+(?:[ \t]*[-~–—至][ \t]*\d+)?(?:[ \t]*[,，、][ \t]*\d+(?:[ \t]*[-~–—至][ \t]*\d+)?)*)[ \t]*([单双]?)周(?:[ \t]*[（(]([单双])周[）)])?[\]】）)]?',
    );
    for (final c in cells) {
      if (!days.containsKey(c.column) ||
          c.row <= headers.first.row ||
          c.text.trim().isEmpty) {
        continue;
      }
      final chunks = _splitCourseChunks(c.text);
      for (var raw in chunks) {
        raw = raw.trim();
        if (raw.isEmpty || const ['无课', '休息', '午休', '—', '-'].contains(raw)) {
          continue;
        }
        if (weekday(raw) != null) continue;
        final explicit = sectionPattern.firstMatch(raw);
        final inferred = periods[c.row];
        if (explicit == null && inferred == null) {
          warnings.add('以下内容缺少节次，未导入：$raw');
          continue;
        }
        final start = explicit == null ? inferred!.$1 : int.parse(explicit[1]!);
        var end = explicit == null
            ? inferred!.$2
            : int.parse(explicit[2] ?? explicit[1]!);
        if (explicit == null) {
          for (final e in periods.entries.where(
            (e) => e.key >= c.row && e.key < c.row + c.rowSpan,
          )) {
            if (e.value.$2 > end) end = e.value.$2;
          }
        }
        if (start < 1 || end < start || end > 30) {
          warnings.add('以下内容的节次无法确认，未导入：$raw');
          continue;
        }
        final inlineTime = TimetableTimeText.bounds(raw);
        final axisStart = periodTimes[c.row];
        final axisEnd = periodTimes[c.row + c.rowSpan - 1] ?? axisStart;
        final time = (
          inlineTime.$1 ?? axisStart?.$1,
          inlineTime.$2 ?? axisEnd?.$2,
        );
        raw = TimetableTimeText.strip(raw);
        final codePrefix = RegExp(
          r'^[\[【［(（|TtIlr]*\s*\d{6,9}\s*[\]】］)）1lI|]?\s*',
        );
        final codedCourse = codePrefix.hasMatch(raw);
        final range = weekPattern.firstMatch(raw);
        final weeks = <int>{};
        var invalidWeeks = false;
        if (range != null) {
          for (final token in range[1]!.split(RegExp(r'[,，、]'))) {
            final bounds = token.trim().split(RegExp(r'[-~–—至]'));
            final lo = int.parse(bounds.first.trim()),
                hi = int.parse(bounds.last.trim());
            if (lo < 1 || hi < lo || hi > 60) {
              warnings.add('“$raw”的周次超出可支持范围（1–60周），未导入；请核对或在预览中手动补充。');
              invalidWeeks = true;
              break;
            }
            if (hi > semester.totalWeeks) {
              warnings.add('课程安排到第 $hi 周，已保留完整周次，请调整学期总周数后导入。');
            }
            weeks.addAll(List.generate(hi - lo + 1, (i) => lo + i));
          }
          if (invalidWeeks) continue;
        } else if (codedCourse) {
          warnings.add('“${raw.split('\n').first}”的周次识别不清，未导入；请在预览中手动补充。');
          continue;
        } else {
          weeks.addAll(List.generate(semester.totalWeeks, (i) => i + 1));
          warnings.add('“${raw.split('\n').first}”缺少周次，暂按全学期，请核对。');
        }
        final weekPatternValue = (raw.contains('单周') || (range?[2] == '单'))
            ? WeekPattern.oddWeeks
            : (raw.contains('双周') || (range?[2] == '双'))
            ? WeekPattern.evenWeeks
            : WeekPattern.everyWeek;
        if (weeks.isEmpty) continue;
        var clean = raw
            .replaceFirst(codePrefix, '')
            .replaceAll(weekPattern, ' ')
            .replaceAll(sectionPattern, ' ')
            .replaceAll(RegExp(r'[（(]?\s*[单双]周\s*[）)]?'), ' ');
        // Code-led school grids wrap titles and rooms visually across lines.
        // A week marker supplies the field boundary even when OCR splits words.
        if (codedCourse && range != null) {
          final title = raw
              .substring(0, range.start)
              .replaceFirst(codePrefix, '')
              .replaceAll(RegExp(r'\s+'), '');
          final details = raw
              .substring(range.end)
              .replaceAll(sectionPattern, ' ')
              .replaceAll(RegExp(r'[（(]?\s*[单双]周\s*[）)]?'), ' ')
              .replaceAll(RegExp(r'\s*\n\s*'), '')
              .trim();
          clean = '$title\n$details';
        }
        final semicolonRecord = raw.contains(';') || raw.contains('；');
        final parts = (semicolonRecord ? raw : clean)
            .split(
              semicolonRecord
                  ? RegExp(r'[\r\n;；]+')
                  : RegExp(r'\n|@|\s{2,}|\s*/\s*'),
            )
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isEmpty) continue;
        var name = parts.first.replaceFirst(RegExp(r'^课程[：:]'), '');
        String teacher = '', room = '';
        if (semicolonRecord) {
          if (parts.length < 3) {
            warnings.add('“$raw”的教师、周次或教室字段不完整，请在预览中核对。');
          }
          if (parts.length > 1 && !parts[1].contains('周')) {
            teacher = parts[1];
          } else {
            final head = RegExp(
              r'^(.*?)\s+([^\s]+(?:副教授|教授|副研究员|研究员|讲师(?:（[^）]+）)?|助教(?:（[^）]+）)?))$',
            ).firstMatch(name);
            if (head != null) {
              name = head[1]!.trim();
              teacher = head[2]!.trim();
            }
          }
          final roomParts = parts
              .skip(1)
              .where((part) => !part.contains('周') && part != teacher)
              .toList();
          room = roomParts.join(' ');
        }
        for (final field in semicolonRecord ? <String>[] : parts.skip(1)) {
          if (RegExp(
            r'楼|室|栋|馆|区|场地|机房|画室|摄影棚|实验室|工作室|温室|苗圃|集合|中心|操场|体育馆|线上|在线|教学平台|[A-Za-z]?\d{2,}',
          ).hasMatch(field)) {
            room = room.isEmpty ? field : '$room $field';
          } else if (teacher.isEmpty) {
            teacher = field.replaceFirst(RegExp(r'^(教师|老师)[：:]'), '');
          } else {
            warnings.add('“$name”有待核对字段：$field');
          }
        }
        if (room.isEmpty) warnings.add('“$name”的教室待核对。');
        final sorted = weeks.toList()..sort();
        final ranges = <(int, int)>[];
        for (final w in sorted) {
          if (ranges.isNotEmpty && ranges.last.$2 + 1 == w) {
            final last = ranges.removeLast();
            ranges.add((last.$1, w));
          } else {
            ranges.add((w, w));
          }
        }
        final id =
            'smart-${_hash('$name|$teacher|${days[c.column]}|$start|$end|$room|${sorted.join(',')}')}';
        courses.add(
          Course(
            id: id,
            semesterId: semester.id,
            source: CourseSource.cdcasKingo,
            externalId: id,
            name: name,
            teacher: teacher,
            colorValue: const [
              0xFF2E7D66,
              0xFF6366A8,
              0xFFD77855,
              0xFF9A6BB5,
            ][_hash(name) % 4],
            sessions: [
              for (final span in ranges)
                CourseSession(
                  weekday: days[c.column]!,
                  startSection: start,
                  endSection: end,
                  startWeek: span.$1,
                  endWeek: span.$2,
                  pattern: weekPatternValue,
                  room: room,
                  startMinute: time.$1,
                  endMinute: time.$2,
                  timeSource: time.$1 == null && time.$2 == null
                      ? CourseTimeSource.schedule
                      : CourseTimeSource.imported,
                ),
            ],
          ),
        );
      }
    }
    if (courses.isEmpty) {
      throw const FormatException('找到表格但未提取到课程，请保留星期和节次或使用模板。');
    }
    return ImportPreview(
      semester: semester,
      courses: {for (final c in courses) c.externalId!: c}.values.toList(),
      importedTimes: readTimes(
        cells
            .where(
              (c) =>
                  c.column < headers.first.column && c.row > headers.first.row,
            )
            .toList(),
        semester.id,
      ),
      warnings: warnings.toSet().toList(),
      replaceExisting: false,
    );
  }

  static int _hash(String text) {
    var h = 2166136261;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 16777619) & 0x7fffffff;
    }
    return h;
  }

  static List<String> _splitCourseChunks(String source) {
    final text = source.trim();
    // Blank lines can also separate notes. A standalone week line and
    // teacher/room fields are needed before treating blocks as schedules.
    final blocks = text.split(RegExp(r'\r?\n[ \t]*\r?\n(?:[ \t]*\r?\n)*'));
    final weekLine = RegExp(
      r'^(?:第)?\d+(?:\s*[-~–—至,，、]\s*\d+)*\s*(?:[单双])?周(?:\s*[（(][单双]周[）)])?$',
    );
    final lines = blocks
        .map(
          (b) => b
              .split(RegExp(r'[\r\n]+'))
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList(),
        )
        .toList();
    if (lines.length > 1 &&
        lines.first.length >= 4 &&
        lines.every(
          (block) => block.length >= 3 && block.any(weekLine.hasMatch),
        )) {
      final title = lines.first.first;
      return [
        for (final block in lines)
          ..._splitCourseChunks(
            (block.length == 3 ? [title, ...block] : block).join('\n'),
          ),
      ];
    }
    if (!text.contains(';') && !text.contains('；')) {
      return text.split(RegExp(r'(?=[\[【［(（|TtIlr]\s*\d{6,9})'));
    }
    final chunks = <String>[];
    var title = '';
    for (final line
        in text
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)) {
      if (line.contains(';') || line.contains('；')) {
        chunks.add(title.isEmpty ? line : '$title\n$line');
        title = '';
      } else {
        title = title.isEmpty ? line : '$title$line';
      }
    }
    if (title.isNotEmpty) chunks.add(title);
    return chunks;
  }
}
