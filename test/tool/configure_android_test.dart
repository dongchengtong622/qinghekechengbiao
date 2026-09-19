import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/configure_android.dart' as configurator;

void main() {
  test('configures the generated Android project idempotently', () {
    final temporary = Directory.systemTemp.createTempSync('qinghe-android-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final app = Directory('${temporary.path}/app')..createSync(recursive: true);
    final main = Directory('${app.path}/src/main')..createSync(recursive: true);
    final gradle = File('${app.path}/build.gradle.kts')
      ..writeAsStringSync('''
android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    defaultConfig {
        minSdk = flutter.minSdkVersion
    }
}

flutter {
}
''');
    final manifest = File('${main.path}/AndroidManifest.xml')
      ..writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="qinghe_timetable">
    </application>
</manifest>
''');

    configurator.configureAndroid(temporary);
    final firstGradle = gradle.readAsStringSync();
    final firstManifest = manifest.readAsStringSync();
    configurator.configureAndroid(temporary);

    expect(gradle.readAsStringSync(), firstGradle);
    expect(manifest.readAsStringSync(), firstManifest);
    expect(firstGradle, contains('minSdk = 24'));
    expect(firstGradle, contains('JavaVersion.VERSION_17'));
    expect(firstGradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(firstGradle, contains('coreLibraryDesugaring('));
    expect(firstManifest, contains('android.permission.INTERNET'));
    expect(firstManifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(firstManifest, contains('android.permission.VIBRATE'));
    expect(
      firstManifest,
      contains('android.permission.RECEIVE_BOOT_COMPLETED'),
    );
    expect(firstManifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(firstManifest, contains('android:label="青禾课表"'));
    expect(firstManifest, contains('ScheduledNotificationBootReceiver'));
  });
}
