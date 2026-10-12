import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/widgets/presentation/widget_settings_page.dart';

void main() {
  testWidgets(
    'shows manual installation steps without unreliable add actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: WidgetSettingsPage(onRefresh: () async {})),
      );
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('手动添加教程'), findsOneWidget);
      expect(find.textContaining('长按桌面空白处'), findsOneWidget);
      expect(find.textContaining('找到“青禾课表”'), findsOneWidget);
      expect(find.textContaining('拖到桌面空白位置'), findsOneWidget);
    },
  );

  testWidgets('refresh prevents duplicate requests and recovers from failure', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WidgetSettingsPage(
          onRefresh: () {
            calls++;
            return calls == 1 ? pending.future : Future.value();
          },
        ),
      ),
    );
    final refresh = find.byType(FilledButton);
    await tester.tap(refresh);
    await tester.pump();
    expect(tester.widget<FilledButton>(refresh).onPressed, isNull);
    pending.completeError(StateError('refresh'));
    await tester.pumpAndSettle();
    expect(find.text('刷新失败，请稍后重试'), findsOneWidget);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.text('组件数据已更新'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
