import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/smart_timetable_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/import_time_plan.dart';
import 'package:qinghe_timetable/features/timetable/domain/models.dart';
import 'package:qinghe_timetable/features/timetable/domain/school_schedule.dart';
import 'package:qinghe_timetable/features/timetable/domain/time_slot_resolver.dart';

void main() {
  final cases =
      jsonDecode(
            File('test/fixtures/v101_times/expected.json').readAsStringSync(),
          )
          as List;
  for (final c in cases) {
    test(
      'V1.0.1 real university Excel ${c['file']} preserves evidence and splitting',
      () {
        final term = Semester(
          id: 'a',
          name: '测试学期',
          firstWeekStart: DateTime(2026, 9, 7),
          totalWeeks: 20,
        );
        const importer = SmartTimetableImporter();
        final workbook = importer.parseWorkbook(
          File('test/fixtures/v101_times/${c['file']}').readAsBytesSync(),
          term,
        );
        final preview = importer.mergeSelectedSheets(workbook.available);
        final course = preview.courses.single;
        expect(course.name, c['name']);
        expect(course.teacher, c['teacher']);
        expect(course.sessions.single.weekday, c['day']);
        expect(course.sessions.single.room, '综合教学楼A301');
        final resolved = ImportTimePlan(
          preview,
          SchoolSchedule.defaults(),
        ).schedule.resolve(course.sessions.single, semesterId: 'a');
        expect(resolved.startMinute, c['start']);
        expect(resolved.endMinute, c['end']);
        final split = TimeSlotResolver.split(
          c['first'],
          c['last'],
          resolved.startMinute!,
          resolved.endMinute!,
          lessonMinutes: c['lesson'],
        );
        if (c['gap'] == null) {
          expect(split.status, SlotStatus.needsConfirmation);
          expect(split.sections, isEmpty);
        } else {
          expect(split.breakMinutes, c['gap']);
          expect(split.sections.first.startMinute, c['start']);
          expect(split.sections.last.endMinute, c['end']);
        }
      },
    );
  }
}
