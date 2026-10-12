import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';

void main() {
  final semester = Semester(
    id: 'v09-fixture',
    name: '2026秋季',
    firstWeekStart: DateTime(2026, 9, 7),
    totalWeeks: 16,
  );
  const importer = SmartTimetableImporter();
  final samples =
      jsonDecode(
            File(
              'test/fixtures/v09_generated/expected.json',
            ).readAsStringSync(),
          )
          as List;
  for (final dynamic raw in samples) {
    final sample = Map<String, dynamic>.from(raw as Map);
    final file = sample['file'] as String;
    test('real Excel $file preserves exact courses and scheduled weeks', () {
      final workbook = importer.parseWorkbook(
        File('test/fixtures/v09_generated/$file').readAsBytesSync(),
        semester,
      );
      final expected = sample['courses'] as List;
      if (expected.isEmpty) {
        expect(workbook.available, isEmpty);
        return;
      }
      final preview = importer.mergeSelectedSheets(workbook.available);
      expect(
        preview.courses.map((c) => c.name).toSet(),
        expected.map((e) => e['name']).toSet(),
        reason: workbook.sheets.map((s) => '${s.name}: ${s.error}').join('\n'),
      );
      for (final dynamic exp in expected) {
        final course = preview.courses.singleWhere(
          (c) => c.name == exp['name'],
        );
        expect(
          course.teacher,
          exp['teacher'],
          reason: '$file ${course.name} teacher',
        );
        expect(course.sessions.map((s) => s.weekday).toSet(), {exp['day']});
        expect(course.sessions.map((s) => s.startSection).toSet(), {
          exp['start'],
        });
        expect(course.sessions.map((s) => s.endSection).toSet(), {exp['end']});
        expect(course.sessions.map((s) => s.room).toSet(), {exp['room']});
        final actualWeeks = {
          for (var week = 1; week <= 16; week++)
            if (course.sessions.any((s) => s.occursInWeek(week))) week,
        };
        expect(
          actualWeeks,
          (exp['weeks'] as List).toSet(),
          reason: '$file ${course.name} weeks',
        );
        if (file != '05_multi_sheet_with_times.xlsx') {
          expect(course.sessions.map((s) => s.startMinute).toSet(), {
            exp['time'][0],
          }, reason: '$file ${course.name} start time');
          expect(course.sessions.map((s) => s.endMinute).toSet(), {
            exp['time'][1],
          }, reason: '$file ${course.name} end time');
        }
      }
      if (file == '05_multi_sheet_with_times.xlsx') {
        expect(
          preview.importedTimes.any(
            (t) =>
                t.startSection == 1 &&
                t.endSection == 2 &&
                t.startMinute == 480 &&
                t.endMinute == 575,
          ),
          isTrue,
        );
      }
    });
  }
  test(
    'corrupt and empty bytes are rejected instead of creating a timetable',
    () {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 0]),
        Uint8List.fromList(utf8.encode('not excel')),
      ]) {
        expect(
          () => importer.parseWorkbook(bytes, semester),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
