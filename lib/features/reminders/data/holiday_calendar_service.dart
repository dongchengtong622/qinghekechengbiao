import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/china_holiday_calendar.dart';

typedef HolidayTextReader = Future<String?> Function(int year);
typedef HolidayTextWriter = Future<void> Function(int year, String source);
typedef HolidayTextFetcher = Future<String> Function(int year);

/// Returns validated annual holiday data, preferring a fresh online copy,
/// then a cached copy, then the annual calendar shipped with the application.
class HolidayCalendarService {
  HolidayCalendarService({
    HolidayTextReader? readBundled,
    HolidayTextReader? readCache,
    HolidayTextWriter? writeCache,
    HolidayTextFetcher? fetchOnline,
  }) : _readBundled = readBundled ?? _bundled,
       _readCache = readCache ?? _cached,
       _writeCache = writeCache ?? _save,
       _fetchOnline = fetchOnline ?? _fetch;

  final HolidayTextReader _readBundled;
  final HolidayTextReader _readCache;
  final HolidayTextWriter _writeCache;
  final HolidayTextFetcher _fetchOnline;
  final Map<int, ChinaHolidayCalendar> _memory = {};

  Future<ChinaHolidayCalendar> load(int year) async {
    final remembered = _memory[year];
    if (remembered != null) return remembered;

    var selected = ChinaHolidayCalendar.fromJson(
      '{"code":0,"holiday":{}}',
      year: year,
    );
    for (final reader in [_readBundled, _readCache]) {
      try {
        final source = await reader(year);
        if (source == null) continue;
        final candidate = ChinaHolidayCalendar.fromJson(source, year: year);
        if (candidate.hasExceptions) selected = candidate;
      } catch (_) {
        // Invalid or missing local data must not interrupt course reminders.
      }
    }
    try {
      final source = await _fetchOnline(year);
      final candidate = ChinaHolidayCalendar.fromJson(source, year: year);
      if (candidate.hasExceptions) {
        selected = candidate;
        await _writeCache(year, source);
      }
    } catch (_) {
      // Offline use is the main reason for shipping and caching calendars.
    }
    return _memory[year] = selected;
  }

  static Future<String?> _bundled(int year) async {
    if (year != 2026) return null;
    return rootBundle.loadString('assets/holidays/china_2026.json');
  }

  static Future<File> _cacheFile(int year) async {
    final dir = await getApplicationSupportDirectory();
    return File(
      '${dir.path}${Platform.pathSeparator}china_holidays_$year.json',
    );
  }

  static Future<String?> _cached(int year) async {
    final file = await _cacheFile(year);
    return file.existsSync() ? file.readAsString() : null;
  }

  static Future<void> _save(int year, String source) async {
    final file = await _cacheFile(year);
    await file.writeAsString(source, flush: true);
  }

  static Future<String> _fetch(int year) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(
            Uri.https('timor.tech', '/api/holiday/year/$year', {'week': 'Y'}),
          )
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const FormatException('节假日服务暂不可用');
      }
      return await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 4));
    } finally {
      client.close(force: true);
    }
  }
}
