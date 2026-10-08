// 移动端教学日历页，以原生 Android TeachingCalendarPage.kt 与
// YearCalendarView.kt 为基准。
// 日/周（时间线 + 日期条）、月（可展开网格 + 日程卡）、年（12 个月迷你网格 +
// 详情卡片）四种视图，支持左右滑动翻页与月视图上下滑动展开/收起。
import { AppModel } from '../../model/AppModel';
import { QMPlusSession } from '../QMPlusSession';
import { CalendarCourseworkItem, CalendarCourseworkProjection, CalendarDeadlineMoments } from './CalendarCourseworkProjection';
import { Course, HolidayItem } from '../../common/Models';
import { CourseRemovalButton } from '../CourseRemovalButton';
import { ScheduleLogic } from '../../common/ScheduleLogic';
import { StrictDates, DateParts } from '../../common/StrictDates';
import { AppTheme } from '../../common/AppTheme';
import { CalendarTypography } from '../../common/CalendarTypography';
import { DeadlineVisual, DeadlineVisualKind } from '../../common/DeadlineVisual';
import { PageTitle, SurfaceCard } from '../SharedComponents';
import {
  CalendarFormatters, CalendarGestureAxis, CalendarMode, CalendarModeInfo,
  CalendarPageRequest, CalendarPageTransitionOffsets, CalendarPageTransitionQueue, CalendarTimelineDay,
  CalendarTimelineLogic, DarkModeProbe, TeachingCalendarLogic
} from './CalendarLogic';
import { TeachingCalendarSession } from './TeachingCalendarSession';
import { MobileCalendarTimelineLayout, MobileCalendarTimelineView } from './MobileCalendarTimelineView';
import { CalendarDailyInfoCards } from './CalendarDailyInfoCards';
import {
  AssignmentDeadlineItem, PublicDeadlineItem, PublicDeadlineKindInfo, PublicDeadlineSource
} from '../../net/CalendarDailyInfoClient';
import { vibrator } from '@kit.SensorServiceKit';
import { AppLanguage, AppLocalization, LocalizationValues } from '../../common/AppLocalization';
import { DeviceState, PhoneNavigationLayout } from '../../common/DeviceState';

class MonthEvent {
  readonly id: string;
  readonly title: string;
  readonly isHoliday: boolean;
  readonly isWorkday: boolean;
  readonly tint: ResourceColor;
  readonly fill: ResourceColor;

  constructor(id: string, title: string, isHoliday: boolean, isWorkday: boolean,
    tint: ResourceColor = AppTheme.text(), fill: ResourceColor = AppTheme.selection()) {
    this.id = id;
    this.title = title;
    this.isHoliday = isHoliday;
    this.isWorkday = isWorkday;
    this.tint = tint;
    this.fill = fill;
  }
}

class CalendarDayData {
  readonly courses: Course[];
  readonly holidays: HolidayItem[];
  readonly assignments: AssignmentDeadlineItem[];
  readonly deadlines: PublicDeadlineItem[];
  monthEvents: MonthEvent[] | null = null;

  constructor(courses: Course[], holidays: HolidayItem[], assignments: AssignmentDeadlineItem[],
    deadlines: PublicDeadlineItem[]) {
    this.courses = courses;
    this.holidays = holidays;
    this.assignments = assignments;
    this.deadlines = deadlines;
  }
}

