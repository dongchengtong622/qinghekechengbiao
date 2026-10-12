import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

void main(List<String> arguments) {
  configureAndroid(Directory(arguments.isEmpty ? 'android' : arguments.first));
}

void configureAndroid(
  Directory androidDirectory, {
  Directory? sourceDirectory,
}) {
  final gradle = File('${androidDirectory.path}/app/build.gradle.kts');
  _configureGradle(gradle);
  File('${androidDirectory.path}/app/proguard-rules.pro').writeAsStringSync(
    File('tool/android/proguard-rules.pro').readAsStringSync(),
  );
  _configureManifest(
    File('${androidDirectory.path}/app/src/main/AndroidManifest.xml'),
  );
  _copyNotificationSounds(
    sourceDirectory ?? Directory.current,
    Directory('${androidDirectory.path}/app/src/main/res/raw'),
  );
  _copyTree(
    Directory('tool/android/res'),
    Directory('${androidDirectory.path}/app/src/main/res'),
  );
  _installRingtoneBridge(Directory.current, androidDirectory);
  _writeResourceKeepFile(androidDirectory);
  final icons = Directory('tool/android/icons');
  if (icons.existsSync()) {
    for (final file in icons.listSync(recursive: true).whereType<File>()) {
      final relative = file.path.substring(icons.path.length + 1);
      final target = File(
        '${androidDirectory.path}/app/src/main/res/$relative',
      );
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    }
  }
  final tests = Directory(
    '${androidDirectory.path}/app/src/test/kotlin/com/qinghe/qinghe_timetable',
  )..createSync(recursive: true);
  for (final file in Directory(
    'tool/android/test',
  ).listSync().whereType<File>()) {
    file.copySync('${tests.path}/${file.uri.pathSegments.last}');
  }
}

void _copyTree(Directory source, Directory target) {
  if (!source.existsSync()) return;
  for (final file in source.listSync(recursive: true).whereType<File>()) {
    final relative = file.path.substring(source.path.length + 1);
    final destination = File('${target.path}/$relative');
    destination.parent.createSync(recursive: true);
    if (file.absolute.path != destination.absolute.path) {
      file.copySync(destination.path);
    }
  }
}

void _copyNotificationSounds(Directory sourceDirectory, Directory target) {
  final source = Directory(
    '${sourceDirectory.path}/assets/notification_sounds',
  );
  target.createSync(recursive: true);
  for (final name in [
    'qinghe_chime.wav',
    'qinghe_soft.wav',
    'qinghe_alert.wav',
  ]) {
    final file = File('${source.path}/$name');
    final bytes = file.readAsBytesSync();
    final isWave =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45;
    if (!isWave) {
      throw FormatException('通知铃声不是有效的 RIFF/WAVE 文件：$name');
    }
    file.copySync('${target.path}/$name');
  }
  final generated =
      <String, ({double base, double beat, int voice, List<int?> notes})>{
        'qinghe_chime.wav': (
          base: 523.25,
          beat: .7,
          voice: 0,
          notes: [0, 7, 12, 7, 4, 7, 12, null],
        ),
        'qinghe_soft.wav': (
          base: 392,
          beat: .8,
          voice: 1,
          notes: [0, 2, 4, 7, 4, 2, 0, null],
        ),
        'qinghe_alert.wav': (
          base: 587.33,
          beat: .35,
          voice: 2,
          notes: [0, 4, 7, 4, 9, 7, 4, null],
        ),
        'qinghe_morning.wav': (
          base: 440,
          beat: .55,
          voice: 1,
          notes: [0, 4, 7, 12, 9, 7, 4, 7],
        ),
        'qinghe_xylophone.wav': (
          base: 659.25,
          beat: .45,
          voice: 3,
          notes: [0, 7, 5, 12, 7, 4, 2, null],
        ),
        'qinghe_water.wav': (
          base: 523.25,
          beat: .9,
          voice: 4,
          notes: [12, 7, 4, 0, null, 9, 4, null],
        ),
        'qinghe_bell.wav': (
          base: 349.23,
          beat: 1.0,
          voice: 0,
          notes: [0, 7, 4, 9, 7, 2, 4, null],
        ),
      };
  for (final entry in generated.entries) {
    _writeTone(File('${target.path}/${entry.key}'), entry.value);
  }
}

