import 'dart:io';
import 'dart:typed_data';

void main(List<String> arguments) {
  configureAndroid(Directory(arguments.isEmpty ? 'android' : arguments.first));
}

void configureAndroid(
  Directory androidDirectory, {
  Directory? sourceDirectory,
}) {
  _configureGradle(File('${androidDirectory.path}/app/build.gradle.kts'));
  _configureManifest(
    File('${androidDirectory.path}/app/src/main/AndroidManifest.xml'),
  );
  _copyNotificationSounds(
    sourceDirectory ?? Directory.current,
    Directory('${androidDirectory.path}/app/src/main/res/raw'),
  );
  _installRingtoneBridge(Directory.current, androidDirectory);
  _writeResourceKeepFile(androidDirectory);
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
  final generated = <String, double>{
    'qinghe_morning.wav': 523.25,
    'qinghe_xylophone.wav': 659.25,
    'qinghe_water.wav': 783.99,
    'qinghe_bell.wav': 880.0,
  };
  for (final entry in generated.entries) {
    _writeTone(File('${target.path}/${entry.key}'), entry.value);
  }
}

void _writeTone(File file, double frequency) {
  const sampleRate = 16000;
  const samples = 6400;
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
    final phase = 2 * 3.141592653589793 * frequency * index / sampleRate;
    final envelope = 1 - index / samples;
    write16((12000 * envelope * _sin(phase)).round());
  }
  file.writeAsBytesSync(bytes.takeBytes());
}

double _sin(double value) {
  var x = value % (2 * 3.141592653589793);
  if (x > 3.141592653589793) x -= 2 * 3.141592653589793;
  final x2 = x * x;
  return x * (1 - x2 / 6 + x2 * x2 / 120 - x2 * x2 * x2 / 5040);
}

void _installRingtoneBridge(Directory source, Directory androidDirectory) {
  final target = Directory(
    '${androidDirectory.path}/app/src/main/kotlin/com/qinghe/qinghe_timetable',
  )..createSync(recursive: true);
  for (final name in ['MainActivity.kt', 'RingtoneProvider.kt']) {
    File('${source.path}/tool/android/$name').copySync('${target.path}/$name');
  }
}

void _writeResourceKeepFile(Directory androidDirectory) {
  final file = File(
    '${androidDirectory.path}/app/src/main/res/raw/keep.xml',
  );
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
  ];
  for (final permission in permissions.reversed) {
    final declaration = '    <uses-permission android:name="$permission" />';
    if (!source.contains(declaration)) {
      source = source.replaceFirst('>\n', '>\n$declaration\n');
    }
  }
  source = source.replaceFirst(
    RegExp(r'android:label="[^"]*"'),
    'android:label="青禾课表"',
  );
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
    source = source.replaceFirst(
      '    </application>',
      '$receivers    </application>',
    );
  }
  const provider = '''
        <provider
            android:name=".RingtoneProvider"
            android:authorities="com.qinghe.timetable.ringtones"
            android:exported="true"
            android:grantUriPermissions="true" />
''';
  if (!source.contains('RingtoneProvider')) {
    source = source.replaceFirst(
      '    </application>',
      '$provider    </application>',
    );
  }
  file.writeAsStringSync(source);
}
