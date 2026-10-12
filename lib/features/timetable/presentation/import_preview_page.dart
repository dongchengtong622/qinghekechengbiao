import 'package:flutter/material.dart';
import '../data/course_repository.dart';
import '../data/timetable_import.dart';
import '../domain/models.dart';
import 'course_editor_page.dart';
import '../domain/school_schedule.dart';
import '../data/import_time_plan.dart';
import 'section_split_page.dart';

typedef ConfirmTimetableImport =
    Future<ImportSummary> Function(ImportPreview preview);

class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({
    super.key,
    required this.preview,
    required this.changes,
    required this.onConfirm,
    this.onPreview,
    this.maxScheduleSection = 12,
    this.schedule,
    this.existingTimes = const [],
  });
  final ImportPreview preview;
  final SchoolSchedule? schedule;
  final List<SectionRangeTime> existingTimes;
  final int maxScheduleSection;
  final ImportSummary changes;
  final ConfirmTimetableImport onConfirm;
  final Future<ImportSummary> Function(ImportPreview)? onPreview;
  @override
  State<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends State<ImportPreviewPage> {
  late ImportPreview _draft;
  late ImportSummary _changes;
  bool _importing = false;
  final _acknowledged = <String>{};
  final _timeChoices = <String, SectionRangeTime>{};
  SchoolSchedule get _baseSchedule =>
      widget.schedule ?? SchoolSchedule.defaults();
  ImportTimePlan get _timePlan => ImportTimePlan(
    _draft,
    _baseSchedule,
    existingTimes: widget.existingTimes,
  );
  String _timeSourceLabel(SectionRangeTime range) {
    if (range.source == CourseTimeSource.schedule) return '默认作息';
    bool matches(SectionRangeTime value) =>
        value.key == range.key &&
        value.startMinute == range.startMinute &&
        value.endMinute == range.endMinute;
    final fromThisImport =
        _draft.importedTimes.any(matches) ||
        _draft.courses.any(
          (course) => course.sessions.any(
            (session) =>
                session.startSection == range.startSection &&
                session.endSection == range.endSection &&
                (session.startMinute == null ||
                    session.startMinute == range.startMinute) &&
                (session.endMinute == null ||
                    session.endMinute == range.endMinute) &&
                (session.startMinute != null || session.endMinute != null) &&
                session.timeSource == range.source,
          ),
        );
    if (range.source == CourseTimeSource.custom) {
      return fromThisImport ? '手动设置' : '当前作息 · 手动设置';
    }
    return fromThisImport ? '课表导入' : '当前作息 · 此前导入';
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.preview;
    _timeChoices.addAll(_draft.timeChoices);
    _changes = widget.changes;
  }

  Future<void> _update(
    List<Course> courses, {
    Semester? semester,
    bool? replace,
  }) async {
    setState(() {
      _draft = ImportPreview(
        semester: semester ?? _draft.semester,
        courses: courses,
        warnings: _draft.warnings,
        importedTimes: _draft.importedTimes,
        timeChoices: Map.of(_timeChoices),
        replaceExisting: replace ?? _draft.replaceExisting,
        courseReviews: {
          for (final course in courses)
            if (_draft.courseReviews[course.id] case final review?)
              course.id: review,
        },
      );
      _importing = true;
    });
    try {
      if (courses.isNotEmpty && widget.onPreview != null) {
        _changes = await widget.onPreview!(_draft);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('预览更新失败，请重试：$error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Course _copyCourse(
    Course c,
    List<CourseSession> sessions, {
    Course? fields,
  }) => Course(
    id: c.id,
    semesterId: _draft.semester.id,
    source: CourseSource.cdcasKingo,
    externalId: c.externalId ?? c.id,
    name: fields?.name ?? c.name,
    teacher: fields?.teacher ?? c.teacher,
    colorValue: fields?.colorValue ?? c.colorValue,
    sessions: sessions,
  );
  Future<void> _edit(int index, int sessionIndex) async {
    final c = _draft.courses[index];
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CourseEditorPage(
          semesterId: _draft.semester.id,
          maxScheduleSection: widget.maxScheduleSection,
          initialCourse: _copyCourse(c, [
            _timePlan.invalidKeys.isEmpty
                ? _timePlan.schedule.resolve(
                    c.sessions[sessionIndex],
                    semesterId: _draft.semester.id,
                  )
                : c.sessions[sessionIndex],
          ]),
          schedule: _timePlan.schedule,
          onSave: (saved) async {
            final time = saved.sessions.first;
            if (time.timeSource == CourseTimeSource.custom &&
                time.startMinute != null &&
                time.endMinute != null) {
              final choice = SectionRangeTime(
                semesterId: _draft.semester.id,
                startSection: time.startSection,
                endSection: time.endSection,
                startMinute: time.startMinute!,
                endMinute: time.endMinute!,
                source: CourseTimeSource.custom,
              );
              _timeChoices[choice.key] = choice;
            }
            final sessions = List<CourseSession>.of(c.sessions)
              ..[sessionIndex] = saved.sessions.first;
            final courses = List<Course>.of(_draft.courses)
              ..[index] = _copyCourse(c, sessions, fields: saved);
            _acknowledged.add(c.id);
            await _update(courses);
          },
        ),
      ),
    );
  }

  Future<void> _add() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CourseEditorPage(
          semesterId: _draft.semester.id,
          maxScheduleSection: widget.maxScheduleSection,
          schedule: _timePlan.schedule,
          onSave: (saved) async {
            await _update([
              ..._draft.courses,
              _copyCourse(saved, saved.sessions),
            ]);
          },
        ),
      ),
    );
  }

  int get _requiredWeeks => _draft.courses.fold<int>(
    1,
    (maxWeek, course) => course.sessions.fold<int>(
      maxWeek,
      (maxWeek, session) =>
          session.endWeek > maxWeek ? session.endWeek : maxWeek,
    ),
  );

  Future<void> _semester() async {
    final value = await askImportSemester(
      context,
      _draft.semester,
      minimumWeeks: _requiredWeeks,
    );
    if (value != null) await _update(_draft.courses, semester: value);
  }

  Future<void> _extendSemester() => _update(
    _draft.courses,
    semester: Semester(
      id: _draft.semester.id,
      name: _draft.semester.name,
      firstWeekStart: _draft.semester.firstWeekStart,
      totalWeeks: _requiredWeeks,
    ),
  );

  Future<void> _confirm() async {
    if (_importing || _draft.courses.isEmpty) return;
    if (_draft.semester.totalWeeks < _requiredWeeks) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('课程已完整保留，请先将学期调整为至少 $_requiredWeeks 周再导入。')),
      );
      return;
    }
    final plan = _timePlan;
    if (plan.invalidKeys.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('部分时间无法与作息匹配，请补全开始和结束时间。')));
      return;
    }
    if (plan.conflicts.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择同节次课程统一使用的时间。')));
      return;
    }
    final unreviewed = _draft.courses.where((course) {
      final review = _draft.courseReviews[course.id];
      return review != null &&
          review.fieldsNeedingReview.isNotEmpty &&
          !_acknowledged.contains(course.id);
    }).length;
    if (unreviewed > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('还有 $unreviewed 门课程的识别字段需要核对。')));
      return;
    }
    final invalid = _draft.courses.any(
      (c) =>
          c.name.trim().isEmpty ||
          c.sessions.any((s) => s.endWeek > _draft.semester.totalWeeks),
    );
    if (invalid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请核对课程名称、周次，并补齐超出当前作息表节次的自定义时间')),
      );
      return;
    }
    var confirmSchedule = plan.schedule;
    if (plan.missingCount > 0) {
      final values = {
        for (final v
            in confirmSchedule.semesterSections[_draft.semester.id] ??
                <SectionTime>[])
          v.section: v,
      };
      for (final course in _draft.courses) {
        for (final session in course.sessions) {
          if (session.timeSource != CourseTimeSource.schedule ||
              session.startMinute != null ||
              session.endMinute != null) {
            continue;
          }
          if (_draft.importedTimes.any(
            (r) =>
                r.startSection <= session.endSection &&
                r.endSection >= session.startSection,
          )) {
            continue;
          }
          for (var n = session.startSection; n <= session.endSection; n++) {
            // Defaults must come from one coherent template, not legacy range evidence.
            final known = values[n];
            final fallback = known ?? confirmSchedule.section(n);
            if (fallback != null) values[n] = fallback;
          }
        }
      }
      confirmSchedule = confirmSchedule.withSemesterSections(
        _draft.semester.id,
        values.values.toList()..sort((a, b) => a.section.compareTo(b.section)),
      );
    }
    if (plan.missingCount > 0) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认使用默认作息'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('课表中缺少完整时间。课表已有时间会保留，缺少的部分使用以下默认作息。'),
                  ..._scheduleLabels(confirmSchedule).map(Text.new),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回核对'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('使用以上时间并导入'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    final confirmedSections = await confirmSectionSplits(
      context,
      confirmSchedule,
      _draft.semester.id,
      rangeKeys: {
        for (final r in _draft.importedTimes) r.key,
        for (final c in _draft.courses)
          for (final s in c.sessions)
            '${_draft.semester.id}:${s.startSection}:${s.endSection}',
      },
      freshKeys: {
        for (final r in _draft.importedTimes) r.key,
        for (final c in _draft.courses)
          for (final s in c.sessions)
            if (s.timeSource != CourseTimeSource.schedule &&
                s.startMinute != null &&
                s.endMinute != null)
              '${_draft.semester.id}:${s.startSection}:${s.endSection}',
      },
      useDefaultMissing: plan.missingCount > 0,
    );
    if (confirmedSections == null || !mounted) return;
    try {
      for (final c in _draft.courses) {
        for (final s in c.sessions) {
          final time = confirmedSections.resolve(
            s,
            semesterId: _draft.semester.id,
          );
          if (time.startMinute == null || time.endMinute == null) {
            throw const FormatException('请补齐超出当前作息表节次的开始和结束时间。');
          }
        }
      }
    } on FormatException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    _draft = _draft.withSectionSchedule(confirmedSections);
    setState(() => _importing = true);
    try {
      if (widget.onPreview != null) {
        final fresh = await widget.onPreview!(_draft);
        if (fresh.removed != _changes.removed ||
            fresh.updated != _changes.updated ||
            fresh.inserted != _changes.inserted) {
          _changes = fresh;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('课表数据已变化，请核对更新后的数量再确认')),
            );
          }
          return;
        }
      }
      final summary = await widget.onConfirm(_draft);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(summary);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showSource(ImportCourseReview review) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导入原文'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [SelectableText(review.rawText)],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  List<String> _scheduleLabels(SchoolSchedule schedule) => [
    for (final s in schedule.sections)
      '第${s.section}节 ${SectionRangeTime.minuteLabel(schedule.range(_draft.semester.id, s.section, s.section)?.startMinute ?? s.startMinute)}–${SectionRangeTime.minuteLabel(schedule.range(_draft.semester.id, s.section, s.section)?.endMinute ?? s.endMinute)}',
    for (final r in schedule.rangeTimes.where(
      (r) =>
          r.semesterId == _draft.semester.id && r.startSection != r.endSection,
    ))
      '第${r.startSection}–${r.endSection}节 ${r.label}（整段时间，优先于单节作息）',
  ];
  Widget _timingNotice() {
    final plan = _timePlan;
    if (plan.missingCount == 0) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFFFF4D6),
      child: ExpansionTile(
        title: Text(
          plan.missingCount > 0
              ? '课表缺少完整时间：${plan.missingCount} 个时段需补用默认作息'
              : '已识别课表时间，将按课表时间导入',
        ),
        subtitle: const Text('查看每节开始、结束时间及同节次统一时间'),
        children: [
          for (final label in _scheduleLabels(plan.schedule))
            ListTile(dense: true, title: Text(label)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('确认导入')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_draft.semester.name),
          subtitle: Text(
            '第一周 ${_draft.semester.firstWeekStart.toString().split(' ').first} · ${_draft.semester.totalWeeks} 周',
          ),
          trailing: TextButton(
            onPressed: _importing ? null : _semester,
            child: const Text('修改学期'),
          ),
        ),
        if (_requiredWeeks > _draft.semester.totalWeeks)
          Card(
            color: const Color(0xFFFFF4D6),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '课程到第 $_requiredWeeks 周，当前学期只有 ${_draft.semester.totalWeeks} 周',
                  ),
                  const Text('全部课程周次已保留。请调整学期周数后再导入；第一周星期一可在导入后修改。'),
                  TextButton(
                    onPressed: _importing ? null : _extendSemester,
                    child: Text('调整为 $_requiredWeeks 周'),
                  ),
                ],
              ),
            ),
          ),
        Text(
          '${_draft.courses.length} 门课程 · ${_draft.courses.fold<int>(0, (n, c) => n + c.sessions.length)} 个上课时段',
        ),
        const SizedBox(height: 8),
        Text(
          _draft.courses.isEmpty
              ? '尚无课程，请手动补充'
              : '将新增 ${_changes.inserted} · 更新 ${_changes.updated} · 移除 ${_changes.removed}',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('替换本学期已导入课程'),
          subtitle: const Text('关闭时保留其他课程；同一来源的重复课程仍会更新。'),
          value: _draft.replaceExisting,
          onChanged: _importing
              ? null
              : (v) => _update(_draft.courses, replace: v),
        ),
        _timingNotice(),
        for (final entry in _timePlan.conflicts.entries)
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '第${entry.value.first.startSection}–${entry.value.first.endSection}节时间冲突',
                  ),
                  subtitle: const Text('请选择本学期同节次课程统一使用的时间'),
                ),
                for (final r in entry.value)
                  ListTile(
                    title: Text('${r.label}（${_timeSourceLabel(r)}）'),
                    trailing: const Icon(Icons.check_circle_outline),
                    onTap: _importing
                        ? null
                        : () {
                            _timeChoices[entry.key] = r;
                            _update(_draft.courses);
                          },
                  ),
              ],
            ),
          ),
        if (_draft.warnings.length > 4)
          Card(
            color: const Color(0xFFFFF4D6),
            child: ExpansionTile(
              title: Text('识别提示（${_draft.warnings.length} 条）'),
              subtitle: const Text('有内容需要核对，请逐门检查课程后再导入。'),
              children: [
                for (final warning in _draft.warnings)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(warning),
                    ),
                  ),
              ],
            ),
          )
        else if (_draft.warnings.isNotEmpty)
          Card(
            color: const Color(0xFFFFF4D6),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('识别提示'),
                  for (final warning in _draft.warnings) Text(warning),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        for (var i = 0; i < _draft.courses.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                ListTile(
                  title: Text(_draft.courses[i].name),
                  subtitle: Text(
                    _draft.courses[i].teacher.isEmpty
                        ? '教师待确认'
                        : _draft.courses[i].teacher,
                  ),
                  trailing: IconButton(
                    tooltip: '删除识别结果',
                    onPressed: _importing
                        ? null
                        : () => _update(
                            List<Course>.of(_draft.courses)..removeAt(i),
                          ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
                if (_draft.courseReviews[_draft.courses[i].id]
                    case final review?) ...[
                  if (review.fieldsNeedingReview.isNotEmpty)
                    CheckboxListTile(
                      title: Text('已核对${review.fieldsNeedingReview.join('、')}'),
                      subtitle: const Text('请对照 Excel 原文件或导入原文修正后再确认。'),
                      value: _acknowledged.contains(_draft.courses[i].id),
                      onChanged: _importing
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _acknowledged.add(_draft.courses[i].id);
                              } else {
                                _acknowledged.remove(_draft.courses[i].id);
                              }
                            }),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _showSource(review),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('查看导入原文'),
                    ),
                  ),
                ],
                for (var j = 0; j < _draft.courses[i].sessions.length; j++)
                  ListTile(
                    dense: true,
                    title: Text(_description(_draft.courses[i].sessions[j])),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _importing ? null : () => _edit(i, j),
                  ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _importing ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('补充遗漏课程'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _importing || _draft.courses.isEmpty ? null : _confirm,
          icon: const Icon(Icons.download_done),
          label: Text(_importing ? '正在导入…' : '导入课表'),
        ),
      ],
    ),
  );
  String _description(CourseSession s) {
    String? label;
    try {
      label = _timePlan.schedule
          .resolve(s, semesterId: _draft.semester.id)
          .timeLabel;
    } on FormatException {
      label = '时间冲突，请修正';
    }
    return '周${'一二三四五六日'[s.weekday - 1]} 第${s.startSection}-${s.endSection}节${label == null ? '' : ' · $label'} · ${s.startWeek}-${s.endWeek}周${s.pattern == WeekPattern.oddWeeks
        ? '（单周）'
        : s.pattern == WeekPattern.evenWeeks
        ? '（双周）'
        : ''} · ${s.room.isEmpty ? '教室待确认' : s.room}';
  }
}

