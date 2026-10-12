import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:qinghe_timetable/features/reminders/domain/china_holiday_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('official rest silences alarms; an adjusted Sunday still rings', () {
    final calendar = ChinaHolidayCalendar.fromJson('''
      {"code":0,"holiday":{
        "01-01":{"holiday":true,"name":"元旦"},
        "01-03":{"holiday":true,"name":"周六"},
        "01-04":{"holiday":false,"name":"元旦调休"}
      }}
    ''', year: 2026);

    expect(calendar.shouldSilence(DateTime(2026, 1, 1)), isTrue);
    expect(calendar.shouldSilence(DateTime(2026, 1, 3)), isFalse);
    expect(calendar.shouldSilence(DateTime(2026, 1, 4)), isFalse);
    expect(calendar.kindFor(DateTime(2026, 1, 3)), HolidayDayKind.weekend);
    expect(
      calendar.kindFor(DateTime(2026, 1, 4)),
      HolidayDayKind.adjustedWorkday,
    );
  });

  test('invalid online response cannot replace a valid local calendar', () {
    expect(
      () => ChinaHolidayCalendar.fromJson('{"code":-1}', year: 2026),
      throwsFormatException,
    );
  });

  test(
    'bundled 2026 calendar contains National Day and make-up workday',
    () async {
      final source = await rootBundle.loadString(
        'assets/holidays/china_2026.json',
      );
      final calendar = ChinaHolidayCalendar.fromJson(source, year: 2026);
      expect(calendar.shouldSilence(DateTime(2026, 10, 1)), isTrue);
      expect(calendar.shouldSilence(DateTime(2026, 10, 7)), isTrue);
      expect(
        calendar.kindFor(DateTime(2026, 10, 10)),
        HolidayDayKind.adjustedWorkday,
      );
      expect(calendar.shouldSilence(DateTime(2026, 9, 20)), isFalse);
    },
  );
}
