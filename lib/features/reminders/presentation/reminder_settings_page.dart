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
  ReminderPermissionState _permission = ReminderPermissionState.denied;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final enabled = await widget.repository.watchRemindersEnabled().first;
      final permission = await widget.scheduler.permissionState();
      if (!mounted) return;
      setState(() {
        _enabled = enabled && permission != ReminderPermissionState.denied;
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
              subtitle: const Text('提前 30 分钟'),
              value: _enabled,
              onChanged: _loading ? null : _setEnabled,
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
