import 'dart:async';

import 'package:flutter/material.dart';

import '../data/reminder_scheduler.dart';
import '../domain/reminder_models.dart';
import '../domain/reminder_settings_repository.dart';

typedef ReminderSettingChanged = Future<void> Function(bool enabled);

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({
    super.key,
    required this.repository,
    required this.scheduler,
    required this.onChanged,
  });

  final ReminderSettingsRepository repository;
  final ReminderScheduler scheduler;
  final ReminderSettingChanged onChanged;

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = false;
  int _leadMinutes = 30;
  ReminderSound _sound = ReminderSound.systemDefault;
  ReminderPermissionStatus _permission = const ReminderPermissionStatus(
    notificationsAllowed: false,
    exactAlarmsAllowed: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(reschedule: true));
    }
  }

  Future<void> _load({bool reschedule = false}) async {
    try {
      final preferences = await widget.repository
          .watchReminderPreferences()
          .first;
      final permission = await widget.scheduler.permissionStatus();
      final enabled =
          preferences.enabled && permission.notificationsAllowed;
      if (reschedule && enabled) await widget.onChanged(true);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _leadMinutes = preferences.leadMinutes;
        _sound = preferences.sound;
        _permission = permission;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取提醒状态，请稍后重试')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setLeadMinutes(int? minutes) async {
    if (minutes == null || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.repository.setReminderLeadMinutes(minutes);
      if (_enabled) await widget.onChanged(true);
      if (mounted) setState(() => _leadMinutes = minutes);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setSound(ReminderSound? sound) async {
    if (sound == null || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.repository.setReminderSound(sound);
      if (_enabled) await widget.onChanged(true);
      if (mounted) setState(() => _sound = sound);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _soundLabel(ReminderSound sound) => switch (sound) {
    ReminderSound.systemDefault => '系统默认',
    ReminderSound.chime => '清脆铃声',
    ReminderSound.soft => '柔和铃声',
    ReminderSound.alert => '提示音',
  };

  Future<void> _setEnabled(bool enabled) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (!enabled) {
        await widget.repository.setRemindersEnabled(false);
        await widget.scheduler.replaceAll(const []);
        await widget.onChanged(false);
        if (!mounted) return;
        setState(() => _enabled = false);
        return;
      }

      final permission = await widget.scheduler
          .requestNotificationPermission();
      final accepted = permission.notificationsAllowed;
      await widget.repository.setRemindersEnabled(accepted);
      if (accepted) await widget.onChanged(true);
      if (!mounted) return;
      setState(() {
        _enabled = accepted;
        _permission = permission;
      });
      if (!accepted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('通知权限未开启，无法启用课程提醒')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提醒设置失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final permission = await widget.scheduler
          .requestNotificationPermission();
      if (!mounted) return;
      setState(() => _permission = permission);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestExactAlarmPermission() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final permission = await widget.scheduler.requestExactAlarmPermission();
      if (_enabled) await widget.onChanged(true);
      if (!mounted) return;
      setState(() => _permission = permission);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNotificationSettings() async {
    await widget.scheduler.openNotificationSettings();
  }

  String get _scheduleMode {
    if (!_permission.notificationsAllowed) return '已禁用';
    return _permission.exactAlarmsAllowed ? '精确' : '非精确（可能延迟）';
  }

  @override
  Widget build(BuildContext context) {
    final delayed =
        _enabled &&
        _permission.notificationsAllowed &&
        !_permission.exactAlarmsAllowed;
    return Scaffold(
      appBar: AppBar(title: const Text('课程提醒')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('上课提醒'),
              subtitle: Text(
                _leadMinutes == 0 ? '当前：上课时提醒' : '当前：提前 $_leadMinutes 分钟',
              ),
              value: _enabled,
              onChanged: _loading ? null : _setEnabled,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('通知权限'),
                  subtitle: Text(
                    _permission.notificationsAllowed ? '已开启' : '未开启',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('request_notification_permission'),
                        tooltip: '请求通知权限',
                        onPressed: _loading
                            ? null
                            : _requestNotificationPermission,
                        icon: const Icon(Icons.notifications_active_outlined),
                      ),
                      IconButton(
                        key: const Key('open_notification_settings'),
                        tooltip: '打开通知设置',
                        onPressed: _loading ? null : _openNotificationSettings,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('精确闹钟权限'),
                  subtitle: Text(
                    _permission.exactAlarmsAllowed ? '已开启' : '未开启',
                  ),
                  trailing:
                      _permission.notificationsAllowed &&
                          !_permission.exactAlarmsAllowed
                      ? TextButton(
                          key: const Key('request_exact_alarm_permission'),
                          onPressed: _loading
                              ? null
                              : _requestExactAlarmPermission,
                          child: const Text('去开启'),
                        )
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('当前调度模式'),
                  subtitle: Text(_scheduleMode),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<int>(
                key: const Key('lead_time'),
                initialValue: _leadMinutes,
                decoration: const InputDecoration(
                  labelText: '提醒时间',
                  border: InputBorder.none,
                ),
                items: const [0, 5, 10, 15, 30, 60]
                    .map(
                      (minutes) => DropdownMenuItem(
                        value: minutes,
                        child: Text(minutes == 0 ? '上课时' : '提前 $minutes 分钟'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _loading ? null : _setLeadMinutes,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<ReminderSound>(
                key: const Key('reminder_sound'),
                initialValue: _sound,
                decoration: const InputDecoration(
                  labelText: '提醒铃声',
                  border: InputBorder.none,
                ),
                items: ReminderSound.values
                    .map(
                      (sound) => DropdownMenuItem(
                        value: sound,
                        child: Text(_soundLabel(sound)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _loading ? null : _setSound,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (delayed)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const ListTile(
                leading: Icon(Icons.schedule_rounded),
                title: Text('提醒可能因系统限制而延迟'),
                subtitle: Text('未获得精确闹钟权限，将使用系统允许的非精确调度。'),
              ),
            ),
        ],
      ),
    );
  }
}
