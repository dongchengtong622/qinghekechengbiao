import 'dart:convert';

enum HolidayDayKind { regular, weekend, rest, adjustedWorkday }

/// Exceptions announced in the Chinese public-holiday calendar for one year.
/// Ordinary weekends are never silently treated as school holidays.
class ChinaHolidayCalendar {
  ChinaHolidayCalendar._(this.year, this._exceptions);

  factory ChinaHolidayCalendar.fromJson(String source, {required int year}) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> || decoded['code'] != 0) {
      throw const FormatException('节假日数据格式无效');
    }
    final entries = decoded['holiday'];
    if (entries is! Map<String, dynamic>) {
      throw const FormatException('节假日数据缺少日期列表');
    }
    final exceptions = <String, HolidayDayKind>{};
    for (final entry in entries.entries) {
      final value = entry.value;
      final key = entry.key;
      if (!RegExp(r'^\d{2}-\d{2}$').hasMatch(key) ||
          value is! Map<String, dynamic>) {
        continue;
      }
      final month = int.parse(key.substring(0, 2));
      final day = int.parse(key.substring(3));
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) continue;
      final name = value['name']?.toString() ?? '';
      if (value['holiday'] == false) {
        exceptions[key] = HolidayDayKind.adjustedWorkday;
      } else if (value['holiday'] == true &&
          !RegExp(r'^周[一二三四五六日天]$').hasMatch(name)) {
        exceptions[key] = HolidayDayKind.rest;
      }
    }
    return ChinaHolidayCalendar._(year, Map.unmodifiable(exceptions));
  }

  final int year;
  final Map<String, HolidayDayKind> _exceptions;

  bool get hasExceptions => _exceptions.isNotEmpty;

  HolidayDayKind kindFor(DateTime date) {
    if (date.year == year) {
      final key =
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final exception = _exceptions[key];
      if (exception != null) return exception;
    }
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday
        ? HolidayDayKind.weekend
        : HolidayDayKind.regular;
  }

  bool shouldSilence(DateTime date) => kindFor(date) == HolidayDayKind.rest;
}
