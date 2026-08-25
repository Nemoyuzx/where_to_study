// 教学日历纯逻辑（与 iOS ScheduleLogicTests 的日历部分对齐）。
import { describe, it, expect } from '@ohos/hypium';
import { DateParts, StrictDates } from '../main/ets/common/StrictDates';
import { Course } from '../main/ets/common/Models';
import {
  CalendarMode, CalendarModeInfo, CalendarPageTransitionOffsets, CalendarPopoverPosition,
  CalendarTimelineLogic,
  CalendarYearDeadlinePriority, TeachingCalendarLogic
} from '../main/ets/view/calendar/CalendarLogic';
import { AppSection, AppSectionInfo } from '../main/ets/common/AppSection';
import {
  CalendarViewportPreloadController, CalendarViewportPreloadPlan,
  CalendarViewportPreloadPlanner, CalendarViewportPreloadTarget
} from '../main/ets/view/calendar/CalendarViewportPreloadController';
import { MobileCalendarTimelineLayout } from
  '../main/ets/view/calendar/MobileCalendarTimelineView';

class CalendarPreloadProbe implements CalendarViewportPreloadTarget {
  calls: number = 0;
  selectedDate: DateParts | null = null;
  markerCount: number = 0;
  holidayYears: number[] = [];

  prewarmCalendarViewport(selectedDate: DateParts, markerDays: DateParts[],
    holidayYears: number[]): void {
    this.calls++;
    this.selectedDate = selectedDate;
    this.markerCount = markerDays.length;
    this.holidayYears = holidayYears;
  }
}

