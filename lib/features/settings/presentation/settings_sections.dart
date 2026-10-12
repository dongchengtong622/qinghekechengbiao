import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../timetable/data/course_repository.dart';
import '../../timetable/domain/models.dart';
import '../../timetable/presentation/import_preview_page.dart';
import 'scoped_schedule_page.dart';
import 'usage_guide_page.dart';

class SettingsSections extends StatelessWidget {
  const SettingsSections({
    super.key,
    required this.repository,
    required this.onChanged,
    required this.onBackup,
    this.onReminders,
  });
  final CourseRepository repository;
  final Future<void> Function() onChanged;
  final VoidCallback onBackup;
  final VoidCallback? onReminders;

  Future<void> openGroup(BuildContext context, String group) async {
    if (group == '作息时间') {
      final term = await repository.watchActiveSemester().first;
      final schedule = await repository.readSchoolSchedule();
      final courses = await repository.watchCoursesForSemester(term.id).first;
      final minimum = courses
          .expand((c) => c.sessions)
          .fold<int>(1, (n, s) => n > s.endSection ? n : s.endSection);
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ScopedSchedulePage(
            semester: term,
            schedule: schedule,
            minimumSectionCount: minimum,
            onSave: (v) async {
              await repository.saveSemesterSchedule(term.id, v);
              await onChanged();
            },
          ),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(group)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SettingsDetails(
                repository: repository,
                onChanged: onChanged,
                onBackup: onBackup,
                group: group,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in const <String, IconData>{
        '提醒设置': Icons.notifications_outlined,
        '课表与学期': Icons.calendar_month_outlined,
        '作息时间': Icons.schedule,
        '数据管理': Icons.backup_outlined,
        '关于与帮助': Icons.help_outline,
      }.entries)
        Card(
          child: ListTile(
            leading: Icon(entry.value),
            title: Text(entry.key),
            trailing: const Icon(Icons.chevron_right),
            onTap: entry.key == '提醒设置'
                ? onReminders
                : () => openGroup(context, entry.key),
          ),
        ),
    ],
  );
}

class _SettingsDetails extends StatelessWidget {
  const _SettingsDetails({
    required this.repository,
    required this.onChanged,
    required this.onBackup,
    required this.group,
  });
  final String group;
  final CourseRepository repository;
  final Future<void> Function() onChanged;
  final VoidCallback onBackup;
  Future<void> editSemester(BuildContext context, Semester current) async {
    final minimumWeeks = await repository.minimumSemesterWeeks(current.id);
    if (!context.mounted) return;
    final value = await askImportSemester(
      context,
      current,
      minimumWeeks: minimumWeeks,
    );
    if (value != null) {
      try {
        await repository.saveSemester(value, makeActive: true);
        await onChanged();
      } on FormatException catch (error) {
        if (context.mounted) await info(context, '无法保存学期', error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Semester>(
    stream: repository.watchActiveSemester(),
    builder: (c, s) {
      if (!s.hasData) return const SizedBox.shrink();
      final term = s.data!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (group == '课表与学期') ...[
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '课表与学期',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('课表管理'),
                    subtitle: Text('当前：${term.name}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ScheduleManagementPage(
                          repository: repository,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('学期信息'),
                    subtitle: Text(
                      '${term.name} · ${term.totalWeeks}周\n第一周星期一：${term.firstWeekStart.toString().split(' ').first}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => editSemester(context, term),
                  ),
                ],
              ),
            ),
          ],
          if (group == '作息时间') ...[
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '作息时间',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('每节上课时间'),
                subtitle: Text('仅修改 ${term.name} 的作息'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final schedule = await repository.readSchoolSchedule();
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ScopedSchedulePage(
                        semester: term,
                        schedule: schedule,
                        onSave: (v) async {
                          await repository.saveSemesterSchedule(term.id, v);
                          await onChanged();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (group == '数据管理') ...[
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '数据管理',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('备份与恢复'),
                subtitle: const Text('导出到本地文件或从备份文件恢复'),
                leading: const Icon(Icons.backup_outlined),
                onTap: onBackup,
              ),
            ),
          ],
          if (group == '关于与帮助') ...[
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '关于与帮助',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('关于青禾课表'),
                    subtitle: const Text('V1.0.5'),
                    onTap: () => info(
                      context,
                      '关于青禾课表',
                      '青禾课表 V1.0.5\n本地课程表，支持Excel导入、多课表、课程提醒与桌面小组件。',
                    ),
                  ),
                  ListTile(
                    title: const Text('使用说明'),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const UsageGuidePage()),
                    ),
                  ),
                  ListTile(
                    title: const Text('问题反馈'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const LocalFeedbackPage(),
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('隐私政策'),
                    onTap: () => info(
                      context,
                      '隐私政策',
                      '课表、学期、作息和提醒配置保存在本机，不需要账号，也不会自动上传课程。Excel文件由你主动选择读取，备份由你选择位置保存。通知和闹钟权限用于课程提醒；本地铃声由你选择导入。卸载或清除数据会删除本机应用数据，请自行保管备份。',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
  static Future<void> info(BuildContext context, String title, String body) =>
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
}

class ScheduleManagementPage extends StatelessWidget {
  const ScheduleManagementPage({
    super.key,
    required this.repository,
    required this.onChanged,
  });
  final CourseRepository repository;
  final Future<void> Function() onChanged;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('课表管理')),
    body: StreamBuilder<Semester>(
      stream: repository.watchActiveSemester(),
      builder: (c, active) => StreamBuilder<List<Semester>>(
        stream: repository.watchSemesters(),
        builder: (c, s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('切换启用课表会同步首页、课程提醒与桌面小组件。'),
            for (final t in s.data ?? <Semester>[])
              Card(
                child: ListTile(
                  title: Text(t.name),
                  subtitle: Text(
                    '${t.totalWeeks}周 · ${t.firstWeekStart.toString().split(' ').first}',
                  ),
                  trailing: active.data?.id == t.id
                      ? const Icon(Icons.check_circle)
                      : TextButton(
                          onPressed: () async {
                            await repository.activateSemester(t.id);
                            await onChanged();
                          },
                          child: const Text('启用'),
                        ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('新建课表'),
              onPressed: () async {
                final now = DateTime.now();
                final monday = DateTime(
                  now.year,
                  now.month,
                  now.day,
                ).subtract(Duration(days: now.weekday - 1));
                final t = await askImportSemester(
                  context,
                  Semester(
                    id: 'schedule-${now.microsecondsSinceEpoch}',
                    name: '新课表',
                    firstWeekStart: monday,
                    totalWeeks: 20,
                  ),
                );
                if (t != null) {
                  await repository.saveSemester(t, makeActive: true);
                  await onChanged();
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class LocalFeedbackPage extends StatefulWidget {
  const LocalFeedbackPage({super.key});
  @override
  State<LocalFeedbackPage> createState() => _LocalFeedbackPageState();
}

class _LocalFeedbackPageState extends State<LocalFeedbackPage> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('问题反馈')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('描述操作步骤、预期结果和实际问题。内容不会自动发送，你可以复制后交给开发者。'),
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(labelText: '问题描述'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: '青禾课表 V1.0.5\n${controller.text}'),
            );
            if (c.mounted) {
              ScaffoldMessenger.of(
                c,
              ).showSnackBar(const SnackBar(content: Text('已复制，请手动发送给开发者')));
            }
          },
          child: const Text('复制反馈内容'),
        ),
      ],
    ),
  );
}
