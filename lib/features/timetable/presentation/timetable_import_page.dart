import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/cdcas_kingo_importer.dart';
import '../data/course_repository.dart';
import 'import_preview_page.dart';

const schoolTimetableUri = 'https://jwc.cdcas.com/';

bool isAllowedSchoolUri(Uri uri) {
  return uri.scheme == 'https' && uri.host == 'jwc.cdcas.com';
}

abstract interface class SchoolWebController {
  Widget buildView();

  Future<Uri?> currentUri();

  Future<String> extractHtml();

  Future<void> clearSession();

  void dispose();
}

typedef SchoolWebControllerFactory = SchoolWebController Function();

class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({
    super.key,
    required this.importer,
    required this.onImport,
    required this.onPreview,
    this.controllerFactory,
  });

  final TimetableImporter importer;
  final Future<ImportSummary> Function(ImportPreview preview) onImport;
  final Future<ImportSummary> Function(ImportPreview preview) onPreview;
  final SchoolWebControllerFactory? controllerFactory;

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  late final SchoolWebController _controller;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controllerFactory?.call() ?? WebViewSchoolController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final currentUri = await _controller.currentUri();
      if (currentUri == null || !isAllowedSchoolUri(currentUri)) {
        throw const TimetableImportException(
          TimetableImportErrorCode.notTimetablePage,
          '当前页面不在学校官网，已停止读取课表。',
        );
      }
      final html = await _controller.extractHtml();
      final preview = widget.importer.parse(html);
      final changes = await widget.onPreview(preview);
      if (!mounted) return;
      final summary = await Navigator.of(context).push<ImportSummary>(
        MaterialPageRoute(
          builder: (_) =>
              ImportPreviewPage(
                preview: preview,
                changes: changes,
                onConfirm: widget.onImport,
              ),
        ),
      );
      if (!mounted || summary == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：新增 ${summary.inserted}，更新 ${summary.updated}，移除 ${summary.removed}',
          ),
        ),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(summary);
      }
    } on TimetableImportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取当前教务页面，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _logout() async {
    await _controller.clearSession();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('教务登录信息已清除')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('成都文理学院教务系统')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text('账号、密码和验证码仅提交给学校官网，青禾课表不会保存这些信息。登录后请打开个人课表。'),
          ),
          Expanded(child: _controller.buildView()),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: _reading ? null : _logout,
                  child: const Text('退出教务登录'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _reading ? null : _recognize,
                  icon: _reading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(_reading ? '正在识别…' : '识别并导入'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WebViewSchoolController implements SchoolWebController {
  WebViewSchoolController() : _cookieManager = WebViewCookieManager() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null && isAllowedSchoolUri(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(schoolTimetableUri));
  }

  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager;

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<Uri?> currentUri() async {
    final value = await _controller.currentUrl();
    return value == null ? null : Uri.tryParse(value);
  }

  @override
  Future<String> extractHtml() async {
    final result = await _controller.runJavaScriptReturningResult(
      '''(() => {
        const documents = [document];
        for (const frame of document.querySelectorAll('iframe')) {
          try {
            if (frame.contentDocument) documents.push(frame.contentDocument);
          } catch (_) {}
        }
        const timetable = documents.find((item) =>
          [...item.querySelectorAll('table')].some((table) =>
            /星期一/.test(table.innerText) && /星期五/.test(table.innerText)));
        return (timetable || document).documentElement.outerHTML;
      })()''',
    );
    if (result is! String) return result.toString();
    try {
      final decoded = jsonDecode(result);
      return decoded is String ? decoded : result;
    } on FormatException {
      return result;
    }
  }

  @override
  Future<void> clearSession() async {
    await _cookieManager.clearCookies();
    await _controller.clearCache();
    await _controller.loadRequest(Uri.parse(schoolTimetableUri));
  }

  @override
  void dispose() {}
}
