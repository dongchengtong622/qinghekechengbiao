import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/data/timetable_import.dart';

void main() {
  final cases =
      jsonDecode(
            File('test/fixtures/v101_diverse/expected.json').readAsStringSync(),
          )
          as List;
  final term = Semester(
    id: 'blocks',
    name: '测试',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 16,
  );
  ImportPreview parseCell(String text) =>
      const SmartTimetableImporter().parseGrid([
        const GridCell('周一', 0, 1),
        const GridCell('周二', 0, 2),
        const GridCell('1-2节\n08:00-09:40', 1, 0),
        GridCell(text, 1, 1),
      ], term);
  test('blank-line week note does not become a fake course', () {
    final p = parseCell('高等数学\n张老师\n1-16周\n理科楼101\n\n第9周停课，具体安排另行通知');
    expect(p.courses.length, 1);
    expect(p.courses.single.name, '高等数学');
  });
  test('shared title is retained across teacher and room changes', () {
    final p = parseCell('高等数学\n张老师\n1-8周\n理科楼101\n\n李老师\n9-16周\n理科楼201');
    expect(p.courses.length, 2);
    expect(p.courses.map((c) => c.name).toSet(), {'高等数学'});
    expect(p.courses.first.teacher, '张老师');
    expect(p.courses.last.teacher, '李老师');
    expect(p.courses.last.sessions.single.room, '理科楼201');
    expect(p.courses.last.sessions.single.occursInWeek(8), false);
    expect(p.courses.last.sessions.single.occursInWeek(9), true);
  });
  for (final c in cases) {
    test(
      'diverse university ${c['file']} preserves every weekly teacher and room',
      () {
        final term = Semester(
          id: 'diverse',
          name: '模拟秋季',
          firstWeekStart: DateTime(2026, 9, 7),
          totalWeeks: 20,
        );
        const importer = SmartTimetableImporter();
        final workbook = importer.parseWorkbook(
          File('test/fixtures/v101_diverse/${c['file']}').readAsBytesSync(),
          term,
        );
        final preview = importer.mergeSelectedSheets(workbook.available);
        final rows = c['rows'] as List;
        for (var week = 1; week <= 20; week++) {
          bool matches(dynamic r) {
            final text = r[5] as String;
            if (text.contains('单周') && week.isEven ||
                text.contains('双周') && week.isOdd) {
              return false;
            }
            final parts = text.replaceAll(RegExp(r'\(.*?\)|周'), '').split(',');
            return parts.any((p) {
              final numbers = p.split('-').map(int.parse).toList();
              return numbers.length == 1
                  ? week == numbers.first
                  : week >= numbers.first && week <= numbers.last;
            });
          }

          final expected =
              rows
                  .where(matches)
                  .map(
                    (r) =>
                        '${r[0]}|${r[1]}|${r[2]}|${r[3]}|${r[4]}|${r[6]}|${r[7]}|${r[8]}',
                  )
                  .toList()
                ..sort();
          final actual = [
            for (final course in preview.courses)
              for (final s in course.sessions)
                if (s.occursInWeek(week))
                  '${course.name}|${course.teacher}|${s.weekday}|${s.startSection}|${s.endSection}|${s.room}|${s.startMinute}|${s.endMinute}',
          ]..sort();
          expect(
            actual,
            expected,
            reason:
                'week $week; ${workbook.sheets.map((s) => s.error).join(';')}',
          );
        }
      },
    );
  }
}
