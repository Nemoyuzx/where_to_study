// 教学日历纯逻辑（与 iOS ScheduleLogicTests 的日历部分对齐）。
import { describe, it, expect } from '@ohos/hypium';
import { DateParts, StrictDates } from '../main/ets/common/StrictDates';
import { Course } from '../main/ets/common/Models';
import {
  CalendarGestureAxis, CalendarMode, CalendarModeInfo, CalendarPageTransitionOffsets,
  CalendarPopoverPosition, CalendarTimelineLogic,
  CalendarYearDeadlinePriority, TeachingCalendarLogic
} from '../main/ets/view/calendar/CalendarLogic';
import { AppSection, AppSectionInfo } from '../main/ets/common/AppSection';
import {
  CalendarViewportPreloadController, CalendarViewportPreloadPlan,
  CalendarViewportPreloadPlanner, CalendarViewportPreloadTarget
} from '../main/ets/view/calendar/CalendarViewportPreloadController';
import { MobileCalendarTimelineLayout } from
  '../main/ets/view/calendar/MobileCalendarTimelineView';
import { TeachingCalendarSession } from
  '../main/ets/view/calendar/TeachingCalendarSession';

class CalendarPreloadProbe implements CalendarViewportPreloadTarget {
  calls: number = 0;
  selectedDate: DateParts | null = null;
  selectedDateKeys: string[] = [];
  markerCount: number = 0;
  holidayYears: number[] = [];

  prewarmCalendarViewport(selectedDate: DateParts, markerDays: DateParts[],
    holidayYears: number[]): void {
    this.calls++;
    this.selectedDate = selectedDate;
    this.selectedDateKeys.push(StrictDates.formatDateParts(selectedDate));
    this.markerCount = markerDays.length;
    this.holidayYears = holidayYears;
  }
}

