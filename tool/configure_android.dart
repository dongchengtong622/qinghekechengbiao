import 'dart:io';

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
  file.writeAsStringSync(source);
}
