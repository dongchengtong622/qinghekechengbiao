import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/data/holiday_calendar_service.dart';

const _builtIn = '{"code":0,"holiday":{"10-01":{"holiday":true,"name":"国庆节"}}}';
const _updated =
    '{"code":0,"holiday":{"10-01":{"holiday":true,"name":"国庆节"},"10-02":{"holiday":true,"name":"国庆节"}}}';

void main() {
  test('uses validated online data and caches it for offline launch', () async {
    String? saved;
    final online = HolidayCalendarService(
      readBundled: (_) async => _builtIn,
      readCache: (_) async => null,
      writeCache: (_, value) async => saved = value,
      fetchOnline: (_) async => _updated,
    );
    final first = await online.load(2026);
    expect(first.shouldSilence(DateTime(2026, 10, 2)), isTrue);
    expect(saved, _updated);

    final offline = HolidayCalendarService(
      readBundled: (_) async => _builtIn,
      readCache: (_) async => saved,
      writeCache: (_, __) async {},
      fetchOnline: (_) async => throw StateError('offline'),
    );
    expect(
      (await offline.load(2026)).shouldSilence(DateTime(2026, 10, 2)),
      isTrue,
    );
  });

  test(
    'keeps bundled holidays when online data is empty or unavailable',
    () async {
      final service = HolidayCalendarService(
        readBundled: (_) async => _builtIn,
        readCache: (_) async => null,
        writeCache: (_, __) async {},
        fetchOnline: (_) async => '{"code":0,"holiday":{}}',
      );
      expect(
        (await service.load(2026)).shouldSilence(DateTime(2026, 10, 1)),
        isTrue,
      );
    },
  );
}
