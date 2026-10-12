import 'package:flutter/material.dart';
import '../../../core/widgets/compact_action_menu.dart';

import '../domain/models.dart';
import '../domain/school_schedule.dart';
import 'weekly_timetable_grid.dart';
import '../../../core/time/section_times.dart';
import '../../../core/time/shanghai_time.dart';

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
    this.onSettings,
    this.onWidgets,
    this.onEdit,
    this.onDelete,
    this.now,
    this.initialGridView = false,
    this.scheduleSectionCount = 12,
    this.schedule,
    this.onViewChanged,
  });

  final DateTime? now;
  final bool initialGridView;
  final int scheduleSectionCount;
  final SchoolSchedule? schedule;
  final ValueChanged<bool>? onViewChanged;
  final Semester semester;
  final List<Course> courses;
  final int initialDisplayWeek;
  final int? currentWeek;
  final bool remindersEnabled;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;
  final VoidCallback? onReminders;
  final VoidCallback? onSettings, onWidgets;
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
  bool _gridView = false;
  int? _selectedDay;
  bool _outsideSemesterToday = false;
  DateTime get _now => widget.now ?? ShanghaiTime.now();

  @override
  void initState() {
    super.initState();
    _displayWeek = _clampWeek(widget.initialDisplayWeek);
    _gridView = widget.initialGridView;
    if (!_gridView && widget.semester.weekFor(_now) == _displayWeek) {
      _selectedDay = _now.weekday;
    }
  }

  @override
  void didUpdateWidget(covariant TimetablePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGridView != widget.initialGridView) {
      _gridView = widget.initialGridView;
    }
    if (oldWidget.semester.id != widget.semester.id ||
        oldWidget.semester.firstWeekStart != widget.semester.firstWeekStart ||
        oldWidget.semester.totalWeeks != widget.semester.totalWeeks) {
      _displayWeek = _clampWeek(widget.initialDisplayWeek);
      _outsideSemesterToday = false;
      _selectedDay = !_gridView && widget.semester.weekFor(_now) == _displayWeek
          ? _now.weekday
          : null;
    } else if (_displayWeek > widget.semester.totalWeeks) {
      _displayWeek = widget.semester.totalWeeks;
    }
  }

  int _clampWeek(int week) {
    if (week < 1) return 1;
    if (week > widget.semester.totalWeeks) return widget.semester.totalWeeks;
    return week;
  }

  List<Course>? _cachedCourses;
  SchoolSchedule? _cachedSchedule;
  int? _cachedWeek;
  Map<int, List<ScheduledCourse>> _coursesByDay = {};

  List<ScheduledCourse> _coursesFor(int weekday) {
    if (_outsideSemesterToday) return const [];
    if (!identical(_cachedCourses, widget.courses) ||
        !identical(_cachedSchedule, widget.schedule) ||
        _cachedWeek != _displayWeek) {
      final schedule = widget.schedule ?? SchoolSchedule.defaults();
      final days = <int, List<ScheduledCourse>>{};
      for (final original in widget.courses) {
        final course = Course(
          id: original.id,
          semesterId: original.semesterId,
          source: original.source,
          externalId: original.externalId,
          name: original.name,
          teacher: original.teacher,
          colorValue: original.colorValue,
          sessions: original.sessions
              .map(
                (session) =>
                    schedule.resolve(session, semesterId: original.semesterId),
              )
              .toList(),
        );
        for (final session in course.sessions) {
          if (session.occursInWeek(_displayWeek)) {
            (days[session.weekday] ??= []).add(
              ScheduledCourse(course: course, session: session),
            );
          }
        }
      }
      for (final day in days.values) {
        day.sort(
          (a, b) => a.session.startSection.compareTo(b.session.startSection),
        );
      }
      _coursesByDay = days;
      _cachedCourses = widget.courses;
      _cachedSchedule = widget.schedule;
      _cachedWeek = _displayWeek;
    }
    return _coursesByDay[weekday] ?? const [];
  }

  String get _weekLabel => _outsideSemesterToday
      ? '当前学期外 · 今天'
      : _displayWeek == widget.currentWeek
      ? '第 $_displayWeek 周 · 本周'
      : '第 $_displayWeek 周';

  Widget _weekSelector(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          PopupMenuButton<int>(
            key: const Key('week_selector'),
            popUpAnimationStyle: AnimationStyle.noAnimation,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
            constraints: const BoxConstraints(
              minWidth: 168,
              maxWidth: 220,
              maxHeight: 400,
            ),
            tooltip: '选择周次',
            onSelected: (week) => setState(() {
              _displayWeek = week;
              _outsideSemesterToday = false;
            }),
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
            child: SizedBox(
              width: constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : null,
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Semantics(
                  button: true,
                  label: '选择周次，当前$_weekLabel',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _outsideSemesterToday
                              ? '当前学期外 · 今天'
                              : '第 $_displayWeek 周',
                          style: TextStyle(
                            color: color,
                            fontSize: _outsideSemesterToday ? 18 : 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (!_outsideSemesterToday &&
                            _displayWeek == widget.currentWeek) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· 本周',
                            style: TextStyle(
                              color: color,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down_rounded, color: color),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_gridView &&
              widget.currentWeek != null &&
              (_outsideSemesterToday || _displayWeek != widget.currentWeek))
            TextButton(
              key: const Key('return_to_current_week'),
              onPressed: () => setState(() {
                _displayWeek = _clampWeek(widget.currentWeek!);
                _outsideSemesterToday = false;
              }),
              child: const Text('回到本周'),
            ),
        ],
      ),
    );
  }

  DateTime _dateFor(int weekday) {
    if (_outsideSemesterToday) {
      final today = DateTime(_now.year, _now.month, _now.day);
      return today.add(Duration(days: weekday - today.weekday));
    }
    return widget.semester.firstWeekStart.add(
      Duration(days: (_displayWeek - 1) * 7 + weekday - 1),
    );
  }

  void _selectToday() {
    final week = widget.semester.weekFor(_now);
    _outsideSemesterToday = week == null;
    if (week != null) _displayWeek = week;
    _selectedDay = _now.weekday;
  }

  Widget _returnToToday() => TextButton(
    key: const Key('return_to_today'),
    onPressed: () => setState(_selectToday),
    child: const Text('回到今天'),
  );
  bool _isToday(int weekday) {
    final d = _dateFor(weekday), n = _now;
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  void _setView(bool grid) {
    setState(() {
      _gridView = grid;
      if (grid) {
        _selectedDay = null;
      } else {
        _selectToday();
      }
    });
    widget.onViewChanged?.call(grid);
  }

  Widget _navigation() => Column(
    children: [
      Row(
        children: List.generate(7, (index) {
          final day = index + 1, date = _dateFor(index + 1);
          return Expanded(
            child: InkWell(
              key: Key('day_nav_$day'),
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                _selectedDay = day;
                _gridView = false;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedDay == day
                      ? Theme.of(context).colorScheme.primaryContainer
                      : _isToday(day)
                      ? const Color(0xFFE2EFE7)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _weekdayNames[index],
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '${date.day}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_isToday(day))
                      const Text('今天', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_selectedDay != _now.weekday || !_isToday(_now.weekday))
            _returnToToday(),
          ChoiceChip(
            key: const Key('view_list'),
            label: const Text('列表'),
            selected: !_gridView,
            onSelected: (_) => _setView(false),
          ),
          ChoiceChip(
            key: const Key('view_grid'),
            label: const Text('周表'),
            selected: _gridView,
            onSelected: (_) => _setView(true),
          ),
        ],
      ),
    ],
  );
  Widget _grid() => WeeklyTimetableGrid(
    sectionCount: widget.scheduleSectionCount,
    schedule: widget.schedule,
    semesterId: widget.semester.id,
    courses: [for (var day = 1; day <= 7; day++) ..._coursesFor(day)],
    dateFor: _dateFor,
    isToday: _isToday,
    onDayTap: _showGridDay,
  );

  List<Widget> _actions(BuildContext contextForMenu) => [
    IconButton(
      onPressed: widget.onAdd,
      icon: const Icon(Icons.add),
      tooltip: '添加课程',
    ),
    CompactActionMenu(
      key: const Key('home_more'),
      onSelected: (v) {
        switch (v) {
          case 'import':
            widget.onImport?.call();
          case 'reminders':
            widget.onReminders?.call();
          case 'widgets':
            widget.onWidgets?.call();
          case 'settings':
            widget.onSettings?.call();
        }
      },
      entries: [
        const CompactMenuEntry('import', Icons.file_download_outlined, '导入课表'),
        CompactMenuEntry(
          'reminders',
          widget.remindersEnabled
              ? Icons.notifications_active_rounded
              : Icons.notifications_none,
          '课程提醒',
          tooltip: widget.remindersEnabled ? '提醒已开启' : '提醒未开启',
        ),
        const CompactMenuEntry('widgets', Icons.widgets_outlined, '桌面小组件'),
        const CompactMenuEntry('settings', Icons.settings_outlined, '设置'),
      ],
    ),
  ];

  Widget _weekPage(BuildContext context) => Scaffold(
    appBar: AppBar(title: _weekSelector(context), actions: _actions(context)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.currentWeek != null &&
                    (_outsideSemesterToday ||
                        _displayWeek != widget.currentWeek))
                  TextButton(
                    key: const Key('return_to_current_week'),
                    onPressed: () => setState(() {
                      _displayWeek = _clampWeek(widget.currentWeek!);
                      _outsideSemesterToday = false;
                    }),
                    child: const Text('回到本周'),
                  ),
                _returnToToday(),
                ChoiceChip(
                  key: const Key('view_list'),
                  label: const Text('列表'),
                  selected: false,
                  onSelected: (_) => _setView(false),
                ),
                ChoiceChip(
                  key: const Key('view_grid'),
                  label: const Text('周表'),
                  selected: true,
                  onSelected: (_) => _setView(true),
                ),
              ],
            ),
            Expanded(child: _grid()),
          ],
        ),
      ),
    ),
  );

  void _showGridDay(int day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text('${_weekdayNames[day - 1]}全部课程（含时间冲突）'),
            for (final item in _coursesFor(day))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _CourseTile(
                  item: item,
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_gridView) return _weekPage(context);
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
                          _weekSelector(context),
                          Text(
                            '${_now.month}月${_now.day}日 · 今天',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    ..._actions(context),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _navigation()),
            ),
            if (_gridView)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                sliver: SliverToBoxAdapter(child: _grid()),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
                sliver: SliverList.builder(
                  itemCount: _selectedDay == null ? DateTime.daysPerWeek : 1,
                  itemBuilder: (context, index) {
                    final weekday = _selectedDay ?? index + 1;
                    return _DaySection(
                      name:
                          '${_weekdayNames[weekday - 1]} · ${_dateFor(weekday).month}/${_dateFor(weekday).day}${_isToday(weekday) ? ' · 今天' : ''}',
                      isToday: _isToday(weekday),
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
    this.isToday = false,
    required this.courses,
    this.onEdit,
    this.onDelete,
  });

  final String name;
  final bool isToday;
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
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    courses.isEmpty
                        ? (isToday ? '今天没课，自由安排' : '当天无课')
                        : '${courses.length} 节课',
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
        onTap: onEdit == null
            ? null
            : () => onEdit!(
                Course(
                  id: course.id,
                  semesterId: course.semesterId,
                  source: course.source,
                  externalId: course.externalId,
                  name: course.name,
                  teacher: course.teacher,
                  colorValue: course.colorValue,
                  sessions: [
                    session,
                    ...course.sessions.where((s) => !identical(s, session)),
                  ],
                ),
              ),
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
                      '第 ${session.startSection}–${session.endSection} 节 · ${SectionTimes.label(session)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (course.teacher.trim().isNotEmpty)
                      Text(
                        course.teacher,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (session.room.trim().isNotEmpty)
                      GestureDetector(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('上课地点'),
                            content: SelectableText(session.room),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('知道了'),
                              ),
                            ],
                          ),
                        ),
                        child: Text(
                          session.room,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
