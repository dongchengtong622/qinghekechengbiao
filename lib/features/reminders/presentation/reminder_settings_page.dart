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

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  bool _loading = true;
  bool _enabled = false;
  int _leadMinutes = 30;
  ReminderSound _sound = ReminderSound.systemDefault;
  ReminderPermissionState _permission = ReminderPermissionState.denied;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final preferences = await widget.repository
          .watchReminderPreferences()
          .first;
      final permission = await widget.scheduler.permissionState();
      if (!mounted) return;
      setState(() {
        _enabled =
            preferences.enabled &&
            permission != ReminderPermissionState.denied;
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

      final permission = await widget.scheduler.requestPermissions();
      final accepted = permission != ReminderPermissionState.denied;
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

  @override
  Widget build(BuildContext context) {
    final delayed =
        _enabled && _permission == ReminderPermissionState.grantedInexact;
    return Scaffold(
      appBar: AppBar(title: const Text('课程提醒')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('上课提醒'),
              subtitle: Text(
                _leadMinutes == 0 ? '上课时提醒' : '提前 $_leadMinutes 分钟',
              ),
              value: _enabled,
              onChanged: _loading ? null : _setEnabled,
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
                        child: Text(
                          minutes == 0 ? '上课时' : '提前 $minutes 分钟',
                        ),
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
            )
          else if (!_loading && _permission == ReminderPermissionState.denied)
            const Card(
              child: ListTile(
                leading: Icon(Icons.notifications_off_outlined),
                title: Text('通知权限未开启'),
                subtitle: Text('开启开关后，系统会请求通知权限。'),
              ),
            ),
        ],
      ),
    );
  }
}
