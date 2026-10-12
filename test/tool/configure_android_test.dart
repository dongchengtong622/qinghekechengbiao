import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/configure_android.dart' as configurator;

void main() {
  test('Windows CRLF manifest permissions remain outside application', () {
    final dir = Directory.systemTemp.createTempSync('qinghe-crlf-');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/app/src/main').createSync(recursive: true);
    File('${dir.path}/app/build.gradle.kts').writeAsStringSync(
      'android {\n compileOptions {}\n defaultConfig {}\n}\nflutter {}',
    );
    final manifest = File('${dir.path}/app/src/main/AndroidManifest.xml');
    manifest.writeAsStringSync(
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\r\n    <application android:label="app">\r\n    </application>\r\n</manifest>',
    );
    configurator.configureAndroid(dir);
    configurator.configureAndroid(dir);
    final content = manifest.readAsStringSync();
    expect(
      content.indexOf('android.permission.WAKE_LOCK'),
      lessThan(content.indexOf('<application')),
    );
  });

  test('release metadata exposes every requested Android artifact', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final workflow = File(
      '.github/workflows/flutter-ci.yml',
    ).readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, contains('version: 1.0.5+18'));
    expect(workflow, contains('flutter build apk --release'));
    expect(
      workflow,
      contains('flutter build apk --release --target-platform android-arm64'),
    );
    expect(workflow, contains('flutter build appbundle --release'));
    expect(workflow, contains('qinghe-timetable-1.0.5-universal.apk'));
    expect(workflow, contains('qinghe-timetable-1.0.5-arm64.apk'));
    expect(workflow, contains('qinghe-timetable-1.0.5.aab'));
    expect(
      readme,
      contains(
        'flutter create --platforms=android --org com.qinghe '
        '--project-name qinghe_timetable .platform_template',
      ),
    );
    expect(readme, contains('dart run tool/configure_android.dart'));
    expect(readme, contains('dart run build_runner build'));
  });

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
    buildTypes { release {} }
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
    final source = Directory('${temporary.path}/source');
    final sounds = Directory('${source.path}/assets/notification_sounds')
      ..createSync(recursive: true);
    for (final name in [
      'qinghe_chime.wav',
      'qinghe_soft.wav',
      'qinghe_alert.wav',
    ]) {
      File('${sounds.path}/$name').writeAsBytesSync([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x41,
        0x56,
        0x45,
        1,
        2,
        3,
      ]);
    }

    configurator.configureAndroid(temporary, sourceDirectory: source);
    final firstGradle = gradle.readAsStringSync();
    final firstManifest = manifest.readAsStringSync();
    configurator.configureAndroid(temporary, sourceDirectory: source);

    expect(gradle.readAsStringSync(), firstGradle);
    expect(manifest.readAsStringSync(), firstManifest);
    expect(firstGradle, contains('minSdk = 24'));
    expect(firstGradle, contains('JavaVersion.VERSION_17'));
    expect(firstGradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(firstGradle, contains('coreLibraryDesugaring('));
    expect(firstGradle, contains('proguardFiles("proguard-rules.pro")'));
    expect(firstGradle, isNot(contains('text-recognition')));
    expect(firstGradle, isNot(contains('onnxruntime')));
    expect(firstGradle, contains('testImplementation("junit:junit:4.13.2")'));
    expect(firstManifest, isNot(contains('UCropActivity')));
    expect(Directory('${main.path}/assets/ocr').existsSync(), isFalse);
    expect(
      File(
        '${main.path}/kotlin/com/qinghe/qinghe_timetable/ImageRecognitionBridge.kt',
      ).existsSync(),
      isFalse,
    );
    expect(
      File('${app.path}/proguard-rules.pro').readAsStringSync(),
      File('tool/android/proguard-rules.pro').readAsStringSync(),
    );
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
    expect(firstManifest, contains('RingtoneProvider'));
    expect(firstManifest, contains('.NextClassWidgetProvider'));
    expect(firstManifest, contains('.TodayClassesWidgetProvider'));
    expect(
      File('${main.path}/res/xml/widget_next_class_info.xml').existsSync(),
      isTrue,
    );
    expect(
      File(
        '${main.path}/kotlin/com/qinghe/qinghe_timetable/CourseWidgets.kt',
      ).readAsStringSync(),
      contains('WidgetRuntime'),
    );
    expect(
      File(
        '${main.path}/kotlin/com/qinghe/qinghe_timetable/MainActivity.kt',
      ).readAsStringSync(),
      contains('com.qinghe.timetable/widgets'),
    );
    expect(
      File(
        '${main.path}/kotlin/com/qinghe/qinghe_timetable/MainActivity.kt',
      ).existsSync(),
      isTrue,
    );
    expect(File('${main.path}/res/raw/keep.xml').existsSync(), isTrue);
    expect(
      File('${main.path}/res/raw/qinghe_morning.wav').lengthSync(),
      greaterThan(320000),
    );
    for (final name in [
      'qinghe_chime.wav',
      'qinghe_soft.wav',
      'qinghe_alert.wav',
    ]) {
      expect(
        File('${main.path}/res/raw/$name').readAsBytesSync().take(4),
        orderedEquals([0x52, 0x49, 0x46, 0x46]),
      );
    }
    for (final name in [
      'qinghe_morning.wav',
      'qinghe_xylophone.wav',
      'qinghe_water.wav',
      'qinghe_bell.wav',
    ]) {
      expect(
        File('${main.path}/res/raw/$name').readAsBytesSync().take(4),
        orderedEquals([0x52, 0x49, 0x46, 0x46]),
      );
    }
  });

  test('rejects notification sounds that are not RIFF WAVE files', () {
    final temporary = Directory.systemTemp.createTempSync('qinghe-sound-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final app = Directory('${temporary.path}/app')..createSync(recursive: true);
    final main = Directory('${app.path}/src/main')..createSync(recursive: true);
    File('${app.path}/build.gradle.kts').writeAsStringSync('''
android { compileOptions {} defaultConfig {} }
flutter {}
''');
    File('${main.path}/AndroidManifest.xml').writeAsStringSync('''
<manifest><application android:label="qinghe_timetable"></application></manifest>
''');
    final source = Directory('${temporary.path}/source');
    final sounds = Directory('${source.path}/assets/notification_sounds')
      ..createSync(recursive: true);
    for (final name in [
      'qinghe_chime.wav',
      'qinghe_soft.wav',
      'qinghe_alert.wav',
    ]) {
      File('${sounds.path}/$name').writeAsBytesSync([1, 2, 3]);
    }

    expect(
      () => configurator.configureAndroid(temporary, sourceDirectory: source),
      throwsA(isA<FormatException>()),
    );
  });
}



