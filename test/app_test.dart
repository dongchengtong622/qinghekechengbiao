import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/app.dart';
import 'package:qinghe_timetable/features/timetable/data/app_database.dart';

void main() {
  testWidgets('seeds and displays courses from the local database', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(QingheApp(database: database));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学英语'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
