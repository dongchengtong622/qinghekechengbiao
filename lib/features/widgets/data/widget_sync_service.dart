import 'package:flutter/services.dart';
import '../domain/widget_snapshot.dart';

class WidgetSyncService {
  static const channel = MethodChannel('com.qinghe.timetable/widgets');
  Future<void> save(WidgetSnapshot snapshot) async {
    try {
      await channel.invokeMethod<void>('saveSnapshot', snapshot.encode());
    } on MissingPluginException {
      /* Non-Android/test environment. */
    }
  }

  Future<bool> pin(String kind) async {
    try {
      return await channel.invokeMethod<bool>('pin', kind) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Map<Object?, Object?>?> initialLink() async {
    try {
      return await channel.invokeMapMethod<Object?, Object?>('initialLink');
    } on MissingPluginException {
      return null;
    }
  }
}
