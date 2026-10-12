import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'V1 Android delivery source has no recognition dependencies or model assets',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, isNot(contains('onnxruntime')));
      expect(gradle, isNot(contains('text-recognition')));
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('image_picker:')));
      expect(pubspec, isNot(contains('image_cropper:')));
      expect(pubspec, contains('excel_plus:'));
      expect(pubspec, contains('file_picker:'));
      expect(Directory('assets/ocr').existsSync(), isFalse);
      expect(
        Directory('android/app/src/main/assets/ocr').existsSync(),
        isFalse,
      );
      final activity = File('tool/android/MainActivity.kt').readAsStringSync();
      expect(activity, isNot(contains('ImageRecognitionBridge')));
      expect(activity, contains('AlarmBridge'));
    },
  );
}
