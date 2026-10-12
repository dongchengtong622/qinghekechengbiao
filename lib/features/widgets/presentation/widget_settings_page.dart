import 'package:flutter/material.dart';

class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({super.key, required this.onRefresh});
  final Future<void> Function() onRefresh;
  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage> {
  bool busy = false;
  String? status;
  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await widget.onRefresh();
      if (mounted) {
        setState(() => status = '组件数据已更新');
      }
    } catch (_) {
      if (mounted) setState(() => status = '刷新失败，请稍后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('桌面小组件')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('组件跟随当前启用课表，显示实际日期的课程。'),
        Card(
          child: ListTile(
            title: const Text('下一节课 · 2×2'),
            subtitle: const Text('课程、开始时间、教室及约距上课时间'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: const Text('今日课程 · 4×2'),
            subtitle: const Text('教学周、星期和今日课程，支持点击查看详情'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新组件数据'),
        ),
        if (status != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(status!)),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('手动添加教程', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text('1. 返回手机桌面，长按桌面空白处，进入桌面编辑。'),
                SizedBox(height: 8),
                Text('2. 打开“小组件”或“桌面挂件”，找到“青禾课表”。'),
                SizedBox(height: 8),
                Text('3. 选择“下一节课”或“今日课程”，长按并拖到桌面空白位置；部分手机可直接点击添加。'),
                SizedBox(height: 8),
                Text('4. 点击桌面空白处或“完成”退出编辑。若放不下，请换到空白桌面页或腾出位置。'),
                SizedBox(height: 12),
                Text(
                  '找不到组件时，请先打开一次青禾课表，再回到桌面尝试。不同手机入口名称可能不同；部分桌面需要双指向内捏合进入编辑。',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('桌面网格尺寸由手机桌面决定。后台省电可能延迟刷新，倒计时为更新时的估计；打开应用或点击刷新可重新计算。'),
      ],
    ),
  );
}
