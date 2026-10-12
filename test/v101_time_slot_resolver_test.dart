import 'package:flutter_test/flutter_test.dart';
import 'package:qinghe_timetable/features/timetable/domain/time_slot_resolver.dart';

void main() {
  test('paired range requires known duration and preserves endpoints', () {
    expect(
      TimeSlotResolver.split(1, 2, 480, 580).status,
      SlotStatus.needsConfirmation,
    );
    final r = TimeSlotResolver.split(1, 2, 480, 580, lessonMinutes: 45);
    expect(r.status, SlotStatus.suggested);
    expect(
      r.sections.map((s) => [s.section, s.startMinute, s.endMinute]).toList(),
      [
        [1, 480, 525],
        [2, 535, 580],
      ],
    );
    expect(r.breakMinutes, 10);
  });
  test('40 and 50 minute candidates must not assume 45', () {
    expect(
      TimeSlotResolver.split(1, 2, 480, 580, lessonMinutes: 40).breakMinutes,
      20,
    );
    expect(
      TimeSlotResolver.split(1, 2, 480, 580, lessonMinutes: 50).breakMinutes,
      0,
    );
  });
  test('invalid, negative, noninteger and cross day never silently round', () {
    expect(
      TimeSlotResolver.split(1, 2, 480, 560, lessonMinutes: 45).status,
      SlotStatus.conflict,
    );
    expect(
      TimeSlotResolver.split(1, 4, 480, 671, lessonMinutes: 45).status,
      SlotStatus.needsConfirmation,
    );
    expect(
      TimeSlotResolver.split(
        1,
        3,
        480,
        640,
        lessonMinutes: 45,
        equalBreaks: false,
      ).status,
      SlotStatus.needsConfirmation,
    );
    expect(
      TimeSlotResolver.split(1, 2, 1380, 30, lessonMinutes: 45).status,
      SlotStatus.conflict,
    );
  });
  test('explicit single range confirmed without candidate assumptions', () {
    final r = TimeSlotResolver.split(3, 3, 600, 640);
    expect(r.status, SlotStatus.confirmed);
    expect(r.sections.single.endMinute, 640);
  });
}
