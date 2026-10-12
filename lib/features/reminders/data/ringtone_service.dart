import 'package:flutter/services.dart';

import '../domain/reminder_models.dart';

abstract interface class RingtoneService {
  Future<RingtoneSelection?> importLocal();

  Future<void> preview(RingtoneSelection sound);

  Future<void> stop();
}

class NativeRingtoneService implements RingtoneService {
  const NativeRingtoneService();

  static const _channel = MethodChannel('com.qinghe.timetable/ringtones');

  @override
  Future<RingtoneSelection?> importLocal() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'importLocal',
    );
    if (result == null) return null;
    final id = result['id'];
    final name = result['name'];
    final uri = result['contentUri'];
    if (id is! String || name is! String || uri is! String) {
      throw const FormatException('本地铃声结果无效');
    }
    return RingtoneSelection(id: id, name: name, contentUri: uri);
  }

  @override
  Future<void> preview(RingtoneSelection sound) {
    return _channel.invokeMethod<void>('preview', {
      'resourceName': sound.resourceName,
      'contentUri': sound.contentUri,
      'silent': sound.isSilent,
    });
  }

  Future<bool> isPlaying() async =>
      await _channel.invokeMethod<bool>('isPlaying') ?? false;

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

abstract interface class VibrationService {
  Future<bool> preview(VibrationSelection vibration);
  Future<void> stop();
}

class NativeVibrationService implements VibrationService {
  const NativeVibrationService();
  static const _channel = MethodChannel('com.qinghe.timetable/ringtones');
  @override
  Future<bool> preview(VibrationSelection vibration) async =>
      await _channel.invokeMethod<bool>('previewVibration', vibration.name) ??
      false;
  @override
  Future<void> stop() => _channel.invokeMethod<void>('stopVibration');
}
