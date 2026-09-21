import 'package:flutter/material.dart';

import '../domain/models.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({
    super.key,
    required this.semester,
    required this.courses,
    required this.initialDisplayWeek,
    required this.currentWeek,
    this.remindersEnabled = false,
    this.onAdd,
    this.onImport,
    this.onReminders,
    this.onEdit,
    this.onDelete,
  });

  final Semester semester;
  final List<Course> courses;
  final int initialDisplayWeek;
  final int? currentWeek;
  final bool remindersEnabled;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;
  final VoidCallback? onReminders;
  final ValueChanged<Course>? onEdit;
  final ValueChanged<Course>? onDelete;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const _weekdayNames = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  late int _displayWeek;

  @override
  void initState() {
    super.initState();
    _displayWeek = _clampWeek(widget.initialDisplayWeek);
  }

  @override
  void didUpdateWidget(covariant TimetablePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semester.id != widget.semester.id) {
      _displayWeek = _clampWeek(widget.initialDisplayWeek);
    } else if (_displayWeek > widget.semester.totalWeeks) {
      _displayWeek = widget.semester.totalWeeks;
    }
  }

  int _clampWeek(int week) {
    if (week < 1) return 1;
    if (week > widget.semester.totalWeeks) return widget.semester.totalWeeks;
    return week;
  }

  List<ScheduledCourse> _coursesFor(int weekday) {
    final result = <ScheduledCourse>[];
    for (final course in widget.courses) {
      for (final session in course.sessions) {
        if (session.weekday == weekday && session.occursInWeek(_displayWeek)) {
          result.add(ScheduledCourse(course: course, session: session));
        }
      }
    }
    result.sort(
      (a, b) => a.session.startSection.compareTo(b.session.startSection),
    );
    return result;
  }

  String get _weekLabel => _displayWeek == widget.currentWeek
      ? '第 $_displayWeek 周 · 本周'
      : '第 $_displayWeek 周';

  Widget _weekSelector(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        PopupMenuButton<int>(
          key: const Key('week_selector'),
          initialValue: _displayWeek,
          tooltip: '选择周次',
          onSelected: (week) => setState(() => _displayWeek = week),
          itemBuilder: (context) =>
              List.generate(widget.semester.totalWeeks, (index) {
                final week = index + 1;
                return PopupMenuItem<int>(
                  value: week,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          week == widget.currentWeek
                              ? '第 $week 周 · 本周'
                              : '第 $week 周',
                        ),
                      ),
                      if (week == _displayWeek)
                        const Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                );
              }),
          child: Semantics(
            button: true,
            label: '选择周次，当前$_weekLabel',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _weekLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: color),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down_rounded, color: color),
                ],
              ),
            ),
          ),
        ),
        if (widget.currentWeek != null && _displayWeek != widget.currentWeek)
          TextButton(
            key: const Key('return_to_current_week'),
            onPressed: () =>
                setState(() => _displayWeek = _clampWeek(widget.currentWeek!)),
            child: const Text('回到本周'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: widget.onAdd == null
          ? null
          : FloatingActionButton.extended(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加课程'),
              tooltip: '添加课程',
            ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '青禾课表',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.semester.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          _weekSelector(context),
                        ],
                      ),
                    ),
                    if (widget.onImport != null)
                      Tooltip(
                        message: '导入课表',
                        child: FilledButton.tonalIcon(
                          onPressed: widget.onImport,
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('导入课表'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: widget.onReminders,
                      icon: Icon(
                        widget.remindersEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                      ),
                      tooltip: widget.remindersEnabled ? '提醒已开启' : '提醒未开启',
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList.builder(
                itemCount: DateTime.daysPerWeek,
                itemBuilder: (context, index) {
                  final weekday = index + 1;
                  return _DaySection(
                    name: _weekdayNames[index],
                    courses: _coursesFor(weekday),
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.name,
    required this.courses,
    this.onEdit,
    this.onDelete,
  });

  final String name;
  final List<ScheduledCourse> courses;
  final ValueChanged<Course>? onEdit;
  final ValueChanged<Course>? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    courses.isEmpty ? '无课' : '${courses.length} 节课',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (courses.isNotEmpty) const SizedBox(height: 12),
              for (final item in courses) ...[
                _CourseTile(item: item, onEdit: onEdit, onDelete: onDelete),
                if (item != courses.last) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.item, this.onEdit, this.onDelete});

  final ScheduledCourse item;
  final ValueChanged<Course>? onEdit;
  final ValueChanged<Course>? onDelete;

  Future<void> _confirmDelete(BuildContext context, Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确认删除“${course.name}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete?.call(course);
  }

  @override
  Widget build(BuildContext context) {
    final course = item.course;
    final session = item.session;
    final color = Color(course.colorValue);
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit == null ? null : () => onEdit!(course),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '第 ${session.startSection}–${session.endSection} 节'
                      '${session.timeLabel == null ? '' : ' · ${session.timeLabel}'}'
                      ' · ${session.room} · ${course.teacher}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                PopupMenuButton<String>(
                  tooltip: '课程操作',
                  onSelected: (_) => _confirmDelete(context, course),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除课程')),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
