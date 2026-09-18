import 'package:flutter/material.dart';

import '../domain/models.dart';

class TimetablePage extends StatelessWidget {
  const TimetablePage({
    super.key,
    required this.semester,
    required this.courses,
    required this.displayWeek,
  });

  final Semester semester;
  final List<Course> courses;
  final int displayWeek;

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
                    IconButton.filledTonal(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none_rounded),
                      tooltip: '提醒',
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
  const _DaySection({required this.name, required this.courses});

  final String name;
  final List<ScheduledCourse> courses;

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
                _CourseTile(item: item),
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
  const _CourseTile({required this.item});

  final ScheduledCourse item;

  @override
  Widget build(BuildContext context) {
    final course = item.course;
    final session = item.session;
    final color = Color(course.colorValue);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
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
        ],
      ),
    );
  }
}
