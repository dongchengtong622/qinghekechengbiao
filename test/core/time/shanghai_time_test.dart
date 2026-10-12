import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/core/time/shanghai_time.dart';

void main() {
  test('converts a UTC instant to the Shanghai calendar day', () {
    final result = ShanghaiTime.fromUtc(DateTime.utc(2026, 9, 20, 16, 30));

    expect(result.location.name, 'Asia/Shanghai');
    expect(result.year, 2026);
    expect(result.month, 9);
    expect(result.day, 21);
    expect(result.hour, 0);
    expect(result.minute, 30);
  });

  test('constructs course times in the Shanghai location', () {
    final result = ShanghaiTime.dateTime(2026, 9, 21, 7, 55);

    expect(result.location.name, 'Asia/Shanghai');
    expect(result.toIso8601String(), '2026-09-21T07:55:00.000+0800');
  });
}
