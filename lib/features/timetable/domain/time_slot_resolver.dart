import 'school_schedule.dart';

enum SlotStatus { confirmed, suggested, needsConfirmation, conflict }

class SlotResolution {
  const SlotResolution(
    this.status,
    this.sections, {
    this.breakMinutes,
    this.reason,
  });
  final SlotStatus status;
  final List<SectionTime> sections;
  final int? breakMinutes;
  final String? reason;
}

/// Combined endpoints do not determine lesson duration or unequal breaks.
abstract final class TimeSlotResolver {
  static SlotResolution split(
    int first,
    int last,
    int start,
    int end, {
    int? lessonMinutes,
    bool equalBreaks = true,
  }) {
    if (first < 1 ||
        last < first ||
        last > 30 ||
        start < 0 ||
        end >= 1440 ||
        end <= start) {
      return const SlotResolution(
        SlotStatus.conflict,
        [],
        reason: '节次或起止时间无效，跨日时间请手动核对',
      );
    }
    final n = last - first + 1;
    if (n == 1) {
      return SlotResolution(SlotStatus.confirmed, [
        SectionTime(first, start, end),
      ]);
    }
    if (lessonMinutes == null) {
      return const SlotResolution(
        SlotStatus.needsConfirmation,
        [],
        reason: '请选择单节时长，合并区间不能唯一确定逐节时间',
      );
    }
    if (lessonMinutes <= 0 || lessonMinutes > 180) {
      return const SlotResolution(SlotStatus.conflict, [], reason: '单节时长无效');
    }
    final gap = end - start - n * lessonMinutes;
    if (gap < 0) {
      return const SlotResolution(
        SlotStatus.conflict,
        [],
        reason: '授课总时长超过原始区间',
      );
    }
    if ((n > 2 && !equalBreaks) || gap % (n - 1) != 0) {
      return const SlotResolution(
        SlotStatus.needsConfirmation,
        [],
        reason: '课间不等或不是整分钟，请逐节填写',
      );
    }
    final b = gap ~/ (n - 1);
    return SlotResolution(SlotStatus.suggested, [
      for (var i = 0; i < n; i++)
        SectionTime(
          first + i,
          start + i * (lessonMinutes + b),
          start + i * (lessonMinutes + b) + lessonMinutes,
        ),
    ], breakMinutes: b);
  }
}
