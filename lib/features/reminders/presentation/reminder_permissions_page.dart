import 'dart:async';
import 'package:flutter/material.dart';
import '../data/reminder_scheduler.dart';
import '../data/native_alarm_scheduler.dart';
import '../domain/reminder_models.dart';

/// Public capabilities are queryable; OEM banner/lock-screen/autostart are not.
class ReminderPermissionsPage extends StatefulWidget {
  const ReminderPermissionsPage({
    super.key,
    required this.scheduler,
    required this.sound,
    required this.onCapabilityChanged,
  });
  final ReminderScheduler scheduler;
  final RingtoneSelection sound;
  final Future<void> Function() onCapabilityChanged;
  @override
  State<ReminderPermissionsPage> createState() =>
      _ReminderPermissionsPageState();
}

class _ReminderPermissionsPageState extends State<ReminderPermissionsPage>
    with WidgetsBindingObserver {
  ReminderPermissionStatus? status;
  bool busy = false;
  bool notificationRequested = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final updated = await widget.scheduler.permissionStatus();
      final changed =
          status != null && status!.capabilityKey != updated.capabilityKey;
      if (mounted) {
        setState(() {
          status = updated;
          error = null;
        });
      }
      if (changed) await widget.onCapabilityChanged();
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法检查，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(String kind, String explanation) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('提醒设置'),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    try {
      if (kind == 'notifications' &&
          status?.notificationsAllowed != true &&
          !notificationRequested) {
        notificationRequested = true;
        final updated = await widget.scheduler.requestNotificationPermission();
        if (updated.notificationsAllowed) {
          await refresh();
          return;
        }
        // Denial leaves this page actionable; no second automatic settings jump.
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('通知未允许，可再次点击设置通知')));
        }
        if (mounted) setState(() => status = updated);
        return;
      }
      if (widget.scheduler case final NativeAlarmScheduler native) {
        await native.openSettings(kind);
      } else if (kind == 'exact') {
        await widget.scheduler.requestExactAlarmPermission();
      } else {
        await widget.scheduler.openNotificationSettings();
      }
      await refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开设置，请到系统设置 → 应用 → 青禾课表手动检查')),
        );
      }
    }
  }

  Widget row(
    String name,
    String state,
    String action,
    String kind,
    String explanation,
  ) => ListTile(
    title: Text(name),
    subtitle: Text(state),
    trailing: TextButton(
      onPressed: busy ? null : () => open(kind, explanation),
      child: Text(action),
    ),
  );
  Future<void> test(Duration delay) async {
    try {
      await widget.scheduler.sendTest(sound: widget.sound, delay: delay);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              delay == Duration.zero
                  ? '通知已提交系统，请检查横幅、声音和锁屏展示'
                  : '定时测试已安排；非精确模式可能延迟',
            ),
          ),
        );
      }
      await refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('测试未完成，请检查通知权限和课程提醒渠道')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final known = s != null;
    final channelNotApplicable = known && s.sdkInt > 0 && s.sdkInt < 26;
    final exactNotApplicable = known && s.sdkInt > 0 && s.sdkInt < 31;
    final primary = !known || !s.notificationsAllowed
        ? '开启通知'
        : !s.exactAlarmsAllowed
        ? '允许精确提醒'
        : '检查提醒设置';
    return Scaffold(
      appBar: AppBar(title: const Text('课程提醒权限')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('完成必要设置，让课前提醒更及时'),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy
                ? null
                : () => open(
                    !known || !s.notificationsAllowed
                        ? 'notifications'
                        : !s.exactAlarmsAllowed
                        ? 'exact'
                        : 'channel',
                    !known || !s.notificationsAllowed
                        ? '允许通知后，才能显示课程提醒。'
                        : !s.exactAlarmsAllowed
                        ? '精确提醒用于在设定的课前时间触发；未允许时可能延迟。'
                        : '横幅和锁屏效果由系统决定，请检查课程提醒渠道。',
                  ),
            child: Text(primary),
          ),
          Card(
            child: Column(
              children: [
                row(
                  '通知权限',
                  known ? (s.notificationsAllowed ? '已开启' : '未开启') : '需要检查',
                  '设置通知',
                  'notifications',
                  '用于显示课程、时间、教室和教师信息。',
                ),
                row(
                  '课程提醒渠道',
                  !known
                      ? '需要检查'
                      : channelNotApplicable
                      ? '不适用：此系统无需通知渠道'
                      : !s.channelAllowed
                      ? '已关闭'
                      : s.channelUserSilenced
                      ? '静默：尊重系统声音设置'
                      : s.channelSilent
                      ? '系统通知无声音；降级模式仅显示通知'
                      : !s.channelHighImportance
                      ? '可能受限：渠道级别较低'
                      : '正常：已允许通知',
                  '设置通知',
                  'channel',
                  '系统中的渠道开关和声音选择会影响课程提醒。',
                ),
                row(
                  '横幅提醒',
                  known && (!s.channelAllowed || !s.channelHighImportance)
                      ? '可能受限；请检查系统横幅设置'
                      : '需要检查；最终展示由系统决定',
                  '检查横幅',
                  'channel',
                  '高优先级只是横幅展示的基础条件，勿扰和厂商设置也会影响。',
                ),
                row(
                  '锁屏提醒',
                  !known
                      ? '需要检查'
                      : s.fullScreenAllowed
                      ? '已允许全屏提醒；到点展示课程详情'
                      : '未允许全屏提醒；仅显示系统通知',
                  '允许全屏提醒',
                  'fullScreen',
                  '用于锁屏时显示课程、时间、教室和教师。解锁时由系统显示横幅；点击可查看详情。Android 14 及以上需要单独允许全屏提醒，通知和横幅仍受系统设置影响。',
                ),
                row(
                  '精确提醒',
                  !known
                      ? '需要检查'
                      : exactNotApplicable
                      ? '不适用：此系统无需单独授权'
                      : s.exactAlarmsAllowed
                      ? '已允许'
                      : '未允许；普通定时提醒可能延迟',
                  '允许精确提醒',
                  'exact',
                  '用于在设定的课前时间提醒；无需关闭课程提醒也可使用降级模式。',
                ),
                row(
                  '后台运行',
                  known && s.backgroundRestricted
                      ? '检测到系统后台限制；厂商设置需要检查'
                      : known && s.batteryUnrestricted
                      ? '电池优化已豁免；厂商后台设置需要检查'
                      : '需要检查；电池与自启动是不同设置',
                  '检查后台',
                  'battery',
                  '按需检查省电和自启动。电池优化豁免不代表全部后台权限正常。',
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed:
                    busy ||
                        !known ||
                        !s.notificationsAllowed ||
                        !s.channelAllowed
                    ? null
                    : () => test(Duration.zero),
                child: const Text('发送测试通知'),
              ),
              OutlinedButton(
                onPressed:
                    busy ||
                        !known ||
                        !s.notificationsAllowed ||
                        !s.channelAllowed
                    ? null
                    : () => test(const Duration(minutes: 1)),
                child: const Text('测试定时提醒'),
              ),
            ],
          ),
          const Text(
            '测试只验证本次展示和短期定时，不保证长期后台效果。静音、勿扰、省电和厂商限制可能影响提醒。强行停止后请再次打开应用。',
          ),
        ],
      ),
    );
  }
}
