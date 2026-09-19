import 'package:flutter/material.dart';

import '../domain/models.dart';

class TimetablePage extends StatelessWidget {
  const TimetablePage({
    super.key,
    required this.semester,
    required this.courses,
    required this.displayWeek,
    this.remindersEnabled = false,
    this.onAdd,
    this.onImport,
    this.onReminders,
    this.onEdit,
    this.onDelete,
  });

  final Semester semester;
  final List<Course> courses;
  final int displayWeek;
  final bool remindersEnabled;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;
  final VoidCallback? onReminders;
  final ValueChanged<Course>? onEdit;
  final ValueChanged<Course>? onDelete;

  static const _weekdayNames = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  List<ScheduledCourse> _coursesFor(int weekday) {
    final result = <ScheduledCourse>[];
    for (final course in courses) {
      for (final session in course.sessions) {
        if (session.weekday == weekday && session.occursInWeek(displayWeek)) {
          result.add(ScheduledCourse(course: course, session: session));
        }
      }
    }
    result.sort(
      (a, b) => a.session.startSection.compareTo(b.session.startSection),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: onAdd == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onAdd,
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
                            '${semester.name} · 第 $displayWeek 周',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (onImport != null)
                      Tooltip(
                        message: '导入课表',
                        child: FilledButton.tonalIcon(
                          onPressed: onImport,
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('导入课表'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: onReminders,
                      icon: Icon(
                        remindersEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                      ),
                      tooltip: remindersEnabled ? '提醒已开启' : '提醒未开启',
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
                    onEdit: onEdit,
                    onDelete: onDelete,
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
                      '第 ${session.startSection}–${session.endSection} 节 · ${session.room} · ${course.teacher}',
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
