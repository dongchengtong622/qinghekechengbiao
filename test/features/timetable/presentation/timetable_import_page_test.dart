import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/data/cdcas_kingo_importer.dart';
import 'package:qinghe_timetable/features/timetable/data/course_repository.dart';
import 'package:qinghe_timetable/features/timetable/presentation/timetable_import_page.dart';

void main() {
  test('school navigation policy only permits the official HTTPS host', () {
    expect(
      isAllowedSchoolUri(Uri.parse('https://jwc.cdcas.com/jsxsd/xskb/xskb_list.do')),
      isTrue,
    );
    expect(isAllowedSchoolUri(Uri.parse('http://jwc.cdcas.com/')), isFalse);
    expect(isAllowedSchoolUri(Uri.parse('https://example.com/')), isFalse);
    expect(isAllowedSchoolUri(Uri.parse('https://jwc.cdcas.com.evil.test/')), isFalse);
  });

  testWidgets('shows school, privacy notice, and import action', (tester) async {
    final controller = _FakeSchoolWebController('<html></html>');
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(
          importer: const CdcasKingoImporter(),
          onImport: _successfulImport,
          controllerFactory: () => controller,
        ),
      ),
    );

    expect(find.text('成都文理学院教务系统'), findsOneWidget);
    expect(find.textContaining('账号、密码和验证码仅提交给学校官网'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '识别并导入'), findsOneWidget);
    expect(find.text('教务网页'), findsOneWidget);
  });

  testWidgets('invalid HTML reports an error without importing', (tester) async {
    var imported = false;
    final controller = _FakeSchoolWebController(
      '<html><body>帐号登录 密码 验证码</body></html>',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(
          importer: const CdcasKingoImporter(),
          onImport: (preview) async {
            imported = true;
            return _successfulImport(preview);
          },
          controllerFactory: () => controller,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '识别并导入'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前页面不是个人课表'), findsOneWidget);
    expect(imported, isFalse);
  });

  testWidgets('valid HTML opens an import preview', (tester) async {
    final controller = _FakeSchoolWebController(_validHtml);
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(
          importer: const CdcasKingoImporter(),
          onImport: _successfulImport,
          controllerFactory: () => controller,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '识别并导入'));
    await tester.pumpAndSettle();

    expect(find.text('确认导入'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
  });

  testWidgets('logout clears the school session', (tester) async {
    final controller = _FakeSchoolWebController('<html></html>');
    await tester.pumpWidget(
      MaterialApp(
        home: TimetableImportPage(
          importer: const CdcasKingoImporter(),
          onImport: _successfulImport,
          controllerFactory: () => controller,
        ),
      ),
    );

    await tester.tap(find.text('退出教务登录'));
    await tester.pumpAndSettle();

    expect(controller.cleared, isTrue);
    expect(find.textContaining('登录信息已清除'), findsOneWidget);
  });
}

Future<ImportSummary> _successfulImport(ImportPreview preview) async {
  return ImportSummary(
    inserted: preview.courses.length,
    updated: 0,
    removed: 0,
    warnings: preview.warnings,
  );
}

class _FakeSchoolWebController implements SchoolWebController {
  _FakeSchoolWebController(this.html);

  final String html;
  bool cleared = false;

  @override
  Widget buildView() => const ColoredBox(
    key: ValueKey('fake-school-webview'),
    color: Colors.white,
    child: Center(child: Text('教务网页')),
  );

  @override
  Future<void> clearSession() async {
    cleared = true;
  }

  @override
  void dispose() {}

  @override
  Future<String> extractHtml() async => html;
}

const _validHtml = '''
<html><body><h1>2026-2027学年第1学期学生课表</h1>
<table data-first-week-start="2026-09-07" data-total-weeks="18">
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th></tr>
<tr><td>第1-2节</td><td>高等数学<br>第1-2节<br>1-18周<br>A302<br>陈老师</td><td></td><td></td><td></td><td></td></tr>
</table></body></html>
''';
