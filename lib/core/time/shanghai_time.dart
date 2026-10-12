import 'package:timezone/data/latest_10y.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

abstract final class ShanghaiTime {
  static bool _initialized = false;
  static late final timezone.Location location;

  static void ensureInitialized() {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    location = timezone.getLocation('Asia/Shanghai');
    _initialized = true;
  }

  static timezone.TZDateTime now() {
    ensureInitialized();
    return timezone.TZDateTime.now(location);
  }

  static timezone.TZDateTime fromUtc(DateTime value) {
    ensureInitialized();
    return timezone.TZDateTime.from(value.toUtc(), location);
  }

  static timezone.TZDateTime dateTime(
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    ensureInitialized();
    return timezone.TZDateTime(location, year, month, day, hour, minute);
  }
}