export default function teachingCalendarLogicTest() {
  describe('TeachingCalendarLogicTest', () => {
    it('year_page_identity_preserves_the_grid_when_selecting_another_day', 0, () => {
      const first: DateParts = new DateParts(2026, 1, 1);
      const selected: DateParts = new DateParts(2026, 9, 5);
      expect(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.year, first))
        .assertEqual(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.year, selected));
      expect(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.year, selected))
        .assertEqual(CalendarMode.year + '.2026');
      expect(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.year,
        new DateParts(2027, 1, 1))).assertEqual(CalendarMode.year + '.2027');
      expect(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.month, selected))
        .assertEqual(CalendarMode.month + '.2026-09');
      expect(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.month,
        new DateParts(2026, 9, 30)))
        .assertEqual(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.month, selected));
      expect(TeachingCalendarLogic.mobilePageIdentity(CalendarMode.month,
        new DateParts(2026, 10, 1))).assertEqual(CalendarMode.month + '.2026-10');
      for (const mode of [CalendarMode.day, CalendarMode.week]) {
        expect(TeachingCalendarLogic.mobilePageIdentity(mode, selected))
          .assertEqual(mode + '.2026-09-05');
      }
    });

    it('month_week_index_matches_monday_first_grid_including_leap_years', 0, () => {
      for (const year of [2026, 2028, 2100]) {
        for (let month: number = 1; month <= 12; month++) {
          const first: DateParts = new DateParts(year, month, 1);
          const start: DateParts = StrictDates.addDays(first,
            1 - StrictDates.weekdayMonday1(first));
          for (let index: number = 0; index < 42; index++) {
            const day: DateParts = StrictDates.addDays(start, index);
            if (day.year === year && day.month === month) {
              expect(TeachingCalendarLogic.monthWeekIndex(day)).assertEqual(Math.floor(index / 7));
            }
          }
        }
      }
    });

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
      const march: DateParts = TeachingCalendarLogic.addMonths(feb, 1, 31);
      expect(march.month).assertEqual(3);
      expect(march.day).assertEqual(31);
    });

    it('month_navigation_preserves_explicit_day_anchor_across_short_months', 0, () => {
      const session: TeachingCalendarSession = new TeachingCalendarSession();
      session.selectDate(new DateParts(2026, 1, 31));
      const february: DateParts = session.monthNavigationDestination(1);
      expect(february.month).assertEqual(2);
      expect(february.day).assertEqual(28);
      session.commitMonthNavigation(february);
      const march: DateParts = session.monthNavigationDestination(1);
      expect(march.month).assertEqual(3);
      expect(march.day).assertEqual(31);

      session.selectDate(new DateParts(2026, 3, 15));
      session.commitMonthNavigation(session.monthNavigationDestination(-1));
      expect(session.selectedDate.month).assertEqual(2);
      expect(session.selectedDate.day).assertEqual(15);
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

    it('month_gesture_locks_to_the_first_deliberate_axis', 0, () => {
      expect(TeachingCalendarLogic.gestureAxis(4, 5)).assertNull();
      expect(TeachingCalendarLogic.gestureAxis(24, 8))
        .assertEqual(CalendarGestureAxis.horizontal);
      expect(TeachingCalendarLogic.gestureAxis(8, -24))
        .assertEqual(CalendarGestureAxis.vertical);
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

    it('month_sheet_handle_and_day_selection_match_mobile_three_stop_behavior', 0, () => {
      expect(TeachingCalendarLogic.monthHandleTargetPosition(0)).assertEqual(1);
      expect(TeachingCalendarLogic.monthHandleTargetPosition(1)).assertEqual(0);
      expect(TeachingCalendarLogic.monthHandleTargetPosition(2)).assertEqual(1);
      expect(TeachingCalendarLogic.monthDaySelectionTargetPosition()).assertEqual(1);
      expect(TeachingCalendarLogic.settledMonthSheetPosition(0.7, 0)).assertEqual(1);
      expect(TeachingCalendarLogic.settledMonthSheetPosition(1.3, 0)).assertEqual(1);
      expect(TeachingCalendarLogic.settledMonthSheetPosition(1, -700)).assertEqual(2);
      expect(TeachingCalendarLogic.settledMonthSheetPosition(1, 700)).assertEqual(0);
      expect(TeachingCalendarLogic.monthDetailsCanScrollAtGestureStart(1)).assertFalse();
      expect(TeachingCalendarLogic.monthDetailsCanScrollAtGestureStart(1.99)).assertFalse();
      expect(TeachingCalendarLogic.monthDetailsCanScrollAtGestureStart(2)).assertTrue();

      const session: TeachingCalendarSession = new TeachingCalendarSession();
      session.setMonthSheetPosition(2);
      expect(session.monthSheetPosition).assertEqual(2);
      session.setMonthSheetPosition(3);
      expect(session.monthSheetPosition).assertEqual(2);
      session.setMonthSheetPosition(-1);
      expect(session.monthSheetPosition).assertEqual(0);
    });

    it('month_week_detent_clips_and_translates_an_intact_grid', 0, () => {
      const rowCount: number = 6;
      const rowHeight: number = TeachingCalendarLogic.monthCollapsedCellHeight;
      for (let rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        expect(TeachingCalendarLogic.monthRowHeight(2, rowIndex, 3)).assertEqual(rowHeight);
      }
      expect(TeachingCalendarLogic.monthGridContentHeight(rowCount, rowHeight))
        .assertEqual(rowCount * rowHeight);
      expect(TeachingCalendarLogic.monthGridViewportHeight(1, rowCount, rowHeight))
        .assertEqual(rowCount * rowHeight);
      expect(TeachingCalendarLogic.monthGridViewportHeight(1.5, rowCount, rowHeight))
        .assertEqual(161);
      expect(TeachingCalendarLogic.monthGridViewportHeight(2, rowCount, rowHeight))
        .assertEqual(rowHeight);
      expect(TeachingCalendarLogic.monthGridTranslationY(1, 3, rowHeight)).assertEqual(0);
      expect(TeachingCalendarLogic.monthGridTranslationY(1.5, 3, rowHeight)).assertEqual(-69);
      expect(TeachingCalendarLogic.monthGridTranslationY(2, 3, rowHeight)).assertEqual(-138);
    });

    it('animated_target_mode_drives_the_compact_date_strip', 0, () => {
      expect(TeachingCalendarLogic.showsCompactDateStrip(CalendarMode.day)).assertTrue();
      expect(TeachingCalendarLogic.showsCompactDateStrip(CalendarMode.week)).assertTrue();
      expect(TeachingCalendarLogic.showsCompactDateStrip(CalendarMode.month)).assertFalse();
      expect(TeachingCalendarLogic.showsCompactDateStrip(CalendarMode.year)).assertFalse();
      expect(TeachingCalendarLogic.showsCompactWeekAxis(CalendarMode.week)).assertTrue();
      expect(TeachingCalendarLogic.showsCompactWeekAxis(CalendarMode.day)).assertFalse();
      expect(TeachingCalendarLogic.showsCompactWeekAxis(CalendarMode.month)).assertFalse();
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

    it('calendar_viewport_preloader_caches_current_and_adjacent_months', 0, () => {
      const selected: DateParts = new DateParts(2026, 1, 31);
      const month: CalendarViewportPreloadPlan =
        CalendarViewportPreloadPlanner.plan(CalendarMode.month, selected);
      expect(month.markerDays.length).assertEqual(42);
      expect(month.holidayYears.includes(2026)).assertTrue();
      const year: CalendarViewportPreloadPlan =
        CalendarViewportPreloadPlanner.plan(CalendarMode.year, selected);
      expect(year.markerDays.length).assertEqual(365);

      const controller: CalendarViewportPreloadController =
        new CalendarViewportPreloadController(8);
      const probe: CalendarPreloadProbe = new CalendarPreloadProbe();
      const session: TeachingCalendarSession = new TeachingCalendarSession();
      session.selectDate(selected);
      const firstWindow: DateParts[] = [session.selectedDate,
        session.monthNavigationDestination(-1), session.monthNavigationDestination(1)];
      for (const date of firstWindow) {
        controller.prewarm(probe, CalendarMode.month, date);
      }
      expect(probe.calls).assertEqual(3);
      expect(probe.markerCount).assertEqual(42);
      expect(probe.selectedDateKeys.includes('2025-12-31')).assertTrue();
      expect(probe.selectedDateKeys.includes('2026-01-31')).assertTrue();
      expect(probe.selectedDateKeys.includes('2026-02-28')).assertTrue();

      session.commitMonthNavigation(session.monthNavigationDestination(1));
      const committedWindow: DateParts[] = [session.selectedDate,
        session.monthNavigationDestination(-1), session.monthNavigationDestination(1)];
      for (const date of committedWindow) {
        controller.prewarm(probe, CalendarMode.month, date);
      }
      // 2 月提交后，1/2 月都已预热，只新增恢复锚点的 3 月 31 日。
      expect(probe.calls).assertEqual(4);
      expect(probe.selectedDateKeys.includes('2026-03-31')).assertTrue();

      for (const date of committedWindow) {
        controller.prewarm(probe, CalendarMode.month, date, true);
      }
      // 来源开关变化时 refresh 仍强制重跑当前与两个相邻月。
      expect(probe.calls).assertEqual(7);

      const bounded: CalendarViewportPreloadController =
        new CalendarViewportPreloadController(2);
      const boundedProbe: CalendarPreloadProbe = new CalendarPreloadProbe();
      bounded.prewarm(boundedProbe, CalendarMode.month, new DateParts(2026, 1, 1));
      bounded.prewarm(boundedProbe, CalendarMode.month, new DateParts(2026, 2, 1));
      bounded.prewarm(boundedProbe, CalendarMode.month, new DateParts(2026, 3, 1));
      bounded.prewarm(boundedProbe, CalendarMode.month, new DateParts(2026, 1, 1));
      expect(boundedProbe.calls).assertEqual(4);
    });

    it('week_column_selection_stays_behind_course_pointer_targets', 0, () => {
      expect(MobileCalendarTimelineLayout.columnSelectionLayerZ <
        MobileCalendarTimelineLayout.courseBlockLayerZ).assertTrue();
      expect(MobileCalendarTimelineLayout.columnTapSelectsDay(false)).assertTrue();
      expect(MobileCalendarTimelineLayout.columnTapSelectsDay(true)).assertFalse();
    });

    it('expanded_tablet_week_matches_macos_timeline_metrics', 0, () => {
      expect(MobileCalendarTimelineLayout.expandedHourAxisWidth).assertEqual(52);
      expect(MobileCalendarTimelineLayout.expandedSlotAxisWidth).assertEqual(104);
      expect(MobileCalendarTimelineLayout.expandedAxisWidth()).assertEqual(156);
      expect(MobileCalendarTimelineLayout.expandedHourHeight).assertEqual(64);
      expect(MobileCalendarTimelineLayout.expandedHeaderHeight).assertEqual(72);
      expect(MobileCalendarTimelineLayout.expandedMinimumDayWidth).assertEqual(118);
      expect(MobileCalendarTimelineLayout.fittedDayWidth(1050, 7)).assertEqual(150);
      expect(MobileCalendarTimelineLayout.fittedDayWidth(700, 7) * 7).assertEqual(700);
      expect(MobileCalendarTimelineLayout.expandedAllDayRowCount(0)).assertEqual(0);
      expect(MobileCalendarTimelineLayout.expandedAllDayRowCount(2)).assertEqual(2);
      expect(MobileCalendarTimelineLayout.expandedAllDayRowCount(4)).assertEqual(3);
      expect(MobileCalendarTimelineLayout.expandedVisibleAllDayEventCount(3)).assertEqual(3);
      expect(MobileCalendarTimelineLayout.expandedVisibleAllDayEventCount(4)).assertEqual(2);
      expect(MobileCalendarTimelineLayout.expandedHiddenAllDayEventCount(4)).assertEqual(2);
      expect(MobileCalendarTimelineLayout.expandedDayHeaderTitle(
        new DateParts(2026, 8, 31), false)).assertEqual('8/31 周一');
      expect(MobileCalendarTimelineLayout.expandedDayHeaderTitle(
        new DateParts(2026, 8, 31), true)).assertEqual('8/31 Mon');
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