Future<Semester?> askImportSemester(
  BuildContext context,
  Semester current, {
  int minimumWeeks = 1,
}) async {
  final name = TextEditingController(text: current.name),
      weeks = TextEditingController(text: '${current.totalWeeks}');
  var date = current.firstWeekStart;
  final form = GlobalKey<FormState>();
  final result = await showDialog<Semester>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('设置学期'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '学期名称'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写学期名称' : null,
                ),
                TextFormField(
                  controller: weeks,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '学期总周数'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1 || n > 60) return '请输入 1 至 60 周';
                    if (n < minimumWeeks) {
                      return '已有课程到第 $minimumWeeks 周，请填写至少 $minimumWeeks 周';
                    }
                    return null;
                  },
                ),
                TextButton(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null) setDialog(() => date = selected);
                  },
                  child: Text('第一周星期一：${date.toString().split(' ').first}'),
                ),
                const Text('请填写第一教学周的星期一，课表日期和提醒将据此计算。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              if (date.weekday != DateTime.monday) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('第一周日期请选择星期一')));
                return;
              }
              Navigator.pop(
                dialogContext,
                Semester(
                  id: current.id,
                  name: name.text.trim(),
                  firstWeekStart: date,
                  totalWeeks: int.parse(weeks.text),
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
  // Dialog controllers are disposed after its closing transition.
  Future<void>.delayed(const Duration(seconds: 1), () {
    name.dispose();
    weeks.dispose();
  });
  return result;
}
