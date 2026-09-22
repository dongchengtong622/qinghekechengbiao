import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/reminder_scheduler.dart';
import '../data/ringtone_service.dart';
import '../domain/reminder_diagnostics.dart';
import '../domain/reminder_models.dart';
import '../domain/reminder_settings_repository.dart';

typedef ReminderSettingChanged = Future<void> Function(bool enabled);

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({
    super.key,
    required this.repository,
    required this.scheduler,
    required this.onChanged,
    this.ringtoneService = const NativeRingtoneService(),
  });

  final ReminderSettingsRepository repository;
  final ReminderScheduler scheduler;
  final ReminderSettingChanged onChanged;
  final RingtoneService ringtoneService;

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = false;
  int _leadMinutes = 30;
  RingtoneSelection _sound = RingtoneSelection.systemDefault;
  ReminderFailure? _failure;
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
    unawaited(widget.ringtoneService.stop());
    super.dispose();
  }

  Future<void> _importLocalSound() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final sound = await widget.ringtoneService.importLocal();
      if (sound == null) return;
      await widget.repository.setReminderSound(sound);
      if (_enabled) await widget.onChanged(true);
      if (mounted) setState(() => _sound = sound);
    } on PlatformException catch (error) {
      _showFailure(
        ReminderFailure(
          stage: ReminderStage.settings,
          code: error.code,
          message: '添加本地音乐失败',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _previewSound() async {
    try {
      await widget.ringtoneService.preview(_sound);
    } on PlatformException catch (error) {
      _showFailure(
        ReminderFailure(
          stage: ReminderStage.registration,
          code: error.code,
          message: '无法试听该铃声',
        ),
      );
    }
  }

  Future<void> _sendTest(Duration delay) async {
    try {
      await widget.scheduler.sendTest(sound: _sound, delay: delay);
      if (!mounted) return;
      final message = delay == Duration.zero ? '测试通知已发送' : '测试已安排，1分钟后请锁屏检查';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on PlatformException catch (error) {
      _showFailure(
        ReminderFailure(
          stage: ReminderStage.registration,
          code: error.code,
          message: '测试通知失败',
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(reschedule: true));
    }
  }

  Future<void> _load({bool reschedule = false}) async {
    ReminderPreferences preferences;
    try {
      preferences = await widget.repository.watchReminderPreferences().first;
    } catch (_) {
      _showFailure(
        const ReminderFailure(
          stage: ReminderStage.settings,
          code: 'read_failed',
          message: '无法读取提醒状态，请稍后重试',
        ),
      );
      if (mounted) setState(() => _loading = false);
      return;
    }

    ReminderPermissionStatus permission;
    try {
      permission = await widget.scheduler.permissionStatus();
    } on PlatformException catch (error) {
      _showFailure(
        ReminderFailure(
          stage: ReminderStage.permissions,
          code: error.code,
          message: '无法读取通知权限，请稍后重试',
        ),
      );
      if (mounted) setState(() => _loading = false);
      return;
    } catch (_) {
      _showFailure(
        const ReminderFailure(
          stage: ReminderStage.permissions,
          code: 'unexpected',
          message: '无法读取通知权限，请稍后重试',
        ),
      );
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final enabled = preferences.enabled && permission.notificationsAllowed;
      if (preferences.enabled && !permission.notificationsAllowed) {
        await widget.repository.setRemindersEnabled(false);
      }
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _leadMinutes = preferences.leadMinutes;
        _sound = preferences.sound;
        _permission = permission;
        _failure = null;
      });
      if (reschedule) await _reschedule(enabled);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reschedule(bool enabled) async {
    try {
      await widget.onChanged(enabled);
    } on PlatformException catch (error) {
      _showFailure(
        ReminderFailure(
          stage: ReminderStage.registration,
          code: error.code,
          message: '设置提醒失败',
        ),
      );
    } catch (_) {
      _showFailure(
        const ReminderFailure(
          stage: ReminderStage.registration,
          code: 'unexpected',
          message: '设置提醒失败',
        ),
      );
    }
  }

  void _showFailure(ReminderFailure failure) {
    if (!mounted) return;
    setState(() => _failure = failure);
    if (failure.stage == ReminderStage.registration) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure.message)));
  }

  Future<void> _copyFailure() async {
    final failure = _failure;
    if (failure == null) return;
    await Clipboard.setData(
      ClipboardData(
        text:
            'stage=${failure.stage.name}; code=${failure.code}; message=${failure.message}',
      ),
    );
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

  Future<void> _setSound(RingtoneSelection? sound) async {
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

  String _soundLabel(RingtoneSelection sound) => sound.name;

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

      final permission = await widget.scheduler.requestNotificationPermission();
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
      final permission = await widget.scheduler.requestNotificationPermission();
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('import_local_ringtone'),
                onPressed: _loading ? null : _importLocalSound,
                icon: const Icon(Icons.library_music_outlined),
                label: const Text('添加本地音乐'),
              ),
              OutlinedButton.icon(
                key: const Key('preview_ringtone'),
                onPressed: _previewSound,
                icon: const Icon(Icons.play_arrow),
                label: const Text('试听'),
              ),
              OutlinedButton.icon(
                key: const Key('stop_ringtone'),
                onPressed: widget.ringtoneService.stop,
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              ),
              FilledButton(
                key: const Key('test_notification_now'),
                onPressed: () => _sendTest(Duration.zero),
                child: const Text('立即测试通知'),
              ),
              FilledButton.tonal(
                key: const Key('test_notification_delayed'),
                onPressed: () => _sendTest(const Duration(minutes: 1)),
                child: const Text('1分钟后测试'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_failure case final failure?) ...[
            Card(
              child: ListTile(
                title: Text(failure.message),
                subtitle: Text(
                  '阶段：${failure.stage.name} · 错误码：${failure.code}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      key: const Key('retry_reminders'),
                      tooltip: '重试',
                      onPressed: _loading
                          ? null
                          : () => _load(reschedule: true),
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      key: const Key('copy_reminder_error'),
                      tooltip: '复制错误详情',
                      onPressed: _copyFailure,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
              child: DropdownButtonFormField<RingtoneSelection>(
                key: const Key('reminder_sound'),
                initialValue: _sound,
                decoration: const InputDecoration(
                  labelText: '提醒铃声',
                  border: InputBorder.none,
                ),
                items: [
                  ...RingtoneSelection.presets,
                  if (_sound.contentUri != null) _sound,
                ]
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
