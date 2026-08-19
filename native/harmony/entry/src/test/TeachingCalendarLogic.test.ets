// 教学日历纯逻辑（与 iOS ScheduleLogicTests 的日历部分对齐）。
import { describe, it, expect } from '@ohos/hypium';
import { DateParts, StrictDates } from '../main/ets/common/StrictDates';
import { Course } from '../main/ets/common/Models';
import {
  CalendarMode, CalendarTimelineLogic, TeachingCalendarLogic
} from '../main/ets/view/calendar/CalendarLogic';

export default function teachingCalendarLogicTest() {
  describe('TeachingCalendarLogicTest', () => {
    it('period_titles_keep_week_in_primary_title', 0, () => {
      const date: DateParts = new DateParts(2026, 8, 14);
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.day))
        .assertEqual('2026年8月14日');
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.week))
        .assertEqual('2026年8月 第 33 周');
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.month))
        .assertEqual('2026年8月');
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.year))
        .assertEqual('2026年');
    });

    it('moved_date_steps_by_visible_period', 0, () => {
      const date: DateParts = new DateParts(2026, 6, 15);
      expect(TeachingCalendarLogic.movedDate(date, CalendarMode.day, 1).day).assertEqual(16);
      expect(TeachingCalendarLogic.movedDate(date, CalendarMode.week, 1).day).assertEqual(22);
      expect(TeachingCalendarLogic.movedDate(date, CalendarMode.month, 1).month).assertEqual(7);
      expect(TeachingCalendarLogic.movedDate(date, CalendarMode.year, 1).year).assertEqual(2027);
    });

    it('add_months_clamps_to_valid_day', 0, () => {
      const jan31: DateParts = new DateParts(2026, 1, 31);
      const feb: DateParts = TeachingCalendarLogic.addMonths(jan31, 1);
      expect(feb.month).assertEqual(2);
      expect(feb.day).assertEqual(28);
    });

    it('year_mode_movement_clamps_leap_day', 0, () => {
      // BUG-048：2028-02-29 在年视图跨年必须钳制为 2029-02-28，不得产生非法日期。
      const leapDay: DateParts = new DateParts(2028, 2, 29);
      const moved: DateParts = TeachingCalendarLogic.movedDate(leapDay, CalendarMode.year, 1);
      expect(moved.year).assertEqual(2029);
      expect(moved.month).assertEqual(2);
      expect(moved.day).assertEqual(28);
      expect(StrictDates.parseDateString(StrictDates.formatDateParts(moved)) !== null).assertTrue();
    });

    it('swipe_requires_deliberate_horizontal_gesture', 0, () => {
      expect(TeachingCalendarLogic.swipeDirection(-72, 12, -118)).assertEqual(1);
      expect(TeachingCalendarLogic.swipeDirection(72, 12, 118)).assertEqual(-1);
      expect(TeachingCalendarLogic.swipeDirection(30, 2, 120)).assertNull();
      expect(TeachingCalendarLogic.swipeDirection(80, 70, 120)).assertNull();
    });

    it('month_expansion_requires_deliberate_vertical_gesture', 0, () => {
      expect(TeachingCalendarLogic.monthExpansionAction(8, -72)).assertEqual(-1);
      expect(TeachingCalendarLogic.monthExpansionAction(8, 72)).assertEqual(1);
      expect(TeachingCalendarLogic.monthExpansionAction(72, 42)).assertNull();
      expect(TeachingCalendarLogic.monthExpansionAction(12, 30)).assertNull();
    });

    it('expanded_month_events_reserve_last_row_for_overflow', 0, () => {
      expect(TeachingCalendarLogic.monthEventLayout(2, 2)[0]).assertEqual(2);
      expect(TeachingCalendarLogic.monthEventLayout(2, 2)[1]).assertEqual(0);
      expect(TeachingCalendarLogic.monthEventLayout(5, 2)[0]).assertEqual(1);
      expect(TeachingCalendarLogic.monthEventLayout(5, 2)[1]).assertEqual(4);
      expect(TeachingCalendarLogic.monthEventLayout(3, 0)[0]).assertEqual(0);
      expect(TeachingCalendarLogic.monthEventLayout(3, 0)[1]).assertEqual(3);
    });

    it('year_course_density_increases_and_stays_below_one', 0, () => {
      expect(TeachingCalendarLogic.yearCourseOpacity(0)).assertEqual(0);
      let previous: number = -1;
      for (const count of [1, 4, 5, 8, 12]) {
        const value: number = TeachingCalendarLogic.yearCourseOpacity(count);
        expect(value > previous).assertTrue();
        previous = value;
      }
      expect(previous < 1).assertTrue();
    });

    it('timeline_minute_and_metadata_helpers', 0, () => {
      expect(CalendarTimelineLogic.minuteOf('09:50')).assertEqual(9 * 60 + 50);
      expect(CalendarTimelineLogic.minuteOf('24:00')).assertNull();
      expect(CalendarTimelineLogic.position(7 * 60 + 59)).assertEqual(0);
      expect(CalendarTimelineLogic.position(15 * 60)).assertEqual(0.5);
      expect(CalendarTimelineLogic.position(22 * 60 + 1)).assertEqual(1);
      const course: Course = new Course('m', '数据挖掘', '徐思雅', '教三楼-3-335', '1-16',
        [1], [], 1, 2, 4, '3-5节', '09:50-12:15');
      expect(CalendarTimelineLogic.courseMetadata(course))
        .assertEqual('教三楼-3-335 · 教师：徐思雅');
      const nonHourly: number[] = CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes();
      expect(nonHourly.includes(13 * 60 + 45)).assertTrue();
      expect(nonHourly.includes(13 * 60)).assertFalse();
      expect(nonHourly.includes(8 * 60 + 45)).assertTrue();
    });
  });
}
