import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/reminder_scheduler.dart';
import '../data/native_alarm_scheduler.dart';
import '../data/ringtone_service.dart';
import '../domain/reminder_models.dart';
import '../domain/reminder_settings_repository.dart';
import 'alarm_options_pages.dart';
import 'reminder_permissions_page.dart';

typedef ReminderSettingChanged = Future<void> Function(bool enabled);

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({
    super.key,
    required this.repository,
    required this.scheduler,
    required this.onChanged,
    this.ringtoneService = const NativeRingtoneService(),
    this.vibrationService = const NativeVibrationService(),
    this.nextReminderAtListenable,
    this.nextReminderListenable,
    this.optionsOnly = false,
    this.additionalSettings = const [],
  });
  final ReminderSettingsRepository repository;
  final ReminderScheduler scheduler;
  final ReminderSettingChanged onChanged;
  final RingtoneService ringtoneService;
  final VibrationService vibrationService;
  final ValueListenable<DateTime?>? nextReminderAtListenable;
  final ValueListenable<CourseReminder?>? nextReminderListenable;
  final bool optionsOnly;
  final List<Widget> additionalSettings;
  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage>
    with WidgetsBindingObserver {
  bool loading = true;
  bool checkingPermission = false;
  int changeRevision = 0;
  int pendingChanges = 0;
  Future<void> writeQueue = Future.value();
  bool enableRequested = false;
  String? error;
  ReminderPreferences prefs = const ReminderPreferences(
    enabled: false,
    leadMinutes: 30,
    sound: RingtoneSelection.systemDefault,
  );
  ReminderPermissionStatus permission = const ReminderPermissionStatus(
    notificationsAllowed: false,
    exactAlarmsAllowed: false,
  );
  bool get canSchedule =>
      permission.notificationsAllowed && permission.channelAllowed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(load(reschedule: true));
  }

  Future<void> load({
    bool reschedule = false,
    bool forceReschedule = false,
  }) async {
    final revision = changeRevision;
    try {
      final p = await widget.repository.watchReminderPreferences().first;
      final s = await widget.scheduler.permissionStatus();
      if (!mounted) return;
      final capabilityChanged = permission.capabilityKey != s.capabilityKey;
      setState(() {
        if (pendingChanges == 0 && revision == changeRevision) prefs = p;
        permission = s;
      });
      if (revision == changeRevision &&
          pendingChanges == 0 &&
          (forceReschedule || (reschedule && capabilityChanged && p.enabled))) {
        await widget.onChanged(p.enabled);
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法更新提醒，请检查设置后重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  ReminderPreferences updatedPreferences({
    bool? enabled,
    int? leadMinutes,
    bool? holidaySilenceEnabled,
  }) => ReminderPreferences(
    enabled: enabled ?? prefs.enabled,
    leadMinutes: leadMinutes ?? prefs.leadMinutes,
    holidaySilenceEnabled: holidaySilenceEnabled ?? prefs.holidaySilenceEnabled,
    sound: prefs.sound,
    snoozeMinutes: prefs.snoozeMinutes,
    maxRings: prefs.maxRings,
    snoozeEnabled: prefs.snoozeEnabled,
    vibration: prefs.vibration,
  );

  Future<void> change(
    ReminderPreferences next,
    Future<void> Function() write,
  ) async {
    if (loading) return;
    final revision = ++changeRevision;
    pendingChanges++;
    setState(() {
      prefs = next;
      error = null;
    });
    // Keep disk writes ordered, while the switches remain responsive. A stale
    // completion must never overwrite a more recent tap or rebuild its alarms.
    final saved = writeQueue.then((_) => write());
    writeQueue = saved.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    var saveFailed = false;
    try {
      await saved;
    } catch (_) {
      saveFailed = true;
    } finally {
      pendingChanges--;
    }
    if (revision != changeRevision) return;
    try {
      final stored = await widget.repository.watchReminderPreferences().first;
      if (revision != changeRevision) return;
      if (mounted) {
        setState(() {
          prefs = stored;
          if (saveFailed) error = '保存提醒设置失败，请重试';
        });
      }
      // Reconcile stored settings even after leaving this page or a failed
      // final write, so disabled reminders cannot retain registered alarms.
      await widget.onChanged(stored.enabled);
    } catch (_) {
      if (mounted && revision == changeRevision) {
        setState(() => error = '提醒调度失败，请重试');
      }
    }
  }

  Future<void> enable(bool enabled) async {
    if (loading || checkingPermission) return;
    if (!enabled) {
      enableRequested = false;
      await change(
        updatedPreferences(enabled: false),
        () => widget.repository.setRemindersEnabled(false),
      );
      return;
    }
    if (prefs.leadMinutes <= 0) {
      final choice = await showDialog<int>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('选择课前提醒时间'),
          children: [
            for (final n in [5, 10, 15, 30, 60])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, n),
                child: Text('提前 $n 分钟'),
              ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      await widget.repository.setReminderLeadMinutes(choice);
      await load();
    }
    setState(() {
      checkingPermission = true;
      error = null;
    });
    try {
      final s = await widget.scheduler.permissionStatus();
      if (!mounted) return;
      setState(() => permission = s);
      final kind = !s.notificationsAllowed
          ? 'notifications'
          : !s.channelAllowed
          ? 'channel'
          : !s.exactAlarmsAllowed
          ? 'exact'
          : null;
      if (kind != null) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('开启课程提醒'),
            content: Text(
              kind == 'exact'
                  ? '请允许青禾课表设置闹钟和提醒，以便按时提醒上课。'
                  : '请允许课程通知，才能显示上课提醒。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        if (accepted == true) {
          await settings(kind);
        }
        return;
      }
      setState(() => checkingPermission = false);
      await change(
        updatedPreferences(enabled: true),
        () => widget.repository.setRemindersEnabled(true),
      );
    } catch (_) {
      if (mounted) setState(() => error = '设置提醒失败，请稍后重试');
    } finally {
      if (mounted) setState(() => checkingPermission = false);
    }
  }

  Future<void> settings(String kind) async {
    final scheduler = widget.scheduler;
    if (scheduler is NativeAlarmScheduler) {
      await scheduler.openSettings(kind);
    } else if (kind == 'exact') {
      await scheduler.requestExactAlarmPermission();
    } else if (kind == 'notifications') {
      await scheduler.requestNotificationPermission();
    } else {
      await scheduler.openNotificationSettings();
    }
    if (mounted) await load();
  }

  Future<void> saved() async {
    final before = prefs;
    await load();
    if (widget.scheduler case final NativeAlarmScheduler native) {
      if (before.sound.storageValue != prefs.sound.storageValue ||
          before.vibration != prefs.vibration) {
        try {
          final fallback = await native.configureAlert(
            prefs.sound,
            prefs.vibration,
          );
          if (fallback) {
            await widget.repository.setReminderSound(
              RingtoneSelection.systemDefault,
            );
            message('所选铃声无法读取，已改用系统默认，请重新选择');
          }
        } catch (_) {
          await widget.repository.setReminderSound(before.sound);
          await widget.repository.setReminderVibration(before.vibration);
          message('当前通知声音已被系统修改或关闭，请到“通知声音设置”中调整；已保留原选择');
        }
        await load();
      }
    }
    await widget.onChanged(prefs.enabled);
  }

  Future<void> open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) await load();
  }

  String get capability {
    if (!permission.notificationsAllowed) return '通知未允许';
    if (!permission.channelAllowed) return '课程提醒渠道已关闭';
    if (!permission.exactAlarmsAllowed) return '已使用普通定时提醒，可能延迟；可允许精确提醒';
    if (!permission.channelHighImportance) return '横幅能力不足，请检查提醒渠道';
    return '通知和准时调度已就绪；横幅效果受系统设置影响';
  }

  Widget stateRow(String title, String state, String kind) => ListTile(
    title: Text(title),
    subtitle: Text(state),
    trailing: TextButton(
      onPressed: loading ? null : () => settings(kind),
      child: const Text('去设置'),
    ),
  );
  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.optionsOnly ? '提醒设置' : '课程提醒')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (!widget.optionsOnly) ...[
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('上课提醒'),
                  subtitle: const Text('课前响铃，上课时停止'),
                  value: prefs.enabled,
                  onChanged: loading || checkingPermission ? null : enable,
                ),
                if (prefs.enabled) ...[
                  ListTile(
                    title: const Text('提醒时间'),
                    trailing: DropdownButton<int>(
                      key: const Key('lead_time'),
                      value: prefs.leadMinutes,
                      items:
                          ({5, 10, 15, 30, 60, prefs.leadMinutes}.toList()
                                ..sort())
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('提前 $v 分钟'),
                                ),
                              )
                              .toList(),
                      onChanged: loading
                          ? null
                          : (v) {
                              if (v != null) {
                                change(
                                  updatedPreferences(leadMinutes: v),
                                  () => widget.repository
                                      .setReminderLeadMinutes(v),
                                );
                              }
                            },
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('holiday_silence'),
                    title: const Text('法定节假日静默'),
                    value: prefs.holidaySilenceEnabled,
                    onChanged: loading
                        ? null
                        : (v) => change(
                            updatedPreferences(holidaySilenceEnabled: v),
                            () => widget.repository.setHolidaySilenceEnabled(v),
                          ),
                  ),
                ],
              ],
            ),
          ),
          Card(
            key: const Key('next_reminder_card'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '下一次已安排提醒',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (widget.nextReminderListenable != null)
                    ValueListenableBuilder<CourseReminder?>(
                      valueListenable: widget.nextReminderListenable!,
                      builder: (_, r, _) => r == null
                          ? const Text('暂无已安排提醒')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.courseName.isEmpty ? r.title : r.courseName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (widget.nextReminderAtListenable != null)
                                  ValueListenableBuilder<DateTime?>(
                                    valueListenable:
                                        widget.nextReminderAtListenable!,
                                    builder: (_, at, _) =>
                                        Text('提醒：${date(at ?? r.scheduledAt)}'),
                                  )
                                else
                                  Text('提醒：${date(r.scheduledAt)}'),
                                if (r.dateLabel.isNotEmpty) Text(r.dateLabel),
                                if (r.timeLabel.isNotEmpty)
                                  Text('上课：${r.timeLabel}'),
                                if (r.sectionLabel.isNotEmpty)
                                  Text(r.sectionLabel),
                                if (r.room.isNotEmpty) Text('教室：${r.room}'),
                                if (r.teacher.isNotEmpty)
                                  Text('教师：${r.teacher}'),
                                if (r.weekLabel.isNotEmpty) Text(r.weekLabel),
                              ],
                            ),
                    )
                  else if (widget.nextReminderAtListenable != null)
                    ValueListenableBuilder<DateTime?>(
                      valueListenable: widget.nextReminderAtListenable!,
                      builder: (_, n, _) =>
                          Text(n == null ? '暂无已安排提醒' : date(n)),
                    )
                  else
                    const Text('暂无已安排提醒'),
                ],
              ),
            ),
          ),
        ],
        if (!widget.optionsOnly && error != null)
          ListTile(
            title: Text(error!),
            trailing: TextButton(
              onPressed: () => load(forceReschedule: true),
              child: const Text('重试'),
            ),
          ),
        if (widget.optionsOnly) ...[
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('提醒设置', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  key: const Key('reminder_sound'),
                  leading: const Icon(Icons.music_note_outlined),
                  title: const Text('铃声'),
                  subtitle: Text(prefs.sound.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: loading
                      ? null
                      : () => open(
                          RingtoneSettingsPage(
                            repository: widget.repository,
                            service: widget.ringtoneService,
                            selected: prefs.sound,
                            onSaved: saved,
                          ),
                        ),
                ),
                if (permission.sdkInt >= 26 &&
                    permission.sdkInt < 30 &&
                    permission.channelSilent &&
                    !permission.explicitAudioConsent)
                  TextButton(
                    onPressed: loading
                        ? null
                        : () async {
                            try {
                              if (widget.scheduler
                                  case final NativeAlarmScheduler native) {
                                await native.configureAlert(
                                  prefs.sound,
                                  prefs.vibration,
                                );
                                await load();
                                await widget.onChanged(prefs.enabled);
                              }
                            } catch (_) {
                              message('请先在系统设置开启课程提醒渠道');
                            }
                          },
                    child: const Text('使用应用铃声和振动'),
                  ),
                if (permission.explicitAudioConsent)
                  TextButton(
                    onPressed: () => settings('soundChannel'),
                    child: const Text('通知声音设置'),
                  ),
                if (permission.channelUserSoundSet ||
                    (permission.sdkInt >= 26 &&
                        permission.sdkInt < 30 &&
                        permission.channelSilent &&
                        !permission.explicitAudioConsent))
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '当前声音由系统通知渠道控制。应用铃声选择已保留；请在课程提醒权限 → 设置通知中检查声音，应用不会额外绕过系统静默设置。',
                    ),
                  ),
                ListTile(
                  key: const Key('vibration_settings'),
                  leading: const Icon(Icons.vibration),
                  title: const Text('振动'),
                  subtitle: Text(prefs.vibration.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: loading
                      ? null
                      : () => open(
                          VibrationSettingsPage(
                            repository: widget.repository,
                            service: widget.vibrationService,
                            selected: prefs.vibration,
                            onSaved: saved,
                          ),
                        ),
                ),
                ListTile(
                  key: const Key('snooze_settings'),
                  leading: const Icon(Icons.snooze),
                  title: const Text('稍后提醒'),
                  subtitle: Text(
                    prefs.snoozeEnabled
                        ? '${prefs.snoozeMinutes} 分钟 · 共 ${prefs.maxRings} 次（含首次）'
                        : '已关闭 · 每节课仅一次',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: loading
                      ? null
                      : () => open(
                          SnoozeSettingsPage(
                            repository: widget.repository,
                            preferences: prefs,
                            onSaved: saved,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (error != null)
            ListTile(
              title: Text(error!),
              trailing: TextButton(
                onPressed: () => load(forceReschedule: true),
                child: const Text('重试'),
              ),
            ),
          Card(
            child: ListTile(
              title: const Text('课程提醒权限'),
              subtitle: Text(capability),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(
                ReminderPermissionsPage(
                  scheduler: widget.scheduler,
                  sound: prefs.sound,
                  onCapabilityChanged: () => widget.onChanged(prefs.enabled),
                ),
              ),
            ),
          ),
          ...widget.additionalSettings,
        ],
      ],
    ),
  );
  Future<void> test(Duration delay) async {
    try {
      await widget.scheduler.sendTest(sound: prefs.sound, delay: delay);
      message(delay == Duration.zero ? '通知已提交系统，请检查实际展示' : '测试已安排，可能受系统省电策略影响');
    } catch (_) {
      message('测试失败，请检查提醒能力');
    }
  }
}
