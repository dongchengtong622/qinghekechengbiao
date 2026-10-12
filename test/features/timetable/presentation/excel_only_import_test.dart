import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_import_page.dart';

void main() {
  Widget page(Future<dynamic> Function() load) => MaterialApp(
    home: TimetableImportPage(
      loadPreview: () async => await load(),
      onPreview: (_) async => const ImportSummary(
        inserted: 0,
        updated: 0,
        removed: 0,
        warnings: [],
      ),
      onImport: (_) async => const ImportSummary(
        inserted: 0,
        updated: 0,
        removed: 0,
        warnings: [],
      ),
    ),
  );
  testWidgets(
    'V1 import explains Excel only and offers no picture or camera entry',
    (tester) async {
      await tester.pumpWidget(page(() async => null));
      expect(find.text('选择 Excel 文件'), findsOneWidget);
      expect(find.text('下载 Excel 模板'), findsOneWidget);
      expect(find.textContaining(RegExp('图片|截图|拍照|相册')), findsNothing);
      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    },
  );
  testWidgets('cancelling Excel selection stays on import without confirming', (
    tester,
  ) async {
    await tester.pumpWidget(page(() async => null));
    await tester.tap(find.text('选择 Excel 文件'));
    await tester.pumpAndSettle();
    expect(find.text('导入课表'), findsOneWidget);
    expect(find.text('确认导入'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Excel pending selection is guarded and never invokes picture status',
    (tester) async {
      final pending = Completer<dynamic>();
      var requests = 0;
      await tester.pumpWidget(
        page(() {
          requests++;
          return pending.future;
        }),
      );
      await tester.tap(find.text('选择 Excel 文件'));
      await tester.pump();
      expect(find.text('正在读取…'), findsOneWidget);
      expect(find.textContaining('图片'), findsNothing);
      expect(requests, 1);
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('选择 Excel 文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
