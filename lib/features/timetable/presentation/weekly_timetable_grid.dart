import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/school_schedule.dart';
import '../../../core/time/section_times.dart';

class WeeklyTimetableGrid extends StatefulWidget {
  const WeeklyTimetableGrid({
    super.key,
    required this.courses,
    required this.dateFor,
    required this.onDayTap,
    required this.isToday,
    this.sectionCount = 12,
    this.schedule,
    this.semesterId,
  });
  final List<ScheduledCourse> courses;
  final int sectionCount;
  final SchoolSchedule? schedule;
  final String? semesterId;
  final DateTime Function(int) dateFor;
  final bool Function(int) isToday;
  final ValueChanged<int> onDayTap;
  @override
  State<WeeklyTimetableGrid> createState() => _WeeklyTimetableGridState();
}

class _WeeklyTimetableGridState extends State<WeeklyTimetableGrid> {
  final _transform = TransformationController();
  double _zoom = 1;
  @override
  void initState() {
    super.initState();
    _transform.addListener(_zoomChanged);
  }

  void _zoomChanged() {
    final value = _transform.value.getMaxScaleOnAxis();
    if ((value - _zoom).abs() > .01) setState(() => _zoom = value);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  SchoolSchedule get _schedule => widget.schedule ?? SchoolSchedule.defaults();

  SectionTime? _axisTime(int number) {
    final schedule = _schedule;
    if (schedule.semesterSections.containsKey(widget.semesterId)) {
      return schedule.sectionFor(widget.semesterId, number);
    }
    SectionTime? individualTime(int sectionNumber) {
      final single = schedule.range(
        widget.semesterId,
        sectionNumber,
        sectionNumber,
      );
      return single == null
          ? schedule.sectionFor(widget.semesterId, sectionNumber)
          : SectionTime(sectionNumber, single.startMinute, single.endMinute);
    }

    // A paired imported range only specifies its outer endpoints. Check all
    // overlapping ranges before accepting a single-section override, using
    // the effective individual times rather than the unmodified base schedule.
    for (final range in schedule.rangeTimes) {
      if (range.semesterId != widget.semesterId ||
          range.startSection == range.endSection ||
          number < range.startSection ||
          number > range.endSection) {
        continue;
      }
      if (range.startMinute !=
              individualTime(range.startSection)?.startMinute ||
          range.endMinute != individualTime(range.endSection)?.endMinute) {
        return null;
      }
    }
    return individualTime(number);
  }

  Widget _axis(int number) {
    final time = _axisTime(number);
    final ranges = _schedule.rangeTimes.where(
      (range) =>
          range.semesterId == widget.semesterId &&
          range.startSection <= number &&
          range.endSection >= number,
    );
    final label = time == null
        ? '时间待确认'
        : '${SectionRangeTime.minuteLabel(time.startMinute)}–${SectionRangeTime.minuteLabel(time.endMinute)}';
    return Tooltip(
      message:
          '第 $number 节 · $label${ranges.isEmpty ? '' : '\n${ranges.map((r) => '第${r.startSection}–${r.endSection}节 ${r.label}').join('\n')}'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              key: Key('section_axis_$number'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$number',
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (time == null)
                  const Text(
                    '时间待确认',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 8),
                  )
                else ...[
                  Text(
                    SectionRangeTime.minuteLabel(time.startMinute),
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 9),
                  ),
                  Text(
                    SectionRangeTime.minuteLabel(time.endMinute),
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _courseContent(ScheduledCourse item) => Padding(
    padding: const EdgeInsets.all(2),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final font = math.min(
          _zoom < 1.5 ? 10.0 : 11 / _zoom,
          math.max(1.0, bounds.maxHeight / 2.3),
        );
        final line = font * 1.15;
        final lines = math.max(
          1,
          ((bounds.maxHeight - 2) / (line.ceilToDouble())).floor(),
        );
        final hasRoom = item.session.room.trim().isNotEmpty;
        final nameLines = math.min(2, math.max(1, lines - (hasRoom ? 1 : 0)));
        var remaining = lines - nameLines - (hasRoom ? 1 : 0);
        final showTeacher =
            item.course.teacher.trim().isNotEmpty && remaining > 0;
        if (showTeacher) remaining--;
        final showTime = _zoom >= 1.5 && remaining > 0;
        Widget text(String value, {int maxLines = 1, bool bold = false}) =>
            Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: font,
                height: 1.15,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            );
        return Tooltip(
          message:
              '${item.course.name}\n${item.session.room}\n${item.course.teacher}\n${SectionTimes.label(item.session)}',
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: bounds.maxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  text(item.course.name, maxLines: nameLines, bold: true),
                  if (hasRoom) text(item.session.room),
                  if (showTeacher) text(item.course.teacher),
                  if (showTime) text(SectionTimes.label(item.session)),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, bounds) {
            const axis = 46.0, header = 36.0;
            final count = widget.courses
                .fold<int>(
                  widget.sectionCount,
                  (n, c) => c.session.endSection > n ? c.session.endSection : n,
                )
                .clamp(1, 30);
            final dayWidth = (bounds.maxWidth - axis) / 7;
            final rowHeight = (bounds.maxHeight - header) / count;
            return ClipRect(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 4,
                child: SizedBox(
                  key: const Key('timetable_grid'),
                  width: bounds.maxWidth,
                  height: bounds.maxHeight,
                  child: Stack(
                    children: [
                      for (var day = 1; day <= 7; day++)
                        Positioned(
                          left: axis + (day - 1) * dayWidth,
                          top: 0,
                          width: dayWidth,
                          height: header,
                          child: Center(
                            child: Text(
                              '${const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day - 1]}\n${widget.dateFor(day).day}',
                              textAlign: TextAlign.center,
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: widget.isToday(day)
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      for (var n = 1; n <= count; n++)
                        Positioned(
                          left: 0,
                          top: header + (n - 1) * rowHeight,
                          width: axis,
                          height: rowHeight,
                          child: _axis(n),
                        ),
                      for (var day = 1; day <= 7; day++)
                        Positioned(
                          left: axis + (day - 1) * dayWidth,
                          top: header,
                          width: dayWidth,
                          height: rowHeight * count,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: widget.isToday(day)
                                  ? const Color(0xFFE9F5EF)
                                  : null,
                              border: Border.all(
                                color: const Color(0xFFDDE8E2),
                                width: .5,
                              ),
                            ),
                          ),
                        ),
                      for (final item in widget.courses)
                        Positioned(
                          left:
                              axis + (item.session.weekday - 1) * dayWidth + 1,
                          top:
                              header +
                              (item.session.startSection - 1) * rowHeight +
                              1,
                          width: dayWidth - 2,
                          height:
                              (item.session.endSection -
                                      item.session.startSection +
                                      1) *
                                  rowHeight -
                              2,
                          child: Material(
                            color: Color(
                              item.course.colorValue,
                            ).withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(5),
                            child: InkWell(
                              onTap: () =>
                                  widget.onDayTap(item.session.weekday),
                              borderRadius: BorderRadius.circular(5),
                              child: _courseContent(item),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              '双指缩放 · 放大后拖动 · 点击课程查看详情',
              style: TextStyle(fontSize: 10),
            ),
          ),
          TextButton(
            key: const Key('reset_week_zoom'),
            onPressed: () => _transform.value = Matrix4.identity(),
            child: const Text('适应整周'),
          ),
        ],
      ),
    ],
  );
}
