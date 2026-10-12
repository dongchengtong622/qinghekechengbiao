// Test-only entry point. Production builds continue to use lib/main.dart.
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:qinghe_timetable/main.dart' as application;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SchedulerBinding.instance.addTimingsCallback((frames) {
    // Printed once per reported batch, outside the frame being measured.
    debugPrint(
      'QH_FRAME_BATCH ${jsonEncode([
        for (final f in frames) {'buildUs': f.buildDuration.inMicroseconds, 'rasterUs': f.rasterDuration.inMicroseconds, 'totalUs': f.totalSpan.inMicroseconds},
      ])}',
    );
  });
  application.main();
}