void _writeTone(
  File file,
  ({double base, double beat, int voice, List<int?> notes}) pattern,
) {
  const sampleRate = 16000;
  const samples = sampleRate * 16;
  final dataSize = samples * 2;
  final bytes = BytesBuilder();
  void write16(int value) => bytes.add([value & 255, (value >> 8) & 255]);
  void write32(int value) => bytes.add([
    value & 255,
    (value >> 8) & 255,
    (value >> 16) & 255,
    (value >> 24) & 255,
  ]);
  bytes.add('RIFF'.codeUnits);
  write32(36 + dataSize);
  bytes.add('WAVEfmt '.codeUnits);
  write32(16);
  write16(1);
  write16(1);
  write32(sampleRate);
  write32(sampleRate * 2);
  write16(2);
  write16(16);
  bytes.add('data'.codeUnits);
  write32(dataSize);
  for (var index = 0; index < samples; index++) {
    final time = index / sampleRate;
    final beat = (time / pattern.beat).floor();
    final local = time % pattern.beat;
    final offset = pattern.notes[beat % pattern.notes.length];
    final note = offset == null ? 0.0 : pattern.base * math.pow(2, offset / 12);
    final attack = (local / .025).clamp(0.0, 1.0);
    final release = ((pattern.beat - local) / .12).clamp(0.0, 1.0);
    final envelope =
        attack * release * math.exp(-local * (pattern.voice == 1 ? 1.4 : 3.2));
    final phase = 2 * math.pi * note * local;
    final fundamental = math.sin(phase);
    final tone = switch (pattern.voice) {
      1 => fundamental + .08 * math.sin(phase * 2),
      2 => fundamental + .38 * math.sin(phase * 2) + .2 * math.sin(phase * 3),
      3 => fundamental + .55 * math.sin(phase * 2) + .22 * math.sin(phase * 4),
      4 => fundamental + .3 * math.sin(phase * 2.01),
      _ => fundamental + .24 * math.sin(phase * 2) + .1 * math.sin(phase * 3),
    };
    final bass = offset == null
        ? 0.0
        : math.sin(2 * math.pi * pattern.base * .5 * time) * .08;
    final fade =
        (time / .05).clamp(0.0, 1.0) * ((16 - time) / .2).clamp(0.0, 1.0);
    write16(
      (10500 * (tone * envelope + bass) * fade).round().clamp(-32768, 32767),
    );
  }
  file.writeAsBytesSync(bytes.toBytes());
}

void _installRingtoneBridge(Directory source, Directory androidDirectory) {
  final target = Directory(
    '${androidDirectory.path}/app/src/main/kotlin/com/qinghe/qinghe_timetable',
  )..createSync(recursive: true);
  for (final name in [
    'MainActivity.kt',
    'CourseWidgets.kt',
    'WidgetSnapshotLogic.kt',
    'LegacyImportCleanup.kt',
    'RingtoneProvider.kt',
    'AlarmPolicy.kt',
    'AlarmJournal.kt',
    'AlarmStore.kt',
    'SerialAlarmExecutor.kt',
    'AlarmBridge.kt',
    'SettingsNavigator.kt',
    'AlertChannelRegistry.kt',
    'CourseAlarmReceiver.kt',
    'CourseAlarmService.kt',
    'CourseAlarmActivity.kt',
  ]) {
    File('${source.path}/tool/android/$name').copySync('${target.path}/$name');
  }
}

void _writeResourceKeepFile(Directory androidDirectory) {
  final file = File('${androidDirectory.path}/app/src/main/res/raw/keep.xml');
  file.writeAsStringSync(
    '<resources xmlns:tools="http://schemas.android.com/tools" '
    'tools:keep="@raw/qinghe_*,@mipmap/ic_launcher" />',
  );
}

