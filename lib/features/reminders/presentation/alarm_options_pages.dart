import 'dart:async';
import 'package:flutter/material.dart';
import '../data/ringtone_service.dart';
import '../domain/reminder_models.dart';
import '../domain/reminder_settings_repository.dart';

class RingtoneSettingsPage extends StatefulWidget {
  const RingtoneSettingsPage({
    super.key,
    required this.repository,
    required this.service,
    required this.selected,
    required this.onSaved,
  });
  final ReminderSettingsRepository repository;
  final RingtoneService service;
  final RingtoneSelection selected;
  final Future<void> Function() onSaved;
  @override
  State<RingtoneSettingsPage> createState() => _RingtoneSettingsPageState();
}

class _RingtoneSettingsPageState extends State<RingtoneSettingsPage> {
  late RingtoneSelection selected = widget.selected;
  bool busy = false;
  Timer? previewStop;
  @override
  void dispose() {
    previewStop?.cancel();
    unawaited(widget.service.stop());
    super.dispose();
  }

  Future<void> choose(RingtoneSelection sound) async {
    setState(() => busy = true);
    try {
      await widget.service.stop();
      await widget.repository.setReminderSound(sound);
      await widget.onSaved();
      if (mounted) setState(() => selected = sound);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存铃声失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> preview(RingtoneSelection sound) async {
    try {
      previewStop?.cancel();
      await widget.service.stop();
      await widget.service.preview(sound);
      previewStop = Timer(
        const Duration(seconds: 15),
        () => unawaited(widget.service.stop()),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法试听该音频')));
      }
    }
  }

  Widget option(RingtoneSelection sound) => ListTile(
    title: Text(sound.name),
    leading: Icon(
      selected.storageValue == sound.storageValue
          ? Icons.radio_button_checked
          : Icons.radio_button_off,
    ),
    onTap: busy ? null : () => choose(sound),
    trailing: sound.isSilent
        ? null
        : IconButton(
            tooltip: '试听${sound.name}',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: busy ? null : () => preview(sound),
          ),
  );
  Widget category(String name, List<RingtoneSelection> values) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(name, style: Theme.of(context).textTheme.titleSmall),
      ),
      ...values.map(option),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('铃声'),
      actions: [
        TextButton(
          onPressed: () => widget.service.stop(),
          child: const Text('停止试听'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        category('默认', [
          RingtoneSelection.systemDefault,
          RingtoneSelection.none,
        ]),
        category('经典铃声', [
          RingtoneSelection.chime,
          RingtoneSelection.alert,
          RingtoneSelection.xylophone,
        ]),
        category('自然铃声', [RingtoneSelection.water, RingtoneSelection.bell]),
        category('天气铃声', [RingtoneSelection.morning, RingtoneSelection.soft]),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('内置铃声为应用合成音。天气仅为铃声分类，不使用联网天气。'),
        ),
        if (selected.contentUri != null) category('自定义', [selected]),
        ListTile(
          leading: const Icon(Icons.audio_file_outlined),
          title: const Text('选择本地音频'),
          subtitle: const Text('音频复制到应用内，重启后仍可使用'),
          onTap: busy
              ? null
              : () async {
                  try {
                    final sound = await widget.service.importLocal();
                    if (sound != null) await choose(sound);
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        this.context,
                      ).showSnackBar(const SnackBar(content: Text('添加本地音频失败')));
                    }
                  }
                },
        ),
      ],
    ),
  );
}

class VibrationSettingsPage extends StatefulWidget {
  const VibrationSettingsPage({
    super.key,
    required this.repository,
    required this.service,
    required this.selected,
    required this.onSaved,
  });
  final ReminderSettingsRepository repository;
  final VibrationService service;
  final VibrationSelection selected;
  final Future<void> Function() onSaved;
  @override
  State<VibrationSettingsPage> createState() => _VibrationSettingsPageState();
}

class _VibrationSettingsPageState extends State<VibrationSettingsPage> {
  late VibrationSelection selected = widget.selected;
  bool busy = false;
  @override
  void dispose() {
    unawaited(widget.service.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('振动')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('振动采用独立节奏，响铃时按节奏循环。选择后预览一次；无振动仅关闭振动。'),
        ),
        ...VibrationSelection.values.map(
          (v) => ListTile(
            title: Text(v.label),
            leading: Icon(
              selected == v
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            onTap: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await widget.repository.setReminderVibration(v);
                      await widget.onSaved();
                      if (mounted) setState(() => selected = v);
                      final supported = await widget.service.preview(v);
                      if (!supported && mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('此设备没有可用的振动器')),
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('振动设置或预览失败')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
          ),
        ),
      ],
    ),
  );
}

class SnoozeSettingsPage extends StatefulWidget {
  const SnoozeSettingsPage({
    super.key,
    required this.repository,
    required this.preferences,
    required this.onSaved,
  });
  final ReminderSettingsRepository repository;
  final ReminderPreferences preferences;
  final Future<void> Function() onSaved;
  @override
  State<SnoozeSettingsPage> createState() => _SnoozeSettingsPageState();
}

class _SnoozeSettingsPageState extends State<SnoozeSettingsPage> {
  late bool enabled = widget.preferences.snoozeEnabled;
  late int interval = widget.preferences.snoozeMinutes;
  late int count = widget.preferences.maxRings;
  bool busy = false;
  Future<void> save(Future<void> Function() write, VoidCallback update) async {
    setState(() => busy = true);
    try {
      await write();
      await widget.onSaved();
      if (mounted) setState(update);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存稍后提醒失败')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('稍后提醒')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          key: const Key('snooze_enabled'),
          title: const Text('稍后提醒'),
          subtitle: const Text('关闭后，每节课仅提醒一次'),
          value: enabled,
          onChanged: busy
              ? null
              : (v) => save(
                  () => widget.repository.setReminderSnoozeEnabled(v),
                  () => enabled = v,
                ),
        ),
        DropdownButtonFormField<int>(
          key: const Key('snooze_interval'),
          initialValue: interval,
          decoration: const InputDecoration(labelText: '间隔'),
          items: [5, 10, 15, 30]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v 分钟')))
              .toList(),
          onChanged: !enabled || busy
              ? null
              : (v) {
                  if (v != null) {
                    save(
                      () => widget.repository.setReminderSnoozeMinutes(v),
                      () => interval = v,
                    );
                  }
                },
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          key: const Key('max_rings'),
          initialValue: count,
          decoration: const InputDecoration(labelText: '总次数（含首次）'),
          items: [2, 3, 5, 10]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v 次')))
              .toList(),
          onChanged: !enabled || busy
              ? null
              : (v) {
                  if (v != null) {
                    save(
                      () => widget.repository.setReminderMaxRings(v),
                      () => count = v,
                    );
                  }
                },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '次数包含首次，3 次表示首次和后续 2 次。无人处理时按间隔重复；稍后按钮也使用该间隔。每次最长 60 秒，上课时停止全部提醒；关闭本节课会取消其后续次数。',
          ),
        ),
      ],
    ),
  );
}