export default function teachingCalendarLogicTest() {
  describe('TeachingCalendarLogicTest', () => {
    it('period_titles_reserve_week_label_for_real_teaching_metadata', 0, () => {
      const date: DateParts = new DateParts(2026, 8, 14);
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.day))
        .assertEqual('2026年8月14日');
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.week))
        .assertEqual('2026年8月');
      expect(TeachingCalendarLogic.periodTitle(date, CalendarMode.week, true))
        .assertEqual('August 2026');
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

    it('month_sheet_only_takes_top_started_detail_pull', 0, () => {
      expect(TeachingCalendarLogic.monthSheetOwnsGesture(80, 2, false)).assertFalse();
      expect(TeachingCalendarLogic.monthSheetOwnsGesture(80, 2, true)).assertTrue();
      expect(TeachingCalendarLogic.monthSheetOwnsGesture(-80, 1, true)).assertTrue();
      expect(TeachingCalendarLogic.monthSheetOwnsGesture(-80, 2, true)).assertFalse();
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

    it('month_and_year_deadline_border_priority_is_assignment_then_school_then_other', 0, () => {
      expect(TeachingCalendarLogic.yearDeadlinePriority(1, 3, 5))
        .assertEqual(CalendarYearDeadlinePriority.assignment);
      // 月格与年格共用同一优先级；选中态/today 只改变底色或无 DDL 时的回退边框。
      expect(TeachingCalendarLogic.yearDeadlinePriority(4, 0, 0))
        .assertEqual(CalendarYearDeadlinePriority.assignment);
      expect(TeachingCalendarLogic.yearDeadlinePriority(0, 2, 5))
        .assertEqual(CalendarYearDeadlinePriority.schoolNotice);
      expect(TeachingCalendarLogic.yearDeadlinePriority(0, 0, 4))
        .assertEqual(CalendarYearDeadlinePriority.other);
      expect(TeachingCalendarLogic.yearDeadlinePriority(0, 0, 0))
        .assertEqual(CalendarYearDeadlinePriority.none);
      const allKinds: CalendarYearDeadlinePriority[] =
        TeachingCalendarLogic.yearDeadlineBorderLayers(1, 1, 1);
      expect(allKinds.length).assertEqual(2);
      expect(allKinds[0]).assertEqual(CalendarYearDeadlinePriority.assignment);
      expect(allKinds[1]).assertEqual(CalendarYearDeadlinePriority.schoolNotice);
      const schoolAndOther: CalendarYearDeadlinePriority[] =
        TeachingCalendarLogic.yearDeadlineBorderLayers(0, 1, 1);
      expect(schoolAndOther.length).assertEqual(2);
      expect(schoolAndOther[0]).assertEqual(CalendarYearDeadlinePriority.schoolNotice);
      expect(schoolAndOther[1]).assertEqual(CalendarYearDeadlinePriority.other);
      expect(TeachingCalendarLogic.yearDeadlineBorderLayers(0, 0, 0).length).assertEqual(0);
      expect(TeachingCalendarLogic.showsTodayMarker(true)).assertTrue();
      expect(TeachingCalendarLogic.showsTodayMarker(false)).assertFalse();
    });

    it('only_day_and_week_use_all_day_dialogs_while_month_stays_inline', 0, () => {
      expect(TeachingCalendarLogic.allDayDialogTitle(CalendarMode.week, false))
        .assertEqual('周视图 · 全天');
      expect(TeachingCalendarLogic.allDayDialogTitle(CalendarMode.week, true))
        .assertEqual('Week View · All-day');
      expect(TeachingCalendarLogic.supportsAllDayDialog(CalendarMode.day)).assertTrue();
      expect(TeachingCalendarLogic.supportsAllDayDialog(CalendarMode.week)).assertTrue();
      expect(TeachingCalendarLogic.supportsAllDayDialog(CalendarMode.month)).assertFalse();
      expect(TeachingCalendarLogic.supportsAllDayDialog(CalendarMode.year)).assertFalse();
    });

    it('day_and_week_top_agenda_share_only_the_selected_date', 0, () => {
      const selected: DateParts = new DateParts(2026, 8, 24);
      expect(TeachingCalendarLogic.timelineCourseSummaryDate(CalendarMode.day, selected)
        .equals(selected)).assertTrue();
      expect(TeachingCalendarLogic.timelineCourseSummaryDate(CalendarMode.week, selected)
        .equals(selected)).assertTrue();
      expect(TeachingCalendarLogic.timelineAgendaSortOrder('holiday')).assertEqual(0);
      expect(TeachingCalendarLogic.timelineAgendaSortOrder('assignment')).assertEqual(1);
      expect(TeachingCalendarLogic.timelineAgendaSortOrder('school_notice')).assertEqual(2);
      expect(TeachingCalendarLogic.timelineAgendaSortOrder('public_deadline')).assertEqual(3);
      expect(TeachingCalendarLogic.agendaDialogChangesSelectedDate(CalendarMode.day)).assertTrue();
      expect(TeachingCalendarLogic.agendaDialogChangesSelectedDate(CalendarMode.month)).assertFalse();
      expect(TeachingCalendarLogic.agendaDialogChangesSelectedDate(CalendarMode.week)).assertFalse();
    });

    it('mode_indicator_and_page_share_forward_then_backward_transition_contract', 0, () => {
      expect(TeachingCalendarLogic.pageTransitionDuration).assertEqual(300);
      const forwardModes: CalendarMode[] = CalendarModeInfo.all;
      for (let index = 0; index < forwardModes.length - 1; index++) {
        expect(TeachingCalendarLogic.modeTransitionDirection(
          forwardModes[index], forwardModes[index + 1])).assertEqual(1);
      }
      const backwardModes: CalendarMode[] = CalendarModeInfo.all.slice().reverse();
      for (let index = 0; index < backwardModes.length - 1; index++) {
        expect(TeachingCalendarLogic.modeTransitionDirection(
          backwardModes[index], backwardModes[index + 1])).assertEqual(-1);
      }
      const forwardOffsets: CalendarPageTransitionOffsets =
        TeachingCalendarLogic.pageTransitionOffsets(1, 320);
      expect(forwardOffsets.incomingStartX).assertEqual(320);
      expect(forwardOffsets.outgoingEndX).assertEqual(-320);
      const backwardOffsets: CalendarPageTransitionOffsets =
        TeachingCalendarLogic.pageTransitionOffsets(-1, 320);
      expect(backwardOffsets.incomingStartX).assertEqual(-320);
      expect(backwardOffsets.outgoingEndX).assertEqual(320);
    });

    it('favorite_management_hides_only_the_phone_navigation', 0, () => {
      expect(AppSectionInfo.showsPhoneNavigation(AppSection.settings, true)).assertFalse();
      expect(AppSectionInfo.showsPhoneNavigation(AppSection.settings, false)).assertTrue();
      expect(AppSectionInfo.showsPhoneNavigation(AppSection.calendar, true)).assertTrue();
    });

    it('expanded_month_grid_reserves_chips_for_courses_only', 0, () => {
      expect(TeachingCalendarLogic.expandedMonthGridShowsChip('course')).assertTrue();
      expect(TeachingCalendarLogic.expandedMonthGridShowsChip('holiday')).assertFalse();
      expect(TeachingCalendarLogic.expandedMonthGridShowsChip('assignment')).assertFalse();
      expect(TeachingCalendarLogic.expandedMonthGridShowsChip('school_notice')).assertFalse();
      expect(TeachingCalendarLogic.expandedMonthGridShowsChip('public_deadline')).assertFalse();
    });

    it('expanded_all_day_cards_show_time_and_route_link_or_details', 0, () => {
      expect(TeachingCalendarLogic.allDayTimeLabel('2026-08-24T23:59:00+08:00'))
        .assertEqual('23:59');
      expect(TeachingCalendarLogic.allDayTimeLabel('2026-08-24 08:05:00'))
        .assertEqual('08:05');
      expect(TeachingCalendarLogic.allDayTimeLabel('', 'All-day')).assertEqual('All-day');
      expect(TeachingCalendarLogic.allDayCardAction('https://example.com/event'))
        .assertEqual('link');
      expect(TeachingCalendarLogic.allDayCardAction(null)).assertEqual('details');
    });

    it('expanded_year_detail_has_a_bounded_scrollable_viewport', 0, () => {
      expect(TeachingCalendarLogic.expandedYearDetailScrollHeight(300)).assertEqual(240);
      expect(TeachingCalendarLogic.expandedYearDetailScrollHeight(700)).assertEqual(364);
      expect(TeachingCalendarLogic.expandedYearDetailScrollHeight(1200)).assertEqual(420);
      expect(TeachingCalendarLogic.expandedYearDetailPanelHeight(300)).assertEqual(268);
      expect(TeachingCalendarLogic.expandedYearDetailPanelHeight(700)).assertEqual(472);
      expect(TeachingCalendarLogic.expandedYearDetailPanelHeight(1200)).assertEqual(528);
    });

    it('expanded_year_detail_stays_near_its_anchor_and_clamps_to_viewport', 0, () => {
      const below: CalendarPopoverPosition = TeachingCalendarLogic.expandedYearDetailPosition(
        220, 120, 1200, 800, 320, 472);
      expect(below.x).assertEqual(60);
      expect(below.y).assertEqual(130);

      const right: CalendarPopoverPosition = TeachingCalendarLogic.expandedYearDetailPosition(
        1180, 120, 1200, 800, 320, 472);
      expect(right.x).assertEqual(864);
      expect(right.y).assertEqual(130);

      const above: CalendarPopoverPosition = TeachingCalendarLogic.expandedYearDetailPosition(
        620, 760, 1200, 800, 320, 472);
      expect(above.x).assertEqual(460);
      expect(above.y).assertEqual(278);

      const clamped: CalendarPopoverPosition = TeachingCalendarLogic.expandedYearDetailPosition(
        4, 150, 760, 300, 320, 268);
      expect(clamped.x).assertEqual(16);
      expect(clamped.y).assertEqual(16);
      expect(clamped.y + 268).assertEqual(284);
    });

    it('calendar_viewport_preloader_is_independent_and_single_flight_by_viewport', 0, () => {
      const selected: DateParts = new DateParts(2026, 8, 24);
      const month: CalendarViewportPreloadPlan =
        CalendarViewportPreloadPlanner.plan(CalendarMode.month, selected);
      expect(month.markerDays.length).assertEqual(42);
      expect(month.holidayYears.includes(2026)).assertTrue();
      const year: CalendarViewportPreloadPlan =
        CalendarViewportPreloadPlanner.plan(CalendarMode.year, selected);
      expect(year.markerDays.length).assertEqual(365);

      const controller: CalendarViewportPreloadController =
        new CalendarViewportPreloadController();
      const probe: CalendarPreloadProbe = new CalendarPreloadProbe();
      controller.prewarm(probe, CalendarMode.month, selected);
      expect(probe.calls).assertEqual(1);
      expect(probe.markerCount).assertEqual(42);
      controller.prewarm(probe, CalendarMode.month, selected);
      expect(probe.calls).assertEqual(1);
      controller.prewarm(probe, CalendarMode.week, selected);
      expect(probe.calls).assertEqual(2);
      expect(probe.markerCount).assertEqual(7);
      controller.prewarm(probe, CalendarMode.week, selected, true);
      expect(probe.calls).assertEqual(3);
    });

    it('week_column_selection_stays_behind_course_pointer_targets', 0, () => {
      expect(MobileCalendarTimelineLayout.columnSelectionLayerZ <
        MobileCalendarTimelineLayout.courseBlockLayerZ).assertTrue();
      expect(MobileCalendarTimelineLayout.columnTapSelectsDay(false)).assertTrue();
      expect(MobileCalendarTimelineLayout.columnTapSelectsDay(true)).assertFalse();
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