void _configureGradle(File file) {
  var source = file.readAsStringSync();
  source = source
      .replaceAll('JavaVersion.VERSION_11', 'JavaVersion.VERSION_17')
      .replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = 24');
  if (!source.contains('qingheCompactApk')) {
    source = source.replaceFirst('android {', '''android {
    // Compact APK is opt-in; default builds retain directly loadable libraries.
    packaging {
        jniLibs {
            useLegacyPackaging = providers.gradleProperty("qingheCompactApk").orNull == "true"
        }
    }
''');
  }
  if (!source.contains('isCoreLibraryDesugaringEnabled = true')) {
    source = source.replaceFirst(
      'compileOptions {',
      'compileOptions {\n        isCoreLibraryDesugaringEnabled = true',
    );
  }
  if (!source.contains('multiDexEnabled = true')) {
    source = source.replaceFirst(
      'defaultConfig {',
      'defaultConfig {\n        multiDexEnabled = true',
    );
  }
  if (!source.contains('coreLibraryDesugaring(')) {
    source = source.replaceFirst('\nflutter {', '''

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {''');
  }
  if (!source.contains('proguardFiles("proguard-rules.pro")')) {
    source = source.replaceFirst(
      'release {',
      'release {\n            proguardFiles("proguard-rules.pro")',
    );
  }
  if (!source.contains('testImplementation("junit:junit:4.13.2")')) {
    source = source.replaceFirst(
      'dependencies {',
      'dependencies {\n    testImplementation("junit:junit:4.13.2")',
    );
  }
  if (!source.contains('org.json:json')) {
    source = source.replaceFirst(
      'dependencies {',
      'dependencies {\n    testImplementation("org.json:json:20240303")',
    );
  }
  file.writeAsStringSync(source);
}

void _configureManifest(File file) {
  var source = file.readAsStringSync();
  const permissions = [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.VIBRATE',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    'android.permission.WAKE_LOCK',
    'android.permission.USE_FULL_SCREEN_INTENT',
  ];
  // Normalize line endings before inserting generated XML blocks.
  source = source.replaceAll('\r\n', '\n');
  for (final permission in permissions) {
    source = source.replaceAll(
      RegExp(
        '^[ \t]*<uses-permission\\s+android:name="${RegExp.escape(permission)}"\\s*/>[ \t]*\n?',
        multiLine: true,
      ),
      '',
    );
  }
  final declarations = permissions
      .map((p) => '    <uses-permission android:name="$p" />')
      .join('\n');
  source = source.replaceFirstMapped(
    RegExp(r'<manifest\b[^>]*>'),
    (m) => '${m[0]}\n$declarations',
  );
  source = source.replaceFirst(
    RegExp(r'android:label="[^"]*"'),
    'android:label="青禾课表"',
  );
  for (final pair in {
    'NextClassWidgetProvider': 'widget_next_class_info',
    'TodayClassesWidgetProvider': 'widget_today_classes_info',
  }.entries) {
    if (!source.contains('android:name=".${pair.key}"')) {
      source = source.replaceFirst(
        '</application>',
        '''<receiver android:name=".${pair.key}" android:label="青禾课表 · ${pair.key == 'NextClassWidgetProvider' ? '下一节课' : '今日课程'}" android:exported="true">
        <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.TIME_SET"/><action android:name="android.intent.action.TIMEZONE_CHANGED"/><action android:name="android.intent.action.MY_PACKAGE_REPLACED"/></intent-filter>
        <meta-data android:name="android.appwidget.provider" android:resource="@xml/${pair.value}"/></receiver></application>''',
      );
    }
  }
  const receivers = '''
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
            android:exported="false" />
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
''';
  if (!source.contains('ScheduledNotificationReceiver')) {
    source = source.replaceFirst('</application>', '$receivers</application>');
  }
  const alarms = '''
        <receiver android:name=".CourseAlarmReceiver" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
                <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />
            </intent-filter>
        </receiver>
        <service android:name=".CourseAlarmService" android:exported="false" android:foregroundServiceType="mediaPlayback" />
        <activity android:name=".CourseAlarmActivity" android:exported="false" android:excludeFromRecents="true" android:theme="@android:style/Theme.Material.Light.NoActionBar" />
''';
  if (!source.contains('.CourseAlarmReceiver')) {
    source = source.replaceFirst('</application>', '$alarms</application>');
  }
  const provider = '''
        <provider
            android:name=".RingtoneProvider"
            android:authorities="com.qinghe.timetable.ringtones"
            android:exported="true"
            android:grantUriPermissions="true" />
''';
  if (!source.contains('RingtoneProvider')) {
    source = source.replaceFirst('</application>', '$provider</application>');
  }
  file.writeAsStringSync(source);
}
