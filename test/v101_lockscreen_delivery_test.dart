import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/configure_android.dart' as configurator;

void main() {
  test('generated Android alarm supports system full-screen delivery', () {
    final dir = Directory.systemTemp.createTempSync('qinghe-lockscreen-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/app/src/main').createSync(recursive: true);
    File('${dir.path}/app/build.gradle.kts').writeAsStringSync(
      'android {\n compileOptions {}\n defaultConfig {}\n}\nflutter {}',
    );
    final manifest = File('${dir.path}/app/src/main/AndroidManifest.xml')
      ..writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="app"></application></manifest>',
      );
    configurator.configureAndroid(dir);
    configurator.configureAndroid(dir);
    expect(
      RegExp(
        'android.permission.USE_FULL_SCREEN_INTENT',
      ).allMatches(manifest.readAsStringSync()).length,
      1,
    );
    final native =
        '${dir.path}/app/src/main/kotlin/com/qinghe/qinghe_timetable';
    final service = File('$native/CourseAlarmService.kt').readAsStringSync();
    expect(service, contains('setFullScreenIntent(automaticActivity, true)'));
    expect(service, isNot(contains('setTimeoutAfter')));
    expect(service, isNot(contains('cancel(published.remove')));
    expect(service, isNot(contains('published.values.forEach')));
    final activity = File('$native/CourseAlarmActivity.kt').readAsStringSync();
    expect(activity, contains('automaticDelivery'));
    expect(activity, contains('shouldShowFullScreen'));
    expect(activity, contains('eventSnapshot'));
    expect(service, contains('eventSnapshot'));
    expect(service, contains('Notification.CATEGORY_ALARM'));
    expect(service, contains('setDeleteIntent'));
    expect(service, contains('GROUP_ALERT_SUMMARY'));
    final receiver = File('$native/CourseAlarmReceiver.kt').readAsStringSync();
    expect(receiver, contains('"collapse"'));
    expect(receiver, contains('collapsed = true'));
    expect(service, contains('setCustomContentView'));
    expect(service, contains('setCustomBigContentView'));
    for (final field in [
      'reminder_compact_time',
      'reminder_compact_room',
      'reminder_compact_teacher',
    ]) {
      expect(service, contains(field));
    }
    expect(activity, contains('isKeyguardLocked'));
    expect(activity, contains('isInteractive'));
    expect(
      File('$native/CourseAlarmReceiver.kt').readAsStringSync(),
      contains('shouldShowFullScreen'),
    );

    expect(
      File('$native/AlarmBridge.kt').readAsStringSync(),
      contains('canUseFullScreenIntent()'),
    );
    expect(
      File('$native/SettingsNavigator.kt').readAsStringSync(),
      contains('ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT'),
    );
  });
}
