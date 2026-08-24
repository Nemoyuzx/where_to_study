// 与 iOS 端 ScheduleLogicTests 的核心断言对齐。
import { describe, it, expect } from '@ohos/hypium';
import { Course, ClassroomDefaults, SlotMetadata } from '../main/ets/common/Models';
import { ScheduleLogic } from '../main/ets/common/ScheduleLogic';
import { StrictDates, DateParts } from '../main/ets/common/StrictDates';

function course(weekday: number, startSlot: number, endSlot: number, weeks: number[]): Course {
  return new Course('c', '测试课程', '测试教师', '主楼-101', '1-18', weeks, [],
    weekday, startSlot, endSlot, '1-2节', '08:00-09:35');
}

export default function scheduleLogicTest() {
  describe('ScheduleLogicTest', () => {
    it('week_number_uses_term_start_date', 0, () => {
      const start: DateParts = new DateParts(2026, 3, 2);
      expect(ScheduleLogic.weekNumber(StrictDates.addDays(start, 14), start)).assertEqual(3);
      expect(ScheduleLogic.weekNumber(StrictDates.addDays(start, -1), start)).assertEqual(0);
      expect(ScheduleLogic.weekNumber(start, start)).assertEqual(1);
    });

    it('busy_slots_include_every_slot_covered_by_courses', 0, () => {
      const start: DateParts = new DateParts(2026, 3, 2);
      const result: Set<number> = ScheduleLogic.busySlots(
        start, start, [course(1, 2, 4, [1])]);
      expect(result.size).assertEqual(3);
      expect(result.has(2)).assertTrue();
      expect(result.has(3)).assertTrue();
      expect(result.has(4)).assertTrue();
    });

    it('courses_on_filters_by_weekday_and_week', 0, () => {
      const start: DateParts = new DateParts(2026, 3, 2);
      const monday: Course[] = ScheduleLogic.coursesOn(
        start, start, [course(1, 0, 1, [1]), course(2, 0, 1, [1])]);
      expect(monday.length).assertEqual(1);
    });

    it('classroom_defaults_expose_every_original_building', 0, () => {
      expect(ClassroomDefaults.buildings('01').join(',')).assertEqual('教1,教2,教3,教4,主楼');
      expect(ClassroomDefaults.buildings('04').join(','))
        .assertEqual('综合教学楼N,综合教学楼S,教学实验综合楼N,教学实验综合楼S,智慧教学楼');
      expect(ClassroomDefaults.buildings('unknown').length).assertEqual(0);
    });

    it('slot_metadata_keeps_fourteen_periods', 0, () => {
      expect(SlotMetadata.defaults.length).assertEqual(14);
      expect(SlotMetadata.defaults[0].start).assertEqual('08:00');
      expect(SlotMetadata.defaults[13].end).assertEqual('20:55');
    });
  });
}
