import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/reminders/data/native_alarm_scheduler.dart';
import 'package:qinghe_timetable/features/reminders/domain/reminder_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.qinghe.timetable/alarms');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'replaceAll') {
            return {
              'ids': [12],
              'nextId': 12,
              'nextAt': 1000,
            };
          }
          return {
            'notificationsAllowed': true,
            'exactAlarmsAllowed': true,
            'fullScreenAllowed': false,
            'batteryUnrestricted': false,
          };
        });
  });
  test('legacy alarms are retired before publishing native cards', () async {
    var retired = false;
    final scheduler = NativeAlarmScheduler(
      migrateLegacy: () async {
        expect(calls, isEmpty);
        retired = true;
      },
    );
    await scheduler.replaceAll([]);
    expect(retired, isTrue);
  });
  test(
    'native silence and disabled snooze are explicit with course details',
    () async {
      final scheduler = NativeAlarmScheduler(migrateLegacy: () async {});
      await scheduler.replaceAll([
        CourseReminder(
          id: 12,
          scheduledAt: DateTime(2026),
          title: '数学',
          body: 'A302',
          payload: 'math',
          sound: RingtoneSelection.none,
          snoozeEnabled: false,
          maxRings: 5,
          vibration: VibrationSelection.none,
          courseName: '数学',
          teacher: '陈老师',
          room: 'A302',
          timeLabel: '08:25–10:00',
        ),
      ]);
      final payload = (calls.single.arguments as List).single as Map;
      expect(payload['silent'], isTrue);
      expect(payload['limit'], 1);
      expect(payload['snoozeEnabled'], isFalse);
      expect(payload['vibration'], 'none');
      expect(payload['courseName'], '数学');
      expect(payload['teacher'], '陈老师');
      expect(payload['timeLabel'], '08:25–10:00');
    },
  );
  test('native payload contains deadline and repetition policy', () async {
    final scheduler = NativeAlarmScheduler(migrateLegacy: () async {});
    final report = await scheduler.replaceAll([
      CourseReminder(
        id: 12,
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(1000),
        classStartAt: DateTime.fromMillisecondsSinceEpoch(2000),
        occurrenceKey: 'unique',
        title: '数学',
        body: 'A302',
        payload: 'math',
        snoozeMinutes: 15,
        maxRings: 5,
      ),
    ]);
    final payload = (calls.single.arguments as List).single as Map;
    expect(report.nextId, 12);
    expect(payload['deadline'], 2000);
    expect(payload['interval'], 15);
    expect(payload['limit'], 5);
    expect(report.registeredIds, {12});
    expect((await scheduler.permissionStatus()).fullScreenAllowed, isFalse);
  });
  test(
    'active audio selection declares no-sound and independent vibration',
    () async {
      final scheduler = NativeAlarmScheduler(migrateLegacy: () async {});
      expect(
        await scheduler.configureAlert(
          RingtoneSelection.none,
          VibrationSelection.gentle,
        ),
        isFalse,
      );
      final payload = calls.single.arguments as Map;
      expect(calls.single.method, 'configureAlert');
      expect(payload['silent'], isTrue);
      expect(payload['vibration'], 'gentle');
      expect(payload['name'], '无铃声');
    },
  );
  test(
    'native unreadable ringtone fallback is surfaced to the settings page',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {'soundFallback': true},
          );
      expect(
        await NativeAlarmScheduler(
          migrateLegacy: () async {},
        ).configureAlert(RingtoneSelection.chime, VibrationSelection.none),
        isTrue,
      );
    },
  );
  test(
    'platform registration errors are surfaced, never reported successful',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'exact_denied'),
          );
      final scheduler = NativeAlarmScheduler(migrateLegacy: () async {});
      expect(() => scheduler.replaceAll([]), throwsA(isA<PlatformException>()));
    },
  );
}
