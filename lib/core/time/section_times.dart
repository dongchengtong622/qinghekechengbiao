import '../../features/timetable/domain/models.dart';

abstract final class SectionTimes {
  static String label(CourseSession session) {
    if (session.timeLabel != null) return session.timeLabel!;
    if (session.startMinute != null) {
      final value = session.startMinute!;
      return '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')} 开始';
    }
    return '时间待确认';
  }
}