@ComponentV2
export struct MobileTeachingCalendarView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: TeachingCalendarSession = new TeachingCalendarSession();
  @Param qmPlusSession: QMPlusSession = new QMPlusSession();
  @Param hasPhoneNavigation: boolean = false;
  @Param phoneNavigationGlobalTop: number = -1;
  @Param phoneNavigationGlobalBottom: number = -1;
  @Event onOpenCourse: (source: string, id: string) => boolean = () => false;
  @Local presentedDay: DateParts | null = null;
  @Local presentedDayOpacity: number = 0;
  @Local allDayDialogDay: DateParts | null = null;
  @Local momentDialogItems: CalendarCourseworkItem[] = [];
  @Local allDayDialogModeRawValue: string = CalendarMode.week;
  @Local showingActions: boolean = false;
  @Local contentWidth: number = 350;
  private readonly isPc: boolean = DeviceState.isPc2in1();
  @Local contentHeight: number = 500;
  @Local contentGlobalTop: number = 0;
  private contentAreaMeasured: boolean = false;
  @Local monthHeaderHeight: number = 26;
  @Local incomingMonthHeaderHeight: number = 26;
  @Local rootWidth: number = 350;
  @Local rootHeight: number = 640;
  @Local isDarkMode: boolean = false;
  private darkModeProbe: DarkModeProbe = new DarkModeProbe();
  @Local rootGlobalX: number = 0;
  @Local rootGlobalY: number = 0;
  @Local presentedDayAnchorX: number = 175;
  @Local presentedDayAnchorY: number = 240;
  @Local pageOffsetX: number = 0;
  @Local incomingPageOffsetX: number = 0;
  @Local pageTransitionActive: boolean = false;
  @Local incomingDate: DateParts = StrictDates.todayParts();
  @Local incomingModeRawValue: string = CalendarMode.week;
  @Local incomingMonthSheetPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local modeIndicatorRawValue: string = CalendarMode.week;
  @Local monthSheetPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local monthDragStartPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local monthDragging: boolean = false;
  @Local monthDetailsScrollEnabled: boolean = false;
  @Local courseSectionExpanded: boolean = true;
  @Local calendarDataRevision: number = 0;
  private courseMotionGeneration: number = 0;
  private courseMotionInFlight: boolean = false;
  private pendingCalendarDataRevision: boolean = false;
  private cachedCalendarDataRevision: number = -1;
  private cachedCalendarDays: Map<string, CalendarDayData> = new Map<string, CalendarDayData>();
  private pageAnimating: boolean = false;
  private pageQueue: CalendarPageTransitionQueue = new CalendarPageTransitionQueue();
  private timelineScroller: Scroller = new Scroller();
  private incomingTimelineScroller: Scroller = new Scroller();
  private monthDetailsScroller: Scroller = new Scroller();
  private incomingMonthDetailsScroller: Scroller = new Scroller();
  private monthGestureAxis: CalendarGestureAxis | null = null;
  private monthGestureRoutedToDetails: boolean = false;
  private monthDetailsAtTopAtGestureStart: boolean = true;
  private monthExpandedTravel: number = 0;
  private monthWeekTravel: number = 0;
  private monthScrollEnableRevision: number = 0;
  private monthScrollEnableTimer: number = -1;
  private monthResetTimer: number = -1;
  private timelineScrollTimer: number = -1;
  private pendingTimelineRestoreOffsetY: number | null = null;
  private pageTransitionRevision: number = 0;
  private pageMountTimer: number = -1;
  private pageCommitTimer: number = -1;
  private pageCleanupTimer: number = -1;
  private presentedDayLoadRevision: number = 0;
  private presentedDayLoadTimer: number = -1;
  private presentedDayMountTimer: number = -1;
  private presentedDayMotionGeneration: number = 0;

  @Monitor('model.schedule', 'model.holidaysByYear', 'model.assignmentDeadlinesByDate',
    'model.publicDeadlinesByDate', 'model.favoriteDeadlines', 'model.runtimeMode', 'qmPlusSession.snapshot', 'model.qmplusEnabled',
    'model.competitionDeadlinesEnabled', 'model.conferenceDeadlinesEnabled',
    'model.schoolContestNoticesEnabled', 'model.summerCampDeadlinesEnabled',
    'model.hackathonDeadlinesEnabled', 'model.customDeadlinesEnabled', 'model.customDeadlinesURL',
    'model.languageSettingRawValue', 'model.systemLanguageID',
    'model.colorTheme.selection', 'model.colorTheme.dark')
  onCalendarDataChange(monitor: IMonitor): void {
    if (this.courseMotionInFlight) {
      this.pendingCalendarDataRevision = true;
      return;
    }
    this.calendarDataRevision++;
  }

  aboutToAppear(): void {
    this.modeIndicatorRawValue = this.session.modeRawValue;
    this.monthSheetPosition = TeachingCalendarLogic.clampMonthSheetPosition(
      this.session.monthSheetPosition);
    this.incomingMonthSheetPosition = this.monthSheetPosition;
    this.monthDetailsScrollEnabled = TeachingCalendarLogic.monthDetailsCanScrollAtGestureStart(
      this.monthSheetPosition);
    this.darkModeProbe.register((dark: boolean) => {
      this.isDarkMode = dark;
    });
  }

  aboutToDisappear(): void {
    this.contentAreaMeasured = false;
    this.finishCourseMotionForNavigation();
    this.darkModeProbe.unregister();
    const pendingPage: CalendarPageRequest | null = this.pageQueue.interrupt();
    if (pendingPage !== null) {
      this.commitPageRequest(pendingPage);
    }
    this.pageTransitionRevision++;
    this.clearPageTransitionTimers();
    this.pageAnimating = false;
    this.pageTransitionActive = false;
    this.pageOffsetX = 0;
    this.incomingPageOffsetX = 0;
    this.modeIndicatorRawValue = this.session.modeRawValue;
    this.monthScrollEnableRevision++;
    this.presentedDayLoadRevision++;
    this.presentedDayMotionGeneration++;
    if (this.presentedDayLoadTimer >= 0) {
      clearTimeout(this.presentedDayLoadTimer);
      this.presentedDayLoadTimer = -1;
    }
    if (this.presentedDayMountTimer >= 0) {
      clearTimeout(this.presentedDayMountTimer);
      this.presentedDayMountTimer = -1;
    }
    this.presentedDay = null;
    this.presentedDayOpacity = 0;
    if (this.monthScrollEnableTimer >= 0) {
      clearTimeout(this.monthScrollEnableTimer);
      this.monthScrollEnableTimer = -1;
    }
    if (this.monthResetTimer >= 0) {
      clearTimeout(this.monthResetTimer);
      this.monthResetTimer = -1;
    }
    // 清理延迟滚动定时器，避免对已销毁 Scroller 操作（BUG-012 修复）。
    if (this.timelineScrollTimer >= 0) {
      clearTimeout(this.timelineScrollTimer);
      this.timelineScrollTimer = -1;
    }
  }

  @Monitor('session.modeRawValue')
  onModeChange(monitor: IMonitor): void {
    if (!this.pageAnimating) {
      this.modeIndicatorRawValue = this.session.modeRawValue;
    }
  }

  private mode(): CalendarMode {
    return CalendarModeInfo.fromRawValue(this.session.modeRawValue);
  }

  private indicatorMode(): CalendarMode {
    return CalendarModeInfo.fromRawValue(this.modeIndicatorRawValue);
  }

  private isEnglish(): boolean {
    return this.model.resolvedLanguage() === AppLanguage.english;
  }

  private selectedDate(): DateParts {
    return this.session.selectedDate;
  }

  private setSelectedDate(date: DateParts): void {
    this.cancelPageTransitionForDirectSelection();
    if (!date.equals(this.selectedDate())) {
      this.finishCourseMotionForNavigation();
    }
    this.session.selectDate(date);
  }

  private setMode(mode: CalendarMode): void {
    this.cancelPageTransitionForDirectSelection();
    if (mode !== this.mode()) {
      this.finishCourseMotionForNavigation();
    }
    this.session.modeRawValue = mode;
  }

  private finishCourseMotionForNavigation(): void {
    this.courseMotionGeneration++;
    this.courseMotionInFlight = false;
    if (this.pendingCalendarDataRevision) {
      this.pendingCalendarDataRevision = false;
      this.calendarDataRevision++;
    }
  }

  private cancelPageTransitionForDirectSelection(): void {
    if (!this.pageAnimating) {
      return;
    }
    this.pageQueue.interrupt();
    this.pageTransitionRevision++;
    this.clearPageTransitionTimers();
    this.pageAnimating = false;
    this.pageTransitionActive = false;
    this.pageOffsetX = 0;
    this.incomingPageOffsetX = 0;
    this.modeIndicatorRawValue = this.session.modeRawValue;
  }

  private toggleCourseSection(): void {
    const expanded: boolean = !this.courseSectionExpanded;
    const generation: number = ++this.courseMotionGeneration;
    this.courseMotionInFlight = true;
    this.getUIContext().animateTo({
      duration: 160,
      curve: Curve.EaseOut,
      onFinish: (): void => {
        if (generation !== this.courseMotionGeneration) {
          return;
        }
        this.courseMotionInFlight = false;
        if (this.pendingCalendarDataRevision) {
          this.pendingCalendarDataRevision = false;
          this.calendarDataRevision++;
        }
      }
    }, (): void => {
      this.courseSectionExpanded = expanded;
    });
  }

  private animateMode(mode: CalendarMode): void {
    const effectiveMode: CalendarMode = this.pageQueue.effectiveMode(this.mode());
    if (mode === effectiveMode) {
      return;
    }
    const direction: number = TeachingCalendarLogic.modeTransitionDirection(effectiveMode, mode);
    this.animatePageChange(direction, this.pageQueue.effectiveDate(this.selectedDate()), mode);
  }

  private coursesOn(date: DateParts): Course[] {
    return this.dayDataOn(date).courses;
  }

  private holidayItemsOn(date: DateParts): HolidayItem[] {
    return this.dayDataOn(date).holidays;
  }

  private dayDataOn(date: DateParts): CalendarDayData {
    // 和宽屏时间线一样，缓存命中仍读取 @Local revision，保留 ArkUI 的更新依赖。
    // 月份拖动/日期点选不改变源数据，不应在各个格子修饰符里重复筛选和 merge/sort。
    const revision: number = this.calendarDataRevision;
    if (this.cachedCalendarDataRevision !== revision) {
      this.cachedCalendarDays.clear();
      this.cachedCalendarDataRevision = revision;
    }
    const target: string = StrictDates.formatDateParts(date);
    const cached: CalendarDayData | undefined = this.cachedCalendarDays.get(target);
    if (cached !== undefined) {
      return cached;
    }
    // 足够同时容纳相邻两年的转场，长时间翻页也不会无限保留历史日期。
    if (this.cachedCalendarDays.size >= 800) {
      this.cachedCalendarDays.clear();
    }
    const holidays: HolidayItem[] = [];
    for (const item of this.model.holidayItems(date.year)) {
      if (item.date === target) {
        holidays.push(item);
      }
    }
    const result: CalendarDayData = new CalendarDayData(this.model.coursesOn(date), holidays,
      this.model.assignmentDeadlinesByDate.get(target) ?? [], this.model.deadlineItems(target));
    this.cachedCalendarDays.set(target, result);
    return result;
  }

  private weekDates(containing: DateParts = this.selectedDate()): DateParts[] {
    const weekday: number = StrictDates.weekdayMonday1(containing);
    const start: DateParts = StrictDates.addDays(containing, 1 - weekday);
    const result: DateParts[] = [];
    for (let i = 0; i < 7; i++) {
      result.push(StrictDates.addDays(start, i));
    }
    return result;
  }

  private monthGridDates(containing: DateParts): DateParts[] {
    const first: DateParts = new DateParts(containing.year, containing.month, 1);
    const leading: number = StrictDates.weekdayMonday1(first) - 1;
    const gridStart: DateParts = StrictDates.addDays(first, -leading);
    const result: DateParts[] = [];
    for (let i = 0; i < 42; i++) {
      result.push(StrictDates.addDays(gridStart, i));
    }
    return result;
  }

  private yearDates(containing: DateParts): DateParts[] {
    const result: DateParts[] = [];
    for (let month = 1; month <= 12; month++) {
      const count: number = StrictDates.daysInMonth(containing.year, month);
      for (let day = 1; day <= count; day++) {
        result.push(new DateParts(containing.year, month, day));
      }
    }
    return result;
  }

  private visibleHolidayYears(renderMode: CalendarMode = this.mode(),
    renderDate: DateParts = this.selectedDate()): number[] {
    const result: Set<number> = new Set<number>();
    if (renderMode === CalendarMode.week) {
      for (const day of this.weekDates(renderDate)) {
        result.add(day.year);
      }
    } else if (renderMode === CalendarMode.month) {
      for (const day of this.monthGridDates(renderDate)) {
        result.add(day.year);
      }
    } else {
      result.add(renderDate.year);
    }
    const list: number[] = [];
    for (const year of result) {
      list.push(year);
    }
    return list;
  }

  private holidayStatus(renderMode: CalendarMode = this.mode(),
    renderDate: DateParts = this.selectedDate()): string {
    for (const year of this.visibleHolidayYears(renderMode, renderDate)) {
      const status: string | undefined = this.model.holidayStatusByYear.get(year);
      if (status !== undefined && status.length > 0) {
        return status;
      }
    }
    return '';
  }

  private animateDate(direction: number): void {
    const mode: CalendarMode = this.pageQueue.effectiveMode(this.mode());
    const baseDate: DateParts = this.pageQueue.effectiveDate(this.selectedDate());
    const anchoredMonthNavigation: boolean = mode === CalendarMode.month;
    const target: DateParts = anchoredMonthNavigation ?
      this.session.monthNavigationDestination(direction, baseDate) :
      TeachingCalendarLogic.movedDate(baseDate, mode, direction);
    this.animatePageChange(direction, target, mode, anchoredMonthNavigation);
  }

  private animatePageChange(direction: number, targetDate: DateParts, targetMode: CalendarMode,
    preservesMonthNavigationAnchor: boolean = false,
    targetMonthSheetPosition: number | null = null): void {
    if (direction === 0) {
      return;
    }
    const request: CalendarPageRequest = new CalendarPageRequest(direction, targetDate, targetMode,
      preservesMonthNavigationAnchor, targetMode === CalendarMode.month ?
        (targetMonthSheetPosition ?? this.monthSheetPosition) : targetMonthSheetPosition);
    if (!this.pageQueue.submit(request)) {
      return;
    }
    this.runPageTransition(request);
  }

  private runPageTransition(request: CalendarPageRequest): void {
    this.finishCourseMotionForNavigation();
    this.monthScrollEnableRevision++;
    if (this.monthScrollEnableTimer >= 0) {
      clearTimeout(this.monthScrollEnableTimer);
      this.monthScrollEnableTimer = -1;
    }
    if (this.monthResetTimer >= 0) {
      clearTimeout(this.monthResetTimer);
      this.monthResetTimer = -1;
    }
    this.clearPageTransitionTimers();
    const revision: number = ++this.pageTransitionRevision;
    this.performCalendarHaptic();
    this.pageAnimating = true;
    const distance: number = Math.max(this.contentWidth, 320);
    this.incomingDate = request.date;
    this.incomingModeRawValue = request.mode;
    this.incomingMonthSheetPosition = request.monthSheetPosition === null ?
      TeachingCalendarLogic.clampMonthSheetPosition(this.monthSheetPosition) :
      TeachingCalendarLogic.clampMonthSheetPosition(request.monthSheetPosition as number);
    const offsets: CalendarPageTransitionOffsets =
      TeachingCalendarLogic.pageTransitionOffsets(request.direction, distance);
    this.incomingPageOffsetX = offsets.incomingStartX;
    this.pageTransitionActive = true;

    // 先挂载相邻页面，下一帧再让两页同时移动，避免旧实现中间出现空白帧。
    this.pageMountTimer = setTimeout(() => {
      this.pageMountTimer = -1;
      if (revision !== this.pageTransitionRevision) {
        return;
      }
      animateTo({ duration: TeachingCalendarLogic.pageTransitionDuration,
        curve: Curve.EaseInOut }, (): void => {
        this.modeIndicatorRawValue = request.mode;
        this.pageOffsetX = offsets.outgoingEndX;
        this.incomingPageOffsetX = 0;
      });
      this.pageCommitTimer = setTimeout(() => {
        this.pageCommitTimer = -1;
        if (revision !== this.pageTransitionRevision) {
          return;
        }
        this.commitPageRequest(request);
        // 先让带新 identity 的 current page 在已经居中的 incoming page 后方挂载。
        // 下一帧再卸载 incoming，避免同一批状态提交使旧 Builder 子树重新出现。
        this.pageOffsetX = 0;
        this.pageCleanupTimer = setTimeout(() => {
          this.pageCleanupTimer = -1;
          if (revision !== this.pageTransitionRevision) {
            return;
          }
          this.incomingPageOffsetX = 0;
          this.pageTransitionActive = false;
          this.pageAnimating = false;
          const next: CalendarPageRequest | null = this.pageQueue.completeActive();
          if (next !== null) {
            this.runPageTransition(next);
          } else if (request.mode === CalendarMode.month) {
            this.resetMonthDetailsScroll();
          }
        }, 16);
      }, 310);
    }, 16);
  }

  private commitPageRequest(request: CalendarPageRequest): void {
    if (!request.date.equals(this.selectedDate())) {
      if (request.preservesMonthAnchor) {
        this.session.commitMonthNavigation(request.date);
      } else {
        this.session.selectDate(request.date);
      }
    }
    this.session.modeRawValue = request.mode;
    if (request.mode === CalendarMode.month) {
      this.monthSheetPosition = request.monthSheetPosition === null ?
        TeachingCalendarLogic.clampMonthSheetPosition(this.monthSheetPosition) :
        TeachingCalendarLogic.clampMonthSheetPosition(request.monthSheetPosition as number);
      this.session.setMonthSheetPosition(this.monthSheetPosition);
      this.monthDetailsScrollEnabled = TeachingCalendarLogic.monthDetailsCanScrollAtGestureStart(
        this.monthSheetPosition);
    }
  }

  private clearPageTransitionTimers(): void {
    if (this.pageMountTimer >= 0) {
      clearTimeout(this.pageMountTimer);
      this.pageMountTimer = -1;
    }
    if (this.pageCommitTimer >= 0) {
      clearTimeout(this.pageCommitTimer);
      this.pageCommitTimer = -1;
    }
    if (this.pageCleanupTimer >= 0) {
      clearTimeout(this.pageCleanupTimer);
      this.pageCleanupTimer = -1;
    }
  }

  private navigateTo(date: DateParts): void {
    if (!date.equals(this.selectedDate())) {
      this.performCalendarHaptic();
    }
    if (this.mode() === CalendarMode.week && !date.equals(this.selectedDate()) &&
      this.weekDates(date)[0].equals(this.weekDates(this.selectedDate())[0])) {
      try {
        const currentOffsetY: number = this.timelineScroller.currentOffset().yOffset;
        this.pendingTimelineRestoreOffsetY = Number.isFinite(currentOffsetY) ?
          Math.max(currentOffsetY, 0) : null;
      } catch (e) {
        this.pendingTimelineRestoreOffsetY = null;
      }
    }
    if (this.mode() === CalendarMode.month &&
      this.monthSheetPosition > TeachingCalendarLogic.monthSheetExpandedPosition + 0.01) {
      this.setSelectedDate(date);
      this.resetMonthDetailsScroll();
      return;
    }
    this.setSelectedDate(date);
  }

  private performCalendarHaptic(): void {
    vibrator.startVibration({ type: 'time', duration: 12 }, { usage: 'touch' })
      .catch((): void => {
        // 模拟器或未配备振动器的设备不应阻断日历交互。
      });
  }

  private handlePeriodSwipe(offsetX: number, offsetY: number, velocityX: number): void {
    if (this.mode() === CalendarMode.year) {
      return;
    }
    const predicted: number = Math.abs(velocityX) > 200 ? velocityX * 0.25 : offsetX;
    const direction: number | null = TeachingCalendarLogic.swipeDirection(offsetX, offsetY, predicted);
    if (direction !== null) {
      this.animateDate(direction);
    }
  }

  private beginMonthGesture(): void {
    this.monthDragging = false;
    this.monthGestureAxis = null;
    this.monthGestureRoutedToDetails = false;
    this.monthDragStartPosition = this.monthSheetPosition;
    const expanded: number = this.contentAreaMeasured ? this.expandedMonthCellHeight() : 0;
    const compact: number = Math.min(TeachingCalendarLogic.monthCollapsedCellHeight, expanded);
    this.monthExpandedTravel = 6 * (expanded - compact);
    this.monthWeekTravel = 5 * compact;
    this.monthScrollEnableRevision++;
    this.monthDetailsScrollEnabled = TeachingCalendarLogic.monthDetailsCanScrollAtGestureStart(
      this.monthDragStartPosition);
    if (this.monthSheetPosition <= TeachingCalendarLogic.monthSheetExpandedPosition + 0.01) {
      this.monthDetailsAtTopAtGestureStart = true;
      return;
    }
    const offset: OffsetResult = this.monthDetailsScroller.currentOffset();
    this.monthDetailsAtTopAtGestureStart = offset.yOffset <= 1;
  }

  private updateMonthGesture(offsetX: number, offsetY: number): void {
    if (this.monthGestureRoutedToDetails) {
      return;
    }
    if (this.monthGestureAxis === null) {
      const axis: CalendarGestureAxis | null = TeachingCalendarLogic.gestureAxis(offsetX, offsetY);
      if (axis === null) {
        return;
      }
      if (axis === CalendarGestureAxis.vertical && !TeachingCalendarLogic.monthSheetOwnsGesture(
        offsetY, this.monthDragStartPosition, this.monthDetailsAtTopAtGestureStart)) {
        // 手势从已上滚的详情区开始时，整次手势都交给 List，
        // 不在到达顶部的同一次拖动中改变月视图档位。
        this.monthGestureRoutedToDetails = true;
        return;
      }
      this.monthGestureAxis = axis;
    }
    if (this.monthGestureAxis !== CalendarGestureAxis.vertical) {
      return;
    }
    if (!this.monthDragging && TeachingCalendarLogic.canMoveMonthSheet(
      offsetX, offsetY, this.monthDragStartPosition)) {
      this.monthDragging = true;
    }
    if (this.monthDragging) {
      this.monthSheetPosition = TeachingCalendarLogic.monthSheetDragPosition(
        offsetY, this.monthDragStartPosition, this.monthExpandedTravel, this.monthWeekTravel);
    }
  }

  private finishMonthGesture(offsetX: number, offsetY: number,
    velocityX: number, velocityY: number): void {
    if (this.monthGestureRoutedToDetails) {
      this.resetMonthGestureRouting();
      return;
    }
    if (this.monthDragging) {
      const target: number = TeachingCalendarLogic.settledMonthSheetPosition(
        this.monthSheetPosition, velocityY);
      this.resetMonthGestureRouting();
      this.settleMonthSheet(target);
      return;
    }
    if (this.monthGestureAxis === CalendarGestureAxis.horizontal) {
      const predicted: number = Math.abs(velocityX) > 200 ? velocityX * 0.25 : offsetX;
      const direction: number | null = TeachingCalendarLogic.swipeDirection(offsetX, offsetY, predicted);
      this.resetMonthGestureRouting();
      if (direction !== null) {
        this.animateDate(direction);
      }
      return;
    }
    this.resetMonthGestureRouting();
  }

  private resetMonthGestureRouting(): void {
    this.monthDragging = false;
    this.monthGestureAxis = null;
    this.monthGestureRoutedToDetails = false;
  }

  private settleMonthSheet(position: number, haptic: boolean = true): void {
    const target: number = Math.min(Math.max(Math.round(position), 0), 2);
    if (haptic && target !== Math.round(this.monthSheetPosition)) {
      this.performCalendarHaptic();
    }
    const duration: number = 120 + 160 * Math.abs(target - this.monthSheetPosition);
    animateTo({ duration: duration,
      curve: Curve.EaseInOut }, (): void => {
      this.monthSheetPosition = target;
    });
    this.session.setMonthSheetPosition(target);
    const scrollRevision: number = ++this.monthScrollEnableRevision;
    if (this.monthScrollEnableTimer >= 0) {
      clearTimeout(this.monthScrollEnableTimer);
      this.monthScrollEnableTimer = -1;
    }
    if (target < TeachingCalendarLogic.monthSheetWeekPosition) {
      this.monthDetailsScrollEnabled = false;
    } else {
      this.monthScrollEnableTimer = setTimeout(() => {
        this.monthScrollEnableTimer = -1;
        if (scrollRevision === this.monthScrollEnableRevision &&
          this.session.monthSheetPosition >= TeachingCalendarLogic.monthSheetWeekPosition - 0.01) {
          this.monthDetailsScrollEnabled = true;
        }
      }, duration + 12);
    }
    if (target < TeachingCalendarLogic.monthSheetWeekPosition) {
      this.resetMonthDetailsScroll();
    }
  }

  private resetMonthDetailsScroll(): void {
    if (this.monthResetTimer >= 0) {
      clearTimeout(this.monthResetTimer);
    }
    this.monthResetTimer = setTimeout(() => {
      this.monthResetTimer = -1;
      this.monthDetailsScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }, 0);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.compactHeader()
        Stack({ alignContent: Alignment.TopStart }) {
          // ComponentV2 不会因为嵌套 @Builder 的 DateParts 参数变化而可靠地
          // 重建既有子树。日/周仍以完整日期刷新目标页，月/年网格按显示周期复用；
          // 其选中态显式读取 session，点选一天无需销毁整页和重置滚动。
          ForEach([this.currentPageIdentity()], (identity: string) => {
            Column() {
              if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
                this.timelineContent(this.mode(), this.selectedDate(), true)
              } else if (this.mode() === CalendarMode.month) {
                this.monthView(this.selectedDate(), true)
              } else {
                this.yearView(this.selectedDate(), true)
              }
            }
            .width('100%')
            .height('100%')
            .translate({ x: this.pageOffsetX })
            .id('calendar.mobile.current-page.' + identity)
          }, (identity: string) => identity)

          if (this.pageTransitionActive) {
            Column() {
              this.incomingCalendarPage()
            }
            .width('100%')
            .height('100%')
            .translate({ x: this.incomingPageOffsetX })
            .enabled(false)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.contentWidth = Number(newArea.width);
          this.contentHeight = Number(newArea.height);
          this.contentGlobalTop = Number(newArea.globalPosition.y);
          this.contentAreaMeasured = this.contentHeight > 0;
        })
      }
      .width('100%')
      .height('100%')

      if (this.presentedDay !== null) {
        this.dayDetailOverlay()
      }
      if (this.allDayDialogDay !== null) {
        this.weekAllDayDialogOverlay()
      }
      if (this.showingActions) {
        this.actionsOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.rootWidth = Number(newArea.width);
      this.rootHeight = Number(newArea.height);
      this.rootGlobalX = Number(newArea.globalPosition.x);
      this.rootGlobalY = Number(newArea.globalPosition.y);
    })
  }

  private currentPageIdentity(): string {
    return TeachingCalendarLogic.mobilePageIdentity(this.mode(), this.selectedDate());
  }

  private monthPageIdentity(date: DateParts): string {
    return date.year.toString() + '-' + (date.month < 10 ? '0' : '') + date.month.toString();
  }

  @Builder
  incomingCalendarPage() {
    if (CalendarModeInfo.fromRawValue(this.incomingModeRawValue) === CalendarMode.day ||
      CalendarModeInfo.fromRawValue(this.incomingModeRawValue) === CalendarMode.week) {
      this.timelineContent(CalendarModeInfo.fromRawValue(this.incomingModeRawValue),
        this.incomingDate, false)
    } else if (CalendarModeInfo.fromRawValue(this.incomingModeRawValue) === CalendarMode.month) {
      this.monthView(this.incomingDate, false)
    } else {
      this.yearView(this.incomingDate, false)
    }
  }

  // ---------- 顶部 ----------

  @Builder
  compactHeader() {
    Column({ space: 0 }) {
      Row({ space: 0 }) {
        Text(this.periodTitle())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .maxLines(1)
          .layoutWeight(1)
          .height(36)
          .onClick(() => {
            this.showDatePicker();
          })

        Text(this.model.text('今天'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.primary())
          .width(52)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.navigateTo(StrictDates.todayParts());
          })

        Text('‹')
          .fontSize(24)
          .fontColor(AppTheme.text())
          .width(34)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.animateDate(-1);
          })

        Text('›')
          .fontSize(24)
          .fontColor(AppTheme.text())
          .width(34)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.animateDate(1);
          })

        Text('⋯')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showingActions = true;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 12, top: 5, bottom: 5 })

      Row() {
        ForEach(CalendarModeInfo.all, (item: CalendarMode) => {
          Text(this.model.text(item))
            .fontSize(14)
            .fontWeight(this.indicatorMode() === item ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(AppTheme.text())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(32)
            .backgroundColor(this.indicatorMode() === item ?
              AppTheme.segmentedSelection() : Color.Transparent)
            .borderRadius(6)
            .animation({ duration: TeachingCalendarLogic.pageTransitionDuration,
              curve: Curve.EaseInOut })
            .onClick(() => {
              this.animateMode(item);
            })
        }, (item: CalendarMode) => 'mode.' + item)
      }
      .width('100%')
      .height(38)
      .padding(3)
      .margin({ left: 12, right: 12, top: 4 })
      .borderRadius(10)
      .backgroundColor(AppTheme.surfaceVariant())

      // 日期条跟随动画目标模式，而不是等 session.modeRawValue 在页面动画
      // 结束后才提交，避免周 -> 月时月页已经出现但周日期条仍滞留。
      if (TeachingCalendarLogic.showsCompactDateStrip(this.indicatorMode())) {
        Column() {
          this.weekDateStrip()
        }
        .padding({ top: 6 })
      }
    }
    .width('100%')
    .backgroundColor(AppTheme.surface())
  }

  @Builder
  weekDateStrip() {
    Row({ space: 0 }) {
      if (TeachingCalendarLogic.showsCompactWeekAxis(this.indicatorMode())) {
        Column({ space: 0 }) {
          Text((this.isEnglish() ? 'Cal ' : this.model.resolvedLanguage() === AppLanguage.simplifiedChinese ?
            '公历 ' : this.model.text('公历') + ' ') +
            StrictDates.isoWeekNumber(this.selectedDate()).toString())
            .fontSize(CalendarTypography.fontSize(9.5, this.isPc))
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.secondaryText())
          Text((this.isEnglish() ? 'Teach ' : this.model.resolvedLanguage() === AppLanguage.simplifiedChinese ?
            '教学 ' : this.model.text('教学') + ' ') +
            (this.model.weekNumberOn(this.selectedDate()) === null ? '—' :
              (this.model.weekNumberOn(this.selectedDate()) as number).toString()))
            .fontSize(CalendarTypography.fontSize(9.5, this.isPc))
            .fontColor(AppTheme.secondaryText())
        }
        .width(MobileCalendarTimelineLayout.axisWidth)
        .height(56)
        .justifyContent(FlexAlign.Center)
      }
      ForEach(this.weekDates(), (day: DateParts) => {
        this.dateStripButton(day)
      }, (day: DateParts) => 'strip.' + StrictDates.formatDateParts(day))
    }
    .width('100%')
    .padding({ left: 0, right: 0 })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          this.handlePeriodSwipe(event.offsetX, event.offsetY, event.velocityX);
        })
    )
  }

  @Builder
  dateStripButton(day: DateParts) {
    Column({ space: 3 }) {
      Text(CalendarFormatters.weekdayLabel(day, this.model.resolvedLanguage()))
        .fontSize(11)
        .fontWeight(day.equals(this.selectedDate()) || day.equals(StrictDates.todayParts()) ?
          FontWeight.Bold : FontWeight.Regular)
        .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() :
          this.stripForeground(this.firstHoliday(day)))
      Text(day.day.toString())
        .fontSize(11)
        .fontWeight(day.equals(this.selectedDate()) || day.equals(StrictDates.todayParts()) ?
          FontWeight.Bold : FontWeight.Regular)
        .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() :
          this.stripForeground(this.firstHoliday(day)))
      Row({ space: 2 }) {
        if (this.firstHoliday(day) !== null) {
          Text(this.model.text(this.firstHoliday(day)?.type === 'holiday' ? '休' : '班'))
            .fontSize(CalendarTypography.fontSize(8, this.isPc))
            .fontWeight(FontWeight.Bold)
            .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() :
              this.stripForeground(this.firstHoliday(day)))
        }
        if (this.coursesOn(day).length > 0) {
          Column()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() :
              this.stripForeground(this.firstHoliday(day)))
        }
      }
      .height(this.isPc ? 14 : 8)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(day.equals(this.selectedDate()) ? AppTheme.selectedDate() : Color.Transparent)
    .borderRadius(10)
    .border({
      radius: 10,
      width: day.equals(StrictDates.todayParts()) ? 2 : 0,
      color: day.equals(StrictDates.todayParts()) ?
        AppTheme.nowIndicator() : Color.Transparent
    })
    .onClick(() => {
      this.navigateTo(day);
    })
  }

  private showDatePicker(): void {
    const selected: Date = new Date(this.selectedDate().year,
      this.selectedDate().month - 1, this.selectedDate().day, 12, 0, 0);
    DatePickerDialog.show({
      start: new Date(2000, 0, 1, 12, 0, 0),
      end: new Date(2100, 11, 31, 12, 0, 0),
      selected: selected,
      lunar: false,
      showTime: false,
      onAccept: (value: DatePickerResult): void => {
        if (value.year !== undefined && value.month !== undefined && value.day !== undefined) {
          this.navigateTo(new DateParts(value.year, value.month + 1, value.day));
        }
      }
    });
  }

  private stripForeground(holiday: HolidayItem | null): ResourceColor {
    if (holiday === null) {
      return AppTheme.text();
    }
    return holiday.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary();
  }

  private firstHoliday(day: DateParts): HolidayItem | null {
    const items: HolidayItem[] = this.holidayItemsOn(day);
    return items.length > 0 ? items[0] : null;
  }

  @Builder
  statusArea(useSurface: boolean = true, renderMode: CalendarMode = this.mode(),
    renderDate: DateParts = this.selectedDate()) {
    if (this.statusMessages(renderMode, renderDate).length > 0) {
      Column({ space: 4 }) {
        ForEach(this.statusMessages(renderMode, renderDate), (message: string, index: number) => {
        Text(this.model.text(message))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
            .maxLines(2)
            .width('100%')
        }, (message: string, index: number) => 'status.' + index.toString() + '.' + message)
      }
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(useSurface ? AppTheme.surface() : AppTheme.background())
    }
  }

  private statusMessages(renderMode: CalendarMode = this.mode(),
    renderDate: DateParts = this.selectedDate()): string[] {
    const result: string[] = [];
    const holiday: string = this.holidayStatus(renderMode, renderDate);
    if (holiday.length > 0) {
      result.push(holiday);
    }
    if (this.model.statusMessage.length > 0) {
      result.push(this.model.statusMessage);
    }
    if (this.model.calendarImportStatusMessage.length > 0) {
      result.push(this.model.calendarImportStatusMessage);
    }
    return result;
  }

  // ---------- 时间线（日/周） ----------

  @Builder
  timelineContent(renderMode: CalendarMode, renderDate: DateParts, interactive: boolean) {
    Column({ space: 0 }) {
      this.selectedDateSummary(
        TeachingCalendarLogic.timelineCourseSummaryDate(renderMode, renderDate), interactive)
      if (this.coursesOn(
        TeachingCalendarLogic.timelineCourseSummaryDate(renderMode, renderDate)).length > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            this.selectedDateCourses(
              TeachingCalendarLogic.timelineCourseSummaryDate(renderMode, renderDate))
          }
          .width('100%')
          .height(TeachingCalendarLogic.courseSummaryViewportHeight(this.coursesOn(
            TeachingCalendarLogic.timelineCourseSummaryDate(renderMode, renderDate)).length))
          .position({ x: 0, y: 0 })
        }
        .width('100%')
        .height(this.courseSectionExpanded ?
          TeachingCalendarLogic.courseSummaryViewportHeight(this.coursesOn(
            TeachingCalendarLogic.timelineCourseSummaryDate(renderMode, renderDate)).length) : 0)
        .opacity(this.courseSectionExpanded ? 1 : 0)
        .clip(true)
        .enabled(this.courseSectionExpanded)
      }
      this.statusArea(true, renderMode, renderDate)
      this.allDayItems(renderMode, renderDate, interactive)
      Scroll(interactive ? this.timelineScroller : this.incomingTimelineScroller) {
        Column() {
          MobileCalendarTimelineView({
            days: this.timelineDays(renderMode, renderDate),
            placements: MobileCalendarTimelineView.placementsFor(
              this.timelineDays(renderMode, renderDate)),
            coursework: this.timelineCoursework(renderMode, renderDate),
            selectedDate: renderDate,
            showsWeekColumns: renderMode === CalendarMode.week,
            onSelectDay: (day: DateParts): void => {
              if (interactive) {
                this.navigateTo(day);
              }
            },
            onOpenCoursework: (item: CalendarCourseworkItem, day: DateParts): void => {
              if (!interactive) { return; }
              if (item.courseID === null || !this.onOpenCourse(item.source, item.courseID)) {
                this.presentAllDayDialog(day, renderMode, false);
                this.momentDialogItems = [item];
              }
            },
            onMoreCoursework: (items: CalendarCourseworkItem[], day: DateParts): void => {
              if (interactive) { this.presentAllDayDialog(day, renderMode, false); this.momentDialogItems = items; }
            }
          })
          Column()
            .height(MobileCalendarTimelineLayout.bottomContentInset)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .id('calendar.mobile.timeline-scroll')
      .onAppear(() => {
        if (interactive) {
          this.scrollTimelineToInitialHour(renderMode, renderDate, this.timelineScroller);
        }
      })
    }
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          if (interactive) {
            this.handlePeriodSwipe(event.offsetX, event.offsetY, event.velocityX);
          }
        })
    )
  }

  private timelineCoursework(renderMode: CalendarMode, renderDate: DateParts): Map<string, CalendarCourseworkItem[]> {
    const result: Map<string, CalendarCourseworkItem[]> = new Map<string, CalendarCourseworkItem[]>();
    for (const day of this.timelineDays(renderMode, renderDate)) {
      const items: CalendarCourseworkItem[] = [];
      if (this.model.isSampleMode()) {
        for (const item of this.allDayItemsOn(day.date)) { if (item.coursework !== null) { items.push(item.coursework); } }
      } else {
        const date: string = StrictDates.formatDateParts(day.date);
        items.push(...CalendarDeadlineMoments.cloudOn(date, this.model.assignmentMomentCatalog, this.model.cloudCourses));
        if (this.model.qmplusEnabled) { items.push(...CalendarCourseworkProjection.qm(date, this.qmPlusSession.snapshot)); }
      }
      result.set(StrictDates.formatDateParts(day.date), items);
    }
    return result;
  }

  private timelineDays(renderMode: CalendarMode = this.mode(),
    renderDate: DateParts = this.selectedDate()): CalendarTimelineDay[] {
    const days: DateParts[] = renderMode === CalendarMode.week ?
      this.weekDates(renderDate) : [renderDate];
    const result: CalendarTimelineDay[] = [];
    for (const day of days) {
      result.push(new CalendarTimelineDay(day, this.coursesOn(day), this.holidayItemsOn(day)));
    }
    return result;
  }

  @Builder
  selectedDateSummary(renderDate: DateParts, interactive: boolean) {
    Row({ space: 8 }) {
      Text(CalendarFormatters.fullDate(renderDate, this.model.resolvedLanguage()))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .maxLines(1)
        .layoutWeight(1)
      Text(this.model.text(this.coursesOn(renderDate).length === 0 ? '暂无课程' :
        this.coursesOn(renderDate).length.toString() + ' 门课'))
        .fontSize(11)
        .fontColor(AppTheme.secondaryText())
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(14)
        .fontColor([AppTheme.secondaryText()])
        .rotate({ angle: this.courseSectionExpanded ? 180 : 0 })
    }
    .height(36)
    .padding({ left: 16, right: 16, top: 5, bottom: 5 })
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.surface())
    .onClick(() => {
      if (interactive) {
        this.toggleCourseSection();
      }
    })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          if (interactive) {
            this.handlePeriodSwipe(event.offsetX, event.offsetY, event.velocityX);
          }
        })
    )
  }

  @Builder
  selectedDateCourses(renderDate: DateParts) {
    Column({ space: TeachingCalendarLogic.courseSummaryRowSpacing }) {
      if (this.coursesOn(renderDate).length === 0) {
        Text(this.model.text('暂无课程'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      } else {
        ForEach(this.coursesOn(renderDate), (course: Course, index: number) => {
          Row({ space: 8 }) {
            Column()
              .width(3)
              .height(30)
              .borderRadius(1.5)
              .backgroundColor(AppTheme.primaryFill())
            Column({ space: 1 }) {
              Text(course.name)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.text())
                .maxLines(1)
              Text(this.courseSubtitle(course))
                .fontSize(10.5)
                .fontColor(AppTheme.secondaryText())
                .maxLines(1)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            CourseRemovalButton({ course: course, date: renderDate })
          }
          .width('100%')
          .height(TeachingCalendarLogic.courseSummaryRowHeight)
        }, (course: Course, index: number) => 'selected-course.' + course.id + '.' + index.toString())
      }
    }
    .padding({ left: 16, right: 16, top: 6, bottom: 8 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AppTheme.surface())
  }

  private courseSubtitle(course: Course): string {
    const parts: string[] = [this.model.courseTimeText(course), CalendarTimelineLogic.courseMetadata(course)];
    return parts.filter((value: string) => value.length > 0).join(' · ')
      .replace('教师：', this.model.text('教师：'));
  }

  @Builder
  allDayItems(renderMode: CalendarMode, renderDate: DateParts, interactive: boolean) {
    if (renderMode === CalendarMode.week && this.allDayEntries(renderMode, renderDate).length > 0) {
      this.weekAllDayItems(renderDate, interactive)
    } else if (renderMode === CalendarMode.day && this.allDayItemsOn(renderDate).length > 0) {
      this.dayAllDayItems(renderDate, interactive)
    }
  }

  @Builder
  dayAllDayItems(renderDate: DateParts, interactive: boolean) {
    Scroll() {
      Row({ space: 8 }) {
        Text(this.model.text('全天'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.secondaryText())
        ForEach(this.allDayItemsOn(renderDate).slice(0, 3), (item: CalendarAllDayItem) => {
          Text(CalendarFormatters.monthDayCompact(renderDate, this.model.resolvedLanguage()) + ' · ' + item.title)
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.tint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(6)
            .backgroundColor(item.fill)
            .onClick(() => {
              if (interactive) {
                this.activateCoursework(renderDate, item, CalendarMode.day);
              }
            })
        }, (item: CalendarAllDayItem) => 'selected-all-day-item.' + item.id + AppTheme.colorKey())
        if (this.allDayItemsOn(renderDate).length > 3) {
          Text('+' + (this.allDayItemsOn(renderDate).length - 3).toString())
            .fontSize(10.5).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary())
            .height(30).padding({ left: 10, right: 10 }).borderRadius(6)
            .backgroundColor(AppTheme.background()).border({ radius: 6, width: 1, color: AppTheme.border() })
            .onClick(() => { if (interactive) { this.presentAllDayDialog(renderDate, CalendarMode.day); } })
        }
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .height(46)
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Fade, { alwaysEnabled: true })
    .width('100%')
    .height(46)
    .backgroundColor(AppTheme.surface())
  }

  @Builder
  weekAllDayItems(renderDate: DateParts, interactive: boolean) {
    Scroll() {
      Row({ space: 0 }) {
        Text(this.model.text('全天')).fontSize(11).fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText()).width(MobileCalendarTimelineLayout.axisWidth)
          .height(40).textAlign(TextAlign.Center)
        ForEach(this.weekDates(renderDate), (day: DateParts) => {
          Column({ space: 0 }) {
            ForEach(this.allDayItemsOn(day).slice(0, MobileCalendarTimelineLayout.expandedVisibleAllDayEventCount(
              this.allDayItemsOn(day).length)), (item: CalendarAllDayItem) => {
              Text(item.title).fontSize(CalendarTypography.fontSize(9.5, this.isPc))
                .fontWeight(FontWeight.Bold).fontColor(item.tint).width('100%')
                .height(26).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding(4).borderRadius(6).backgroundColor(item.fill)
                .onClick(() => { if (interactive) { this.activateCoursework(day, item, CalendarMode.week); } })
            }, (item: CalendarAllDayItem) => item.id + AppTheme.colorKey())
            if (MobileCalendarTimelineLayout.expandedHiddenAllDayEventCount(this.allDayItemsOn(day).length) > 0) {
              Text('+' + MobileCalendarTimelineLayout.expandedHiddenAllDayEventCount(this.allDayItemsOn(day).length).toString())
                .fontSize(CalendarTypography.fontSize(9.5, this.isPc)).fontColor(AppTheme.secondaryText()).width('100%').height(26)
                .textAlign(TextAlign.Center).borderRadius(6).backgroundColor(AppTheme.surfaceVariant())
                .onClick(() => { if (interactive) { this.presentAllDayDialog(day, CalendarMode.week); } })
            }
          }.layoutWeight(1).constraintSize({ minHeight: 40 }).padding(2)
        }, (day: DateParts) => 'week-all-day.' + StrictDates.formatDateParts(day))
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%').constraintSize({ maxHeight: 82, minHeight: 40 })
      .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off).backgroundColor(AppTheme.surface())
      .edgeEffect(EdgeEffect.Fade, { alwaysEnabled: true })
  }

  private weekAllDayLabel(day: DateParts): string {
    const items: CalendarAllDayItem[] = this.allDayItemsOn(day);
    if (items.length === 0) {
      return '';
    }
    return items.length > 1 ? items[0].title + ' +' + (items.length - 1).toString() : items[0].title;
  }

  private allDayItemsOn(day: DateParts): CalendarAllDayItem[] {
    const result: CalendarAllDayItem[] = [];
    for (const course of this.coursesOn(day)) {
      if (course.eventKind === 'exam' && !ScheduleLogic.hasTime(course)) {
        result.push(new CalendarAllDayItem(course.id,
          this.model.text('考试') + ' · ' + course.name + ' · ' + this.model.text('时间待定'),
          AppTheme.accent(), AppTheme.selection(), -1));
      }
    }
    for (const item of this.holidayItemsOn(day)) {
      result.push(new CalendarAllDayItem('holiday-' + item.id(),
        this.model.text(item.type === 'holiday' ? '休' : '班') + ' ' + item.name,
        item.type === 'holiday' ? AppTheme.holiday() : AppTheme.selectionText(), AppTheme.selection(),
        TeachingCalendarLogic.timelineAgendaSortOrder(item.type)));
    }
    for (const item of this.dayDataOn(day).assignments) {
      const coursework: CalendarCourseworkItem = CalendarCourseworkProjection.cloud(item, this.model.cloudCourses);
      result.push(new CalendarAllDayItem('assignment-' + item.id,
        this.model.text('作业') + ' · ' + item.title,
        AppTheme.assignment(), AppTheme.assignmentSurface(),
        TeachingCalendarLogic.timelineAgendaSortOrder('assignment'), null, coursework));
    }
    if (this.model.qmplusEnabled && !this.model.isSampleMode()) {
      for (const item of CalendarCourseworkProjection.qm(StrictDates.formatDateParts(day), this.qmPlusSession.snapshot)) {
        result.push(new CalendarAllDayItem(item.key, this.model.text(item.kind === 'quiz' ? '测验' : '作业') + ' · ' + item.title,
          AppTheme.assignment(), AppTheme.assignmentSurface(), TeachingCalendarLogic.timelineAgendaSortOrder('assignment'), null, item));
      }
    }
    for (const item of this.dayDataOn(day).deadlines) {
        const title: string = item.source === PublicDeadlineSource.schoolNotice ?
          this.model.text('校内') + ' · ' + item.name :
          this.model.text(PublicDeadlineKindInfo.title(item.kind)) + ' · ' + item.name;
        const event: CalendarAllDayItem = new CalendarAllDayItem('deadline-' + item.id, title,
          DeadlineVisual.colorForItem(item), DeadlineVisual.surfaceForItem(item),
          TeachingCalendarLogic.timelineAgendaSortOrder(
            item.source === PublicDeadlineSource.schoolNotice ? 'school_notice' : 'public_deadline'),
          item);
        result.push(event);
    }
    result.sort((lhs: CalendarAllDayItem, rhs: CalendarAllDayItem): number =>
      lhs.sortOrder - rhs.sortOrder);
    return result;
  }

  private allDayEntries(renderMode: CalendarMode, renderDate: DateParts): CalendarAllDayItem[] {
    const days: DateParts[] = renderMode === CalendarMode.week ?
      this.weekDates(renderDate) : [renderDate];
    const result: CalendarAllDayItem[] = [];
    for (const day of days) {
      for (const item of this.allDayItemsOn(day)) {
        result.push(item);
      }
    }
    return result;
  }

  private activateCoursework(day: DateParts, item: CalendarAllDayItem, mode: CalendarMode): void {
    if (item.coursework !== null && item.coursework.courseID !== null) {
      if (this.onOpenCourse(item.coursework.source, item.coursework.courseID)) { this.allDayDialogDay = null; return; }
    }
    this.presentAllDayDialog(day, mode);
  }

  // ---------- 月视图 ----------

  private renderedMonthSheetPosition(interactive: boolean): number {
    return interactive ? this.monthSheetPosition : this.incomingMonthSheetPosition;
  }

  private renderedMonthDate(renderDate: DateParts, interactive: boolean): DateParts {
    // 稳定月份 key 后，Builder 按值捕获的 renderDate 可能还是上一次点选日期。
    // current 必须直接读取响应式 session；incoming 保持转场目标的固定日期。
    return interactive ? this.selectedDate() : renderDate;
  }

  @Builder
  monthView(renderDate: DateParts, interactive: boolean) {
    Column({ space: 0 }) {
      Column({ space: 0 }) {
        this.statusArea(false, CalendarMode.month, renderDate)
        this.monthWeekdayHeader()
      }
      .width('100%')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        if (interactive && this.monthPageIdentity(renderDate) === this.monthPageIdentity(this.selectedDate())) {
          this.monthHeaderHeight = Number(newArea.height);
        } else if (!interactive && this.monthPageIdentity(renderDate) === this.monthPageIdentity(this.incomingDate)) {
          this.incomingMonthHeaderHeight = Number(newArea.height);
        }
      })
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 0 }) {
          ForEach(this.monthWeeks(renderDate), (week: DateParts[], rowIndex: number) => {
            Row({ space: 2 }) {
              ForEach(week, (day: DateParts) => {
                this.monthDayButton(day, rowIndex, renderDate, interactive)
              }, (day: DateParts) => 'month-day.' + StrictDates.formatDateParts(day))
            }
            .width('100%')
            .height(this.monthGridRowHeight(renderDate,
              this.renderedMonthSheetPosition(interactive), interactive))
          }, (week: DateParts[], rowIndex: number) => 'month-week.' + rowIndex.toString() + '.' +
            StrictDates.formatDateParts(week[0]))
        }
        .width('100%')
        .height(this.monthGridContentHeight(renderDate,
          this.renderedMonthSheetPosition(interactive), interactive))
        .translate({ y: this.monthGridTranslationY(this.renderedMonthDate(renderDate, interactive),
          this.renderedMonthSheetPosition(interactive), interactive) })
        .id('calendar.mobile.month-grid.' + this.monthPageIdentity(renderDate))
      }
      .width('100%')
      .height(this.monthGridViewportHeight(renderDate,
        this.renderedMonthSheetPosition(interactive), interactive))
      .clip(true)
      .id('calendar.mobile.month-grid-viewport.' + this.monthPageIdentity(renderDate))

      this.monthExpansionHandle(interactive)
      List({ space: 0, scroller: interactive ?
        this.monthDetailsScroller : this.incomingMonthDetailsScroller }) {
          ListItem() {
            Column({ space: 10 }) {
              // 仅按日期重建使用 Builder 值参数的课程摘要；原生组件的 @Param
              // 可以原位更新，避免点选日期时销毁并重建整组每日信息卡片。
              ForEach([this.renderedMonthDate(renderDate, interactive)], (day: DateParts) => {
                Column({ space: 10 }) {
                  this.daySummaryCard(day)
                }
                .width('100%')
                .id('calendar.mobile.month-summary.' + StrictDates.formatDateParts(day))
              }, (day: DateParts) => 'month-summary.' + StrictDates.formatDateParts(day))
              CalendarDailyInfoCards({ day: this.renderedMonthDate(renderDate, interactive) })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: TeachingCalendarLogic.monthDetailsTopGap(
          this.renderedMonthSheetPosition(interactive), this.monthDetailsAvailableHeight(renderDate, interactive)) })
        .visibility(this.renderedMonthSheetPosition(interactive) > 0 ? Visibility.Visible : Visibility.None)
        .opacity(Math.min(this.renderedMonthSheetPosition(interactive), 1))
        .enableScrollInteraction(interactive && this.monthDetailsScrollEnabled)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Fade, { alwaysEnabled: true })
        .borderRadius(10)
        .backgroundColor(AppTheme.background())
        .clip(true)
        .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
    }
    .padding({ left: 0, right: 0, top: 8, bottom: 0 })
    .width('100%')
    .height(this.monthUsableHeight())
    .clip(true)
    .id('calendar.mobile.month-page.' + this.monthPageIdentity(renderDate))
    // 与 iOS simultaneousGesture 一致：页面手势与详情 List 并行识别，
    // 然后由上方的轴锁定/顶部快照决定归属。排他手势会导致 List
    // 抢走横向事件，从而出现“左右滑动却不翻月”。
    .parallelGesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 18 })
        .onActionStart(() => {
          if (interactive) {
            this.beginMonthGesture();
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (interactive) {
            this.updateMonthGesture(event.offsetX, event.offsetY);
          }
        })
        .onActionEnd((event: GestureEvent) => {
          if (interactive) {
            this.finishMonthGesture(event.offsetX, event.offsetY, event.velocityX, event.velocityY);
          }
        })
        .onActionCancel(() => {
          if (interactive && this.monthDragging) {
            this.settleMonthSheet(Math.round(this.monthDragStartPosition));
          }
          this.resetMonthGestureRouting();
        })
    )
  }

  private monthWeeks(renderDate: DateParts): DateParts[][] {
    const dates: DateParts[] = this.monthGridDates(new DateParts(
      renderDate.year, renderDate.month, 1));
    const weeks: DateParts[][] = [];
    for (let row: number = 0; row < 6; row++) {
      weeks.push(dates.slice(row * 7, row * 7 + 7));
    }
    return weeks;
  }

  private selectedMonthWeekIndex(renderDate: DateParts = this.selectedDate()): number {
    return TeachingCalendarLogic.monthWeekIndex(renderDate);
  }

  @Builder
  monthWeekdayHeader() {
    Row({ space: 4 }) {
      ForEach(CalendarFormatters.weekdayLabels, (label: string) => {
        Text(this.model.text(label))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.secondaryText())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(18)
      }, (label: string) => 'month-weekday.' + label)
    }
    .width('100%')
    .padding({ bottom: 8 })
  }

  private monthNavigationInset(): number {
    return TeachingCalendarLogic.monthNavigationBottomInset(this.contentGlobalTop,
      this.contentHeight, this.phoneNavigationGlobalTop, this.phoneNavigationGlobalBottom,
      this.hasPhoneNavigation, PhoneNavigationLayout.navigationHeightVp +
      PhoneNavigationLayout.minimumBottomClearanceVp + TeachingCalendarLogic.monthNavigationGap);
  }

  private monthUsableHeight(): number {
    return Math.max(this.contentHeight - this.monthNavigationInset(), 0);
  }

  private expandedMonthCellHeight(interactive: boolean = true): number {
    return TeachingCalendarLogic.measuredExpandedMonthCellHeight(this.contentHeight,
      this.monthNavigationInset(), interactive ? this.monthHeaderHeight : this.incomingMonthHeaderHeight);
  }

  private monthDetailsAvailableHeight(renderDate: DateParts, interactive: boolean): number {
    return Math.max(this.monthUsableHeight() - 8 -
      (interactive ? this.monthHeaderHeight : this.incomingMonthHeaderHeight) - 28 -
      this.monthGridViewportHeight(renderDate, this.renderedMonthSheetPosition(interactive), interactive), 0);
  }

  private monthRowHeight(rowIndex: number, renderDate: DateParts = this.selectedDate(),
    sheetPosition: number = this.monthSheetPosition, interactive: boolean = true): number {
    // 当前六行始终同高；monthRowHeight 不使用选中周，平移时才需要计算周索引。
    return TeachingCalendarLogic.monthRowHeight(sheetPosition, rowIndex,
      0, this.expandedMonthCellHeight(interactive));
  }

  private monthGridRowHeight(renderDate: DateParts,
    sheetPosition: number = this.monthSheetPosition, interactive: boolean = true): number {
    return this.monthRowHeight(0, renderDate, sheetPosition, interactive);
  }

  private monthGridViewportHeight(renderDate: DateParts,
    sheetPosition: number = this.monthSheetPosition, interactive: boolean = true): number {
    return TeachingCalendarLogic.monthGridViewportHeight(sheetPosition, 6,
      this.monthGridRowHeight(renderDate, sheetPosition, interactive));
  }

  private monthGridContentHeight(renderDate: DateParts,
    sheetPosition: number = this.monthSheetPosition, interactive: boolean = true): number {
    return TeachingCalendarLogic.monthGridContentHeight(6,
      this.monthGridRowHeight(renderDate, sheetPosition, interactive));
  }

  private monthGridTranslationY(renderDate: DateParts,
    sheetPosition: number = this.monthSheetPosition, interactive: boolean = true): number {
    return TeachingCalendarLogic.monthGridTranslationY(sheetPosition,
      this.selectedMonthWeekIndex(renderDate),
      this.monthGridRowHeight(renderDate, sheetPosition, interactive));
  }

  private monthExpansionProgress(sheetPosition: number = this.monthSheetPosition): number {
    return TeachingCalendarLogic.monthCellExpansionProgress(sheetPosition);
  }

  @Builder
  monthDayButton(day: DateParts, rowIndex: number, renderDate: DateParts,
    interactive: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 0 }) {
        Row({ space: 3 }) {
          Text(day.day.toString())
            .fontSize(15)
            .fontWeight(day.equals(this.renderedMonthDate(renderDate, interactive)) ?
              FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.monthForeground(day, this.renderedMonthDate(renderDate, interactive)))
          if (TeachingCalendarLogic.showsTodayMarker(day.equals(StrictDates.todayParts()))) {
            Column()
              .width(5)
              .height(5)
              .borderRadius(2.5)
              .backgroundColor(AppTheme.nowIndicator())
          }
        }
        .width('100%')
        .height(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        if (this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive)) > 0.01) {
          this.expandedMonthEvents(day, renderDate, interactive)
        }
        if (this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive)) < 0.99) {
          Text(this.compactMonthMarker(day))
            .fontSize(CalendarTypography.fontSize(9.5, this.isPc))
            .fontColor(this.monthForeground(day, this.renderedMonthDate(renderDate, interactive)))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(TeachingCalendarLogic.interpolateMonthMetric(12, 0,
              this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive))))
            .opacity(1 - this.monthExpansionProgress(
              this.renderedMonthSheetPosition(interactive)))
        }
      }
      .padding({
        left: TeachingCalendarLogic.interpolateMonthMetric(4, 3,
          this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive))),
        right: TeachingCalendarLogic.interpolateMonthMetric(4, 3,
          this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive))),
        top: 5,
        bottom: TeachingCalendarLogic.interpolateMonthMetric(5, 2,
          this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive)))
      })
      .width('100%')
      .height('100%')
      .justifyContent(this.monthExpansionProgress(
        this.renderedMonthSheetPosition(interactive)) > 0.01 ?
        FlexAlign.Start : FlexAlign.Center)
      this.deadlineBorderLayers(day, 10, 7, 6,
        day.equals(this.renderedMonthDate(renderDate, interactive)))
    }
    .layoutWeight(1)
    .height(this.monthRowHeight(rowIndex, renderDate,
      this.renderedMonthSheetPosition(interactive), interactive))
    .backgroundColor(this.monthBackground(day, this.renderedMonthDate(renderDate, interactive)))
    .borderRadius(10)
    .clip(true)
    .onClick(() => {
      if (!interactive) {
        return;
      }
      const target: number = TeachingCalendarLogic.monthDaySelectionTargetPosition();
      if (!day.equals(this.renderedMonthDate(renderDate, interactive)) ||
        Math.round(this.monthSheetPosition) !== target) {
        this.performCalendarHaptic();
      }
      const selected: DateParts = this.selectedDate();
      if (day.year !== selected.year || day.month !== selected.month) {
        const direction: number = StrictDates.epochDay(day.year, day.month, day.day) >
          StrictDates.epochDay(selected.year, selected.month, selected.day) ? 1 : -1;
        // incoming 直接以目标中档挂载；纵向收拢只影响 outgoing，
        // 避免横向换月时新页格子跟着共享的纵向动画二次收缩。
        this.animatePageChange(direction, day, CalendarMode.month, false, target);
        this.settleMonthSheet(target, false);
        return;
      }
      this.setSelectedDate(day);
      this.settleMonthSheet(target, false);
      this.resetMonthDetailsScroll();
    })
  }

  private compactMonthMarker(day: DateParts): string {
    let result: string = '';
    const holiday: HolidayItem | null = this.firstHoliday(day);
    if (holiday !== null) {
      result += holiday.type === 'holiday' ? '休' : '班';
    }
    if (holiday !== null && this.coursesOn(day).length > 0) {
      result += '  ';
    }
    for (let index: number = 0; index < Math.min(this.coursesOn(day).length, 3); index++) {
      result += '•';
    }
    return result;
  }

  private monthEventCapacity(day: DateParts, renderDate: DateParts,
    interactive: boolean): number {
    const sheetPosition: number = this.renderedMonthSheetPosition(interactive);
    const height: number = this.monthRowHeight(0, renderDate, sheetPosition, interactive);
    const available: number = TeachingCalendarLogic.monthEntryAvailableHeight(
      height, this.monthExpansionProgress(sheetPosition));
    return TeachingCalendarLogic.monthEntrySlotCapacity(available);
  }

  private visibleMonthEventCount(day: DateParts, renderDate: DateParts,
    interactive: boolean): number {
    return TeachingCalendarLogic.visibleMonthEntryCount(
      this.monthEvents(day).length, this.monthEventCapacity(day, renderDate, interactive));
  }

  private hiddenMonthEventCount(day: DateParts, renderDate: DateParts,
    interactive: boolean): number {
    return TeachingCalendarLogic.hiddenMonthEntryCount(
      this.monthEvents(day).length, this.monthEventCapacity(day, renderDate, interactive));
  }

  @Builder
  expandedMonthEvents(day: DateParts, renderDate: DateParts, interactive: boolean) {
    Column({ space: 1 }) {
      ForEach(this.monthEvents(day).slice(0,
        this.visibleMonthEventCount(day, renderDate, interactive)),
        (event: MonthEvent) => {
          this.monthEventItem(event, day, renderDate, interactive)
        }, (event: MonthEvent) => 'month-event.' + event.id + '.' + event.title + AppTheme.colorKey())
      if (this.hiddenMonthEventCount(day, renderDate, interactive) > 0) {
        Text('+' + this.hiddenMonthEventCount(day, renderDate, interactive).toString())
          .fontSize(CalendarTypography.fontSize(9.5, this.isPc))
          .fontWeight(FontWeight.Medium)
          .fontColor(day.equals(this.renderedMonthDate(renderDate, interactive)) ?
            AppTheme.onPrimary() : AppTheme.text())
          .width('100%')
          .height(14)
          .padding({ left: 3, right: 3 })
          .textAlign(TextAlign.Start)
          .borderRadius(4)
          .backgroundColor(day.equals(this.renderedMonthDate(renderDate, interactive)) ?
            AppTheme.selectedDateStrong() : AppTheme.selection())
        }
      }
    .width('100%')
    .height(TeachingCalendarLogic.monthEntryAvailableHeight(
      this.monthRowHeight(0, renderDate,
        this.renderedMonthSheetPosition(interactive), interactive),
      this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive))))
    .alignItems(HorizontalAlign.Start)
    .opacity(this.monthExpansionProgress(this.renderedMonthSheetPosition(interactive)))
  }

  @Builder
  monthEventItem(event: MonthEvent, day: DateParts, renderDate: DateParts, interactive: boolean) {
    Text(event.title)
      .fontSize(CalendarTypography.fontSize(9.5, this.isPc))
      .fontWeight(FontWeight.Medium)
      .fontColor(day.equals(this.renderedMonthDate(renderDate, interactive)) ?
        AppTheme.onPrimary() : (event.id.startsWith('course-') ?
          AppTheme.textOnSelectionBlend(Math.min(0.08 + this.markerCount(day) * 0.08, 0.36), this.isDarkMode) : event.tint))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 3, right: 3 })
      .width('100%')
      .height(14)
      .textAlign(TextAlign.Start)
      .backgroundColor(day.equals(this.renderedMonthDate(renderDate, interactive)) ?
        AppTheme.selectedDateStrong() : event.fill)
      .borderRadius(4)
  }

  private monthEvents(day: DateParts): MonthEvent[] {
    const data: CalendarDayData = this.dayDataOn(day);
    if (data.monthEvents !== null) {
      return data.monthEvents as MonthEvent[];
    }
    const result: MonthEvent[] = [];
    for (const item of data.holidays) {
      result.push(new MonthEvent(
        'holiday-' + item.id(), this.model.text(item.type === 'holiday' ? '休' : '班') +
          ' ' + item.name,
        item.type === 'holiday', item.type === 'workday',
        item.type === 'holiday' ? AppTheme.holiday() : AppTheme.selectionText(), AppTheme.selection()));
    }
    for (const course of data.courses) {
      result.push(new MonthEvent('course-' + course.id, course.name, false, false,
        AppTheme.selectionText(), AppTheme.selection()));
    }
    for (const item of data.assignments) {
      result.push(new MonthEvent('assignment-' + item.id,
        this.model.text('作业') + ' ' + item.title, false, false,
        AppTheme.assignment(), AppTheme.assignmentSurface()));
    }
    for (const item of data.deadlines) {
          const school: boolean = item.source === PublicDeadlineSource.schoolNotice;
          result.push(new MonthEvent('deadline-' + item.id,
            (school ? this.model.text('校内') :
              this.model.text(PublicDeadlineKindInfo.title(item.kind))) + ' ' + item.name,
            false, false,
          DeadlineVisual.colorForItem(item), DeadlineVisual.surfaceForItem(item)));
    }
    data.monthEvents = result;
    return result;
  }

  @Builder
  monthExpansionHandle(interactive: boolean) {
    Column() {
      Row({ space: 0 }) {
        Column()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(AppTheme.secondaryText())
          .rotate({ angle: -24 * this.monthExpansionProgress(
            this.renderedMonthSheetPosition(interactive)),
            centerX: '100%', centerY: '50%' })
        Column()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(AppTheme.secondaryText())
          .rotate({ angle: 24 * this.monthExpansionProgress(
            this.renderedMonthSheetPosition(interactive)),
            centerX: '0%', centerY: '50%' })
      }
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
    .id('calendar.mobile.month-handle.' + Math.round(
      this.renderedMonthSheetPosition(interactive)).toString())
    .onClick(() => {
      if (!interactive) {
        return;
      }
      const rounded: number = Math.round(this.renderedMonthSheetPosition(interactive));
      const target: number = TeachingCalendarLogic.monthHandleTargetPosition(rounded);
      this.settleMonthSheet(target);
    })
  }

  private monthForeground(day: DateParts, renderDate: DateParts): ResourceColor {
    if (day.equals(renderDate)) {
      return AppTheme.onPrimary();
    }
    if (day.month !== renderDate.month) {
      return AppTheme.textOnPrimaryBlend(Math.min(0.08 + this.markerCount(day) * 0.08, 0.36), this.isDarkMode, true);
    }
    const holiday: HolidayItem | null = this.firstHoliday(day);
    if (holiday === null) {
      return AppTheme.textOnPrimaryBlend(Math.min(0.08 + this.markerCount(day) * 0.08, 0.36), this.isDarkMode);
    }
    return holiday.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary();
  }

  private monthBackground(day: DateParts, renderDate: DateParts): ResourceColor {
    if (day.equals(renderDate)) {
      return AppTheme.selectedDate();
    }
    const count: number = this.markerCount(day);
    if (count <= 0) {
      return Color.Transparent;
    }
    const alpha: number = Math.min(0.08 + count * 0.08, 0.36);
    return CalendarColors.primaryWithAlpha(alpha, this.isDarkMode);
  }

  private markerCount(day: DateParts): number {
    const data: CalendarDayData = this.dayDataOn(day);
    return data.courses.length + data.assignments.length + data.deadlines.length;
  }

  // ---------- 年视图 ----------

  @Builder
  yearView(renderDate: DateParts, interactive: boolean) {
    Scroll() {
      Column({ space: 12 }) {
        this.statusArea(false, CalendarMode.year, renderDate)
        Text(this.model.text('颜色越深表示当天日程越多'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
        Grid() {
          ForEach(this.monthsOfYear(), (month: number) => {
            GridItem() {
              this.miniMonth(month, renderDate, interactive)
            }
          }, (month: number) => 'mini-month.' + month.toString())
        }
        .columnsTemplate('repeat(' + this.yearColumnCount().toString() + ', 1fr)')
        .columnsGap(16)
        .rowsGap(18)
        .width('100%')
      }
      .padding({
        left: 16,
        right: 16,
        top: 16,
        bottom: PhoneNavigationLayout.minimumContentBottomInsetVp
      })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }

  private yearColumnCount(): number {
    return this.contentWidth >= 700 ? 3 : 2;
  }

  private monthsOfYear(): number[] {
    const result: number[] = [];
    for (let month = 1; month <= 12; month++) {
      result.push(month);
    }
    return result;
  }

  @Builder
  miniMonth(month: number, renderDate: DateParts, interactive: boolean) {
    Column({ space: 0 }) {
      Text(CalendarFormatters.monthLabel(month, this.model.resolvedLanguage()))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .width('100%')
        .height(28)
        .textAlign(TextAlign.Start)
        .onClick(() => {
          if (interactive) {
            const targetDate: DateParts = new DateParts(renderDate.year, month, 1);
            const direction: number = TeachingCalendarLogic.modeTransitionDirection(
              CalendarMode.year, CalendarMode.month);
            this.animatePageChange(direction, targetDate, CalendarMode.month);
          }
        })
      Row({ space: 1 }) {
        ForEach(CalendarFormatters.weekdayLabels, (label: string) => {
          Text(this.model.text(label))
            .fontSize(CalendarTypography.fontSize(8, this.isPc))
            .fontColor(AppTheme.secondaryText())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
        }, (label: string) => 'year-weekday.' + month.toString() + '.' + label)
      }
      .width('100%')
      .height(14)

      Grid() {
        ForEach(this.monthGridDates(new DateParts(renderDate.year, month, 1)),
          (day: DateParts) => {
            GridItem() {
              this.yearDayButton(day, month, interactive)
            }
          }, (day: DateParts) => 'year-day.' + StrictDates.formatDateParts(day))
      }
      .columnsTemplate('repeat(7, 1fr)')
      .columnsGap(2)
      .rowsGap(2)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  yearDayButton(day: DateParts, month: number, interactive: boolean) {
    if (day.month === month) {
      Stack({ alignContent: Alignment.Center }) {
        Row({ space: 2 }) {
          Text(day.day.toString())
            .fontSize(CalendarTypography.fontSize(8, this.isPc))
            .fontColor(day.equals(this.selectedDate()) ?
              AppTheme.onPrimary() : AppTheme.textOnPrimaryBlend(
                TeachingCalendarLogic.yearCourseOpacity(this.markerCount(day)), this.isDarkMode))
          if (TeachingCalendarLogic.showsTodayMarker(day.equals(StrictDates.todayParts()))) {
            Column()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(AppTheme.nowIndicator())
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        this.deadlineBorderLayers(day, 4, 2, 4, day.equals(this.selectedDate()))
      }
      .width('100%')
      .height(26)
      .borderRadius(4)
      .backgroundColor(day.equals(this.selectedDate()) ?
        AppTheme.selectedDate() : CalendarColors.primaryWithAlpha(
          TeachingCalendarLogic.yearCourseOpacity(this.markerCount(day)), this.isDarkMode))
      .clip(true)
      .onClick((event: ClickEvent) => {
        if (!interactive) {
          return;
        }
        this.performCalendarHaptic();
        this.showYearDay(day, event);
      })
    } else {
      Column()
        .width('100%')
        .height(26)
    }
  }

  private showYearDay(day: DateParts, event: ClickEvent): void {
    const revision: number = ++this.presentedDayLoadRevision;
    const motionGeneration: number = ++this.presentedDayMotionGeneration;
    if (this.presentedDayLoadTimer >= 0) {
      clearTimeout(this.presentedDayLoadTimer);
    }
    if (this.presentedDayMountTimer >= 0) {
      clearTimeout(this.presentedDayMountTimer);
    }
    this.presentedDayAnchorX = Number(event.target.area.globalPosition.x) - this.rootGlobalX +
      Number(event.target.area.width) / 2;
    this.presentedDayAnchorY = Number(event.target.area.globalPosition.y) - this.rootGlobalY +
      Number(event.target.area.height) / 2;
    this.setSelectedDate(day);
    this.presentedDayOpacity = 0;
    this.presentedDay = day;
    // 新节点先挂载一帧再启动数值动画，确保首次点击也有进入帧。
    this.presentedDayMountTimer = setTimeout(() => {
      this.presentedDayMountTimer = -1;
      if (motionGeneration !== this.presentedDayMotionGeneration) {
        return;
      }
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
        this.presentedDayOpacity = 1;
      });
    }, 16);
    // 首帧和开窗过渡先完成；远端请求不参与开窗动画。
    this.presentedDayLoadTimer = setTimeout(() => {
      this.presentedDayLoadTimer = -1;
      if (revision === this.presentedDayLoadRevision && this.presentedDay?.equals(day)) {
        this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(day));
      }
    }, 180);
  }

  private dismissYearDay(): void {
    if (this.presentedDay === null) {
      return;
    }
    const motionGeneration: number = ++this.presentedDayMotionGeneration;
    this.presentedDayLoadRevision++;
    if (this.presentedDayLoadTimer >= 0) {
      clearTimeout(this.presentedDayLoadTimer);
      this.presentedDayLoadTimer = -1;
    }
    if (this.presentedDayMountTimer >= 0) {
      clearTimeout(this.presentedDayMountTimer);
      this.presentedDayMountTimer = -1;
    }
    this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (motionGeneration === this.presentedDayMotionGeneration) {
          this.presentedDay = null;
        }
      }
    }, (): void => {
      this.presentedDayOpacity = 0;
    });
  }

  private yearDeadlineKinds(day: DateParts): DeadlineVisualKind[] {
    const data: CalendarDayData = this.dayDataOn(day);
    return DeadlineVisual.borderKinds(data.assignments.length, data.deadlines);
  }

  @Builder
  deadlineBorderLayers(day: DateParts, outerRadius: number, innerRadius: number,
    innerInset: number, selected: boolean) {
    if (AppTheme.shouldOutlineSelectedDate(selected, this.yearDeadlineKinds(day).length > 0)) {
      Column()
        .width('100%')
        .height('100%')
        .border({ width: 1.5, color: AppTheme.selectedDateOutline() })
        .borderRadius(outerRadius)
        .hitTestBehavior(HitTestMode.None)
    }
    ForEach(this.yearDeadlineKinds(day),
      (kind: DeadlineVisualKind, index: number) => {
      Column()
        .width(index === 0 ? '100%' : this.deadlineInnerSize(innerInset))
        .height(index === 0 ? '100%' : this.deadlineInnerSize(innerInset))
        .border({
          width: index === 0 ? 1.5 : 1,
          color: DeadlineVisual.color(kind)
        })
        .borderRadius(index === 0 ? outerRadius : innerRadius)
        .hitTestBehavior(HitTestMode.None)
      }, (kind: DeadlineVisualKind, index: number) => kind + '.' + index.toString())
  }

  private deadlineInnerSize(innerInset: number): string {
    return 'calc(100% - ' + innerInset.toString() + 'vp)';
  }

  // ---------- 日/周全天日程弹窗 ----------

  private presentAllDayDialog(day: DateParts, mode: CalendarMode, load: boolean = true): void {
    this.momentDialogItems = [];
    if (!TeachingCalendarLogic.supportsAllDayDialog(mode)) {
      return;
    }
    if (TeachingCalendarLogic.agendaDialogChangesSelectedDate(mode)) {
      this.setSelectedDate(day);
    }
    if (load) { this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(day)); }
    this.allDayDialogModeRawValue = mode;
    this.allDayDialogDay = day;
  }

  private dialogItemsOn(day: DateParts): CalendarAllDayItem[] {
    if (this.momentDialogItems.length === 0) { return this.allDayItemsOn(day); }
    return this.momentDialogItems.map((item: CalendarCourseworkItem): CalendarAllDayItem =>
      new CalendarAllDayItem(item.key, item.title + ' · ' + item.deadline.substring(11, 16),
        AppTheme.assignment(), AppTheme.assignmentSurface(),
        TeachingCalendarLogic.timelineAgendaSortOrder('assignment'), null, item));
  }

  @Builder
  weekAllDayDialogOverlay() {
    this.centeredAllDayDialog(CalendarModeInfo.fromRawValue(this.allDayDialogModeRawValue))
  }

  @Builder
  centeredAllDayDialog(mode: CalendarMode) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.allDayDialogDay = null;
        })
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(TeachingCalendarLogic.allDayDialogTitle(mode, this.model.resolvedLanguage()))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
            Text(CalendarFormatters.fullDate(this.allDayDialogDay as DateParts, this.model.resolvedLanguage()))
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(this.model.text('完成'))
            .fontSize(14)
            .fontColor(AppTheme.primary())
            .onClick(() => {
              this.allDayDialogDay = null;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.dialogItemsOn(this.allDayDialogDay as DateParts),
              (item: CalendarAllDayItem) => {
                Row({ space: 6 }) {
                  Text(item.title)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(item.tint)
                    .layoutWeight(1)
                  if (item.deadlineItem !== null) {
                    Button() {
                      SymbolGlyph(this.model.isFavoriteDeadline(item.deadlineItem as PublicDeadlineItem) ?
                        $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
                        .fontSize(18)
                        .fontColor([this.model.isFavoriteDeadline(item.deadlineItem as PublicDeadlineItem) ?
                          AppTheme.assignment() : AppTheme.secondaryText()])
                    }
                    .type(ButtonType.Normal)
                    .width(34)
                    .height(34)
                    .backgroundColor(Color.Transparent)
                    .accessibilityText(this.model.text(
                      this.model.isFavoriteDeadline(item.deadlineItem as PublicDeadlineItem) ?
                        '取消收藏' : '收藏'))
                    .onClick(() => {
                      const ownerGeneration: number = this.presentedDayMotionGeneration;
                      const uiContext = this.getUIContext();
                      const showFeedback = (message: string): void => {
                        if (ownerGeneration !== this.presentedDayMotionGeneration || this.presentedDay === null) {
                          return;
                        }
                        try {
                          uiContext.getPromptAction().showToast({ message: this.model.text(message) });
                        } catch (e) {
                          // 年视图弹层关闭后不让旧 UI 回调覆盖模型中的准确失败原因。
                        }
                      };
                      this.model.toggleFavoriteDeadline(item.deadlineItem as PublicDeadlineItem)
                        .then((changed: boolean): void => {
                          if (!changed) {
                            showFeedback(AppModel.favoriteDeadlineLimitMessage);
                          }
                        }, (): void => {
                          this.model.statusMessage = '无法保存收藏';
                          showFeedback('无法保存收藏');
                        });
                    })
                  }
                }
                .width('100%')
                .padding({ left: 10, right: 6, top: 5, bottom: 5 })
                .borderRadius(6)
                .backgroundColor(item.fill)
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  if (item.coursework !== null) { this.activateCoursework(this.allDayDialogDay as DateParts, item, mode); }
                })
              }, (item: CalendarAllDayItem) => 'all-day-dialog.' + mode + '.' + item.id + AppTheme.colorKey())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Fade, { alwaysEnabled: true })
        .constraintSize({ maxHeight: Math.max(this.rootHeight - 180, 160) })
        .width('100%')
      }
      .padding(16)
      .width(Math.min(360, Math.max(this.rootWidth - 32, 240)))
      .constraintSize({ maxHeight: Math.max(this.rootHeight - 48, 220) })
      .borderRadius(12)
      .border({ radius: 12, width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.elevated())
      .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 8 })
      .position({ x: '50%', y: '50%' })
      .translate({ x: '-50%', y: '-50%' })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  // ---------- 年视图详情卡片 ----------

  @Builder
  dayDetailOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.dismissYearDay();
        })
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text(CalendarFormatters.monthDayCompact(this.presentedDay as DateParts, this.model.resolvedLanguage()))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
            .layoutWeight(1)
          Text(this.model.text('完成'))
            .fontSize(14)
            .fontColor(AppTheme.primary())
            .onClick(() => {
              this.dismissYearDay();
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: 10 }) {
            this.daySummaryCard(this.presentedDay as DateParts, false)
            CalendarDailyInfoCards({ day: this.presentedDay as DateParts })
            Text(this.model.text('跳转到'))
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
              .width('100%')
            this.yearNavigationCommands(this.presentedDay as DateParts)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Fade, { alwaysEnabled: true })
        .layoutWeight(1)
        .width('100%')
      }
      .padding(14)
      .width(this.dayDetailWidth())
      .height(this.dayDetailHeight(this.presentedDay as DateParts))
      .borderRadius(8)
      .border({ radius: 8, width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.elevated())
      .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Start)
      .position({
        x: this.dayDetailX(),
        y: this.dayDetailY(this.presentedDay as DateParts)
      })
    }
    .width('100%')
    .height('100%')
    .opacity(this.presentedDayOpacity)
  }

  private dayDetailWidth(): number {
    return Math.min(300, Math.max(this.rootWidth - 32, 220));
  }

  private dayDetailHeight(day: DateParts): number {
    const contentHeight: number = 310 + this.holidayItemsOn(day).length * 28 +
      Math.max(this.coursesOn(day).length, 1) * 48;
    return Math.min(Math.max(contentHeight, 190), Math.max(this.rootHeight - 32, 190));
  }

  private dayDetailX(): number {
    const width: number = this.dayDetailWidth();
    return Math.min(Math.max(this.presentedDayAnchorX - width / 2, 16),
      Math.max(this.rootWidth - width - 16, 16));
  }

  private dayDetailY(day: DateParts): number {
    const height: number = this.dayDetailHeight(day);
    const below: number = this.presentedDayAnchorY + 10;
    if (below + height <= this.rootHeight - 16) {
      return below;
    }
    return Math.max(this.presentedDayAnchorY - height - 10, 16);
  }

  @Builder
  yearNavigationCommands(day: DateParts) {
    Row({ space: 8 }) {
      ForEach(CalendarModeInfo.all.slice(0, 3), (item: CalendarMode) => {
        Text(this.model.text(item + '视图'))
          .fontSize(13)
          .fontColor(AppTheme.text())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(32)
          .borderRadius(6)
          .border({ radius: 6, width: 1, color: AppTheme.border() })
          .backgroundColor(AppTheme.background())
          .onClick(() => {
            this.performCalendarHaptic();
            this.setSelectedDate(day);
            this.setMode(item);
            this.dismissYearDay();
          })
      }, (item: CalendarMode) => 'year-jump.' + item)
    }
    .width('100%')
  }

  @Builder
  daySummaryCard(day: DateParts, framed: boolean = true) {
    Column({ space: 10 }) {
      Text(CalendarFormatters.fullDate(day, this.model.resolvedLanguage()))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      ForEach(this.holidayItemsOn(day), (item: HolidayItem) => {
        Row({ space: 6 }) {
          SymbolGlyph(item.type === 'holiday' ? $r('sys.symbol.calendar_badge_clock') :
            $r('sys.symbol.briefcase'))
            .fontSize(14)
            .fontColor([item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary()])
          Text(item.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary())
        }
        .width('100%')
      }, (item: HolidayItem) => 'summary-holiday.' + item.id())

      if (this.coursesOn(day).length === 0) {
        Text(this.model.text('暂无课程'))
          .fontSize(14)
          .fontColor(AppTheme.secondaryText())
      } else {
        ForEach(this.coursesOn(day), (course: Course, index: number) => {
          Row({ space: 10 }) {
            Column()
              .width(4)
              .height(38)
              .borderRadius(2)
              .backgroundColor(AppTheme.primaryFill())
            Column({ space: 2 }) {
              Text(course.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.text())
              Text(this.courseSubtitle(course))
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            CourseRemovalButton({ course: course, date: day })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (course: Course, index: number) => 'summary-course.' + course.id + '.' + index.toString())
      }
    }
    .padding(framed ? 14 : 0)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(framed ? 10 : 0)
    .border({ radius: framed ? 10 : 0, width: framed ? 1 : 0, color: AppTheme.border() })
    .backgroundColor(framed ? AppTheme.surface() : Color.Transparent)
  }

  // ---------- 操作菜单 ----------

  @Builder
  actionsOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.showingActions = false;
        })
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(16)
            .fontColor([AppTheme.text()])
          Text(this.model.isRefreshingSchedule ? this.model.text('正在获取…') :
            this.model.text('获取/刷新个人课表'))
            .fontSize(14)
            .fontColor(AppTheme.text())
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppTheme.background())
        .borderRadius(8)
        .onClick(() => {
          this.showingActions = false;
          if (!this.model.isRefreshingSchedule && !this.model.isImportingCalendar) {
            this.model.refreshSchedule();
          }
        })

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.calendar_badge_plus'))
            .fontSize(16)
            .fontColor([AppTheme.text()])
          Text(this.model.isImportingCalendar ? this.model.text('正在导入…') :
            this.model.text('导入系统日历'))
            .fontSize(14)
            .fontColor(AppTheme.text())
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppTheme.background())
        .borderRadius(8)
        .onClick(() => {
          this.showingActions = false;
          if (this.model.schedule !== null && !this.model.isRefreshingSchedule &&
            !this.model.isImportingCalendar) {
            this.model.importScheduleToCalendar();
          }
        })

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(16)
            .fontColor([AppTheme.text()])
          Text(this.model.isImportingCalendar ? this.model.text('正在导入…') :
            this.model.text('导入已收藏日程'))
            .fontSize(14)
            .fontColor(AppTheme.text())
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppTheme.background())
        .borderRadius(8)
        .opacity(this.model.favoriteDeadlines.length > 0 && !this.model.isImportingCalendar ? 1 : 0.55)
        .onClick(() => {
          this.showingActions = false;
          if (this.model.favoriteDeadlines.length > 0 && !this.model.isImportingCalendar) {
            this.model.importFavoritesToCalendar();
          }
        })
      }
      .padding(8)
      .width(230)
      .borderRadius(10)
      .backgroundColor(AppTheme.elevated())
      .margin({ top: 44, right: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  private periodTitle(): string {
    const base: string = TeachingCalendarLogic.periodTitle(
      this.selectedDate(), this.mode(), this.model.resolvedLanguage());
    if (this.mode() !== CalendarMode.week) {
      return base;
    }
    const calendarWeek: number = StrictDates.isoWeekNumber(this.selectedDate());
    const teachingWeek: number | null = this.model.weekNumberOn(this.selectedDate());
    if (this.isEnglish()) {
      return base + ' · Calendar week ' + calendarWeek.toString() + ' · Teaching week ' +
        (teachingWeek === null ? '—' : teachingWeek.toString());
    }
    if (this.model.resolvedLanguage() !== AppLanguage.simplifiedChinese) {
      const language: AppLanguage = this.model.resolvedLanguage();
      return base + ' · ' + AppLocalization.format('公历第 {week} 周',
        new LocalizationValues('week', calendarWeek.toString()), language, language) + ' · ' +
        AppLocalization.format('第 {week} 教学周',
          new LocalizationValues('week', teachingWeek === null ? '—' : teachingWeek.toString()), language, language);
    }
    return base + ' · 公历第' + calendarWeek.toString() + '周 · 第' +
      (teachingWeek === null ? '—' : teachingWeek.toString()) + '教学周';
  }

  private shanghaiHour(): number {
    const shanghaiMs: number = (Date.now() + 8 * 3600 * 1000) % 86400000;
    return Math.floor(Math.floor(shanghaiMs / 60000) / 60);
  }

  private scrollTimelineToInitialHour(renderMode: CalendarMode, renderDate: DateParts,
    scroller: Scroller): void {
    const days: CalendarTimelineDay[] = this.timelineDays(renderMode, renderDate);
    const today: DateParts = StrictDates.todayParts();
    let includesToday: boolean = false;
    for (const day of days) {
      if (day.date.equals(today)) {
        includesToday = true;
        break;
      }
    }
    const hour: number = MobileCalendarTimelineLayout.initialVisibleHour(
      this.shanghaiHour(), includesToday);
    const restoreOffsetY: number | null = this.pendingTimelineRestoreOffsetY;
    this.pendingTimelineRestoreOffsetY = null;
    if (this.timelineScrollTimer >= 0) {
      clearTimeout(this.timelineScrollTimer);
    }
    this.timelineScrollTimer = setTimeout(() => {
      this.timelineScrollTimer = -1;
      scroller.scrollTo({
        xOffset: 0,
        yOffset: restoreOffsetY === null ?
          (hour - 8) * MobileCalendarTimelineLayout.hourHeight : restoreOffsetY
      });
    }, 150);
  }
}

class CalendarAllDayItem {
  readonly id: string;
  readonly title: string;
  readonly tint: ResourceColor;
  readonly fill: ResourceColor;
  readonly sortOrder: number;
  readonly deadlineItem: PublicDeadlineItem | null;
  readonly coursework: CalendarCourseworkItem | null;

  constructor(id: string, title: string, tint: ResourceColor, fill: ResourceColor,
    sortOrder: number, deadlineItem: PublicDeadlineItem | null = null, coursework: CalendarCourseworkItem | null = null) {
    this.id = id;
    this.title = title;
    this.tint = tint;
    this.fill = fill;
    this.sortOrder = sortOrder;
    this.deadlineItem = deadlineItem;
    this.coursework = coursework;
  }
}

// 主题主色的透明度变体（供月/年单元格背景使用；深浅色下均可用）。
class CalendarColors {
  static primaryWithAlpha(alpha: number, dark: boolean): string {
    return AppTheme.primaryWithAlpha(alpha, dark);
  }
}
