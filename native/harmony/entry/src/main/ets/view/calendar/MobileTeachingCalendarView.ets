// 移动端教学日历页，以原生 Android TeachingCalendarPage.kt 与
// YearCalendarView.kt 为基准。
// 日/周（时间线 + 日期条）、月（可展开网格 + 日程卡）、年（12 个月迷你网格 +
// 详情卡片）四种视图，支持左右滑动翻页与月视图上下滑动展开/收起。
import { AppModel } from '../../model/AppModel';
import { Course, HolidayItem } from '../../common/Models';
import { StrictDates, DateParts } from '../../common/StrictDates';
import { AppTheme } from '../../common/AppTheme';
import { PageTitle, SurfaceCard } from '../SharedComponents';
import {
  CalendarFormatters, CalendarMode, CalendarModeInfo, CalendarTimelineDay,
  CalendarTimelineLogic, CalendarYearDeadlinePriority, DarkModeProbe, TeachingCalendarLogic
} from './CalendarLogic';
import { TeachingCalendarSession } from './TeachingCalendarSession';
import { MobileCalendarTimelineLayout, MobileCalendarTimelineView } from './MobileCalendarTimelineView';
import { CalendarDailyInfoCards } from './CalendarDailyInfoCards';
import {
  PublicDeadlineKindInfo, PublicDeadlineSnapshot, PublicDeadlineSource
} from '../../net/CalendarDailyInfoClient';
import { vibrator } from '@kit.SensorServiceKit';
import { AppLanguage } from '../../common/AppLocalization';

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

@ComponentV2
export struct MobileTeachingCalendarView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: TeachingCalendarSession = new TeachingCalendarSession();
  @Local presentedDay: DateParts | null = null;
  @Local allDayDialogDay: DateParts | null = null;
  @Local allDayDialogModeRawValue: string = CalendarMode.week;
  @Local showingActions: boolean = false;
  @Local contentWidth: number = 350;
  @Local contentHeight: number = 500;
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
  @Local monthSheetPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local monthDragStartPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local monthDragging: boolean = false;
  @Local monthDetailsReady: boolean = true;
  @Local monthPageOpacity: number = 1;
  @Local courseSectionExpanded: boolean = true;
  private pageAnimating: boolean = false;
  private timelineScroller: Scroller = new Scroller();
  private incomingTimelineScroller: Scroller = new Scroller();
  private monthDetailsScroller: Scroller = new Scroller();
  private monthDetailsAtTopAtGestureStart: boolean = true;
  private monthDetailsReadyRevision: number = 0;
  private timelineScrollTimer: number = -1;

  aboutToAppear(): void {
    this.monthSheetPosition = this.session.isMonthExpanded ?
      TeachingCalendarLogic.monthSheetExpandedPosition :
      TeachingCalendarLogic.monthSheetDetailsPosition;
    this.ensureVisibleHolidays();
    this.ensureVisibleCalendarData();
    this.darkModeProbe.register((dark: boolean) => {
      this.isDarkMode = dark;
    });
  }

  aboutToDisappear(): void {
    this.darkModeProbe.unregister();
    // 清理延迟滚动定时器，避免对已销毁 Scroller 操作（BUG-012 修复）。
    if (this.timelineScrollTimer >= 0) {
      clearTimeout(this.timelineScrollTimer);
      this.timelineScrollTimer = -1;
    }
  }

  @Monitor('session.selectedDate')
  onSelectedDateChange(monitor: IMonitor): void {
    this.ensureVisibleHolidays();
    this.ensureVisibleCalendarData();
  }

  @Monitor('session.modeRawValue')
  onModeChange(monitor: IMonitor): void {
    this.ensureVisibleHolidays();
    this.ensureVisibleCalendarData();
  }

  @Monitor('model.almanacEnabled', 'model.competitionDeadlinesEnabled',
    'model.schoolContestNoticesEnabled', 'model.summerCampDeadlinesEnabled',
    'model.hackathonDeadlinesEnabled')
  onDailyInfoFeatureChange(monitor: IMonitor): void {
    this.ensureVisibleCalendarData();
  }

  private mode(): CalendarMode {
    return CalendarModeInfo.fromRawValue(this.session.modeRawValue);
  }

  private isEnglish(): boolean {
    return this.model.resolvedLanguage() === AppLanguage.english;
  }

  private selectedDate(): DateParts {
    return this.session.selectedDate;
  }

  private setSelectedDate(date: DateParts): void {
    this.session.selectedDate = date;
  }

  private setMode(mode: CalendarMode): void {
    this.session.modeRawValue = mode;
  }

  private animateMode(mode: CalendarMode): void {
    if (mode === this.mode()) {
      return;
    }
    const direction: number = TeachingCalendarLogic.modeTransitionDirection(this.mode(), mode);
    this.animatePageChange(direction, this.selectedDate(), mode);
  }

  private coursesOn(date: DateParts): Course[] {
    return this.model.coursesOn(date);
  }

  private holidayItemsOn(date: DateParts): HolidayItem[] {
    const target: string = StrictDates.formatDateParts(date);
    const result: HolidayItem[] = [];
    for (const item of this.model.holidayItems(date.year)) {
      if (item.date === target) {
        result.push(item);
      }
    }
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

  private ensureVisibleHolidays(): void {
    this.ensureHolidays(this.mode(), this.selectedDate());
  }

  private ensureVisibleCalendarData(): void {
    const selected: DateParts = this.selectedDate();
    if (this.mode() === CalendarMode.month) {
      this.model.prefetchCalendarMarkers(this.monthGridDates(selected));
      if (this.monthDetailsReady &&
        this.monthSheetPosition > TeachingCalendarLogic.monthSheetExpandedPosition + 0.01) {
        this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(selected));
      }
    } else if (this.mode() === CalendarMode.week) {
      this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(selected));
      this.model.prefetchCalendarMarkers(this.weekDates(selected));
    } else if (this.mode() === CalendarMode.day) {
      this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(selected));
      this.model.prefetchCalendarMarkers([selected]);
    } else {
      this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(selected));
      this.model.prefetchCalendarMarkers(this.yearDates(selected));
    }
  }

  private ensureHolidays(renderMode: CalendarMode, renderDate: DateParts): void {
    for (const year of this.visibleHolidayYears(renderMode, renderDate)) {
      this.model.ensureHolidays(year, false);
    }
  }

  private animateDate(direction: number): void {
    if (this.mode() === CalendarMode.month) {
      this.animateMonthChange(direction);
      return;
    }
    this.animatePageChange(direction, TeachingCalendarLogic.movedDate(
      this.selectedDate(), this.mode(), direction), this.mode());
  }

  private animateMonthChange(direction: number): void {
    if (direction === 0 || this.pageAnimating) {
      return;
    }
    this.performCalendarHaptic();
    this.pageAnimating = true;
    this.monthDetailsReady = false;
    const target: DateParts = TeachingCalendarLogic.movedDate(
      this.selectedDate(), CalendarMode.month, direction);
    animateTo({ duration: 110, curve: Curve.EaseOut }, (): void => {
      this.monthPageOpacity = 0.72;
    });
    setTimeout(() => {
      this.setSelectedDate(target);
      animateTo({ duration: 150, curve: Curve.EaseOut }, (): void => {
        this.monthPageOpacity = 1;
      });
      setTimeout(() => {
        this.pageAnimating = false;
        this.revealMonthDetailsAfter(0);
      }, 156);
    }, 116);
  }

  private animatePageChange(direction: number, targetDate: DateParts, targetMode: CalendarMode): void {
    if (direction === 0 || this.pageAnimating) {
      return;
    }
    this.performCalendarHaptic();
    this.pageAnimating = true;
    const distance: number = Math.max(this.contentWidth, 320);
    this.incomingDate = targetDate;
    this.incomingModeRawValue = targetMode;
    this.ensureHolidays(targetMode, targetDate);
    this.incomingPageOffsetX = direction * distance;
    this.pageTransitionActive = true;

    // 先挂载相邻页面，下一帧再让两页同时移动，避免旧实现中间出现空白帧。
    setTimeout(() => {
      animateTo({ duration: 300, curve: Curve.EaseInOut }, (): void => {
        this.pageOffsetX = -direction * distance;
        this.incomingPageOffsetX = 0;
      });
      setTimeout(() => {
        this.setSelectedDate(targetDate);
        this.setMode(targetMode);
        this.pageOffsetX = 0;
        this.incomingPageOffsetX = 0;
        this.pageTransitionActive = false;
        this.pageAnimating = false;
      }, 310);
    }, 16);
  }

  private navigateTo(date: DateParts): void {
    if (!date.equals(this.selectedDate())) {
      this.performCalendarHaptic();
    }
    if (this.mode() === CalendarMode.month &&
      this.monthSheetPosition > TeachingCalendarLogic.monthSheetExpandedPosition + 0.01) {
      this.monthDetailsReady = false;
      this.setSelectedDate(date);
      this.revealMonthDetailsAfter(130);
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
    this.monthDragStartPosition = this.monthSheetPosition;
    if (this.monthSheetPosition <= TeachingCalendarLogic.monthSheetExpandedPosition + 0.01 ||
      !this.monthDetailsReady) {
      this.monthDetailsAtTopAtGestureStart = true;
      return;
    }
    const offset: OffsetResult = this.monthDetailsScroller.currentOffset();
    this.monthDetailsAtTopAtGestureStart = offset.yOffset <= 1;
  }

  private updateMonthGesture(offsetX: number, offsetY: number): void {
    if (!this.monthDragging && TeachingCalendarLogic.monthSheetOwnsGesture(
      offsetY, this.monthDragStartPosition, this.monthDetailsAtTopAtGestureStart) &&
      TeachingCalendarLogic.canMoveMonthSheet(
      offsetX, offsetY, this.monthDragStartPosition)) {
      this.monthDragging = true;
    }
    if (this.monthDragging) {
      this.monthSheetPosition = TeachingCalendarLogic.monthSheetDragPosition(
        offsetY, this.monthDragStartPosition);
    }
  }

  private finishMonthGesture(offsetX: number, offsetY: number,
    velocityX: number, velocityY: number): void {
    if (this.monthDragging) {
      const target: number = TeachingCalendarLogic.settledMonthSheetPosition(
        this.monthSheetPosition, velocityY);
      this.settleMonthSheet(target);
      this.monthDragging = false;
      return;
    }
    const predicted: number = Math.abs(velocityX) > 200 ? velocityX * 0.25 : offsetX;
    const direction: number | null = TeachingCalendarLogic.swipeDirection(offsetX, offsetY, predicted);
    if (direction !== null) {
      this.animateDate(direction);
      return;
    }
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
    this.session.isMonthExpanded = target === TeachingCalendarLogic.monthSheetExpandedPosition;
    if (target > TeachingCalendarLogic.monthSheetExpandedPosition) {
      this.revealMonthDetailsAfter(duration + 12);
    }
  }

  private revealMonthDetailsAfter(delay: number): void {
    this.monthDetailsReadyRevision++;
    const revision: number = this.monthDetailsReadyRevision;
    setTimeout(() => {
      if (revision === this.monthDetailsReadyRevision &&
        this.monthSheetPosition > TeachingCalendarLogic.monthSheetExpandedPosition + 0.01) {
        this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(this.selectedDate()));
        this.monthDetailsReady = true;
        setTimeout(() => {
          this.monthDetailsScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
        }, 0);
      }
    }, Math.max(delay, 0));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.compactHeader()
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            this.currentCalendarPage()
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.pageOffsetX })

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
        })
      }
      .width('100%')
      .height('100%')

      if (this.presentedDay !== null) {
        this.dayDetailOverlay()
      }
      if (this.allDayDialogDay !== null) {
        if (this.allDayDialogModeRawValue === CalendarMode.month) {
          this.monthAllDayDialogOverlay()
        } else {
          this.weekAllDayDialogOverlay()
        }
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

  @Builder
  currentCalendarPage() {
    if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
      this.timelineContent(this.mode(), this.selectedDate(), true)
    } else if (this.mode() === CalendarMode.month) {
      this.monthView(this.selectedDate(), true)
    } else {
      this.yearView(this.selectedDate(), true)
    }
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
            .fontWeight(this.mode() === item ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(AppTheme.text())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(32)
            .backgroundColor(this.mode() === item ? AppTheme.segmentedSelection() : Color.Transparent)
            .borderRadius(6)
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

      if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
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
      if (this.mode() === CalendarMode.week) {
        Column({ space: 0 }) {
          Text(TeachingCalendarLogic.weekOfYear(this.selectedDate()).toString())
            .fontSize(9.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.secondaryText())
          Text(this.model.text('周'))
            .fontSize(9.5)
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
      Text(CalendarFormatters.weekdayLabel(day, this.isEnglish()))
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
            .fontSize(8)
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
      .height(8)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(day.equals(this.selectedDate()) ? AppTheme.selectedDate() : Color.Transparent)
    .borderRadius(10)
    .border({
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
      if (this.courseSectionExpanded) {
        this.selectedDateCourses(
          TeachingCalendarLogic.timelineCourseSummaryDate(renderMode, renderDate))
      }
      this.statusArea(true, renderMode, renderDate)
      this.allDayItems(renderMode, renderDate, interactive)
      Scroll(interactive ? this.timelineScroller : this.incomingTimelineScroller) {
        Column() {
          MobileCalendarTimelineView({
            days: this.timelineDays(renderMode, renderDate),
            placements: MobileCalendarTimelineView.placementsFor(
              this.timelineDays(renderMode, renderDate)),
            selectedDate: renderDate,
            showsWeekColumns: renderMode === CalendarMode.week,
            onSelectDay: (day: DateParts): void => {
              if (interactive) {
                this.navigateTo(day);
              }
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
      .edgeEffect(EdgeEffect.None)
      .width('100%')
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
      Text(CalendarFormatters.fullDate(renderDate, this.isEnglish()))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .maxLines(1)
        .layoutWeight(1)
      Text(this.model.text(this.coursesOn(renderDate).length === 0 ? '暂无课程' :
        this.coursesOn(renderDate).length.toString() + ' 门课'))
        .fontSize(11)
        .fontColor(AppTheme.secondaryText())
      Text(this.courseSectionExpanded ? '⌃' : '⌄')
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
    }
    .height(36)
    .padding({ left: 16, right: 16, top: 5, bottom: 5 })
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.surface())
    .onClick(() => {
      if (interactive) {
        animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
          this.courseSectionExpanded = !this.courseSectionExpanded;
        });
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
    Column({ space: 6 }) {
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
          }
          .width('100%')
          .height(34)
        }, (course: Course, index: number) => 'selected-course.' + course.id + '.' + index.toString())
      }
    }
    .padding({ left: 16, right: 16, top: 6, bottom: 8 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AppTheme.surface())
  }

  private courseSubtitle(course: Course): string {
    const parts: string[] = [course.timeRange, CalendarTimelineLogic.courseMetadata(course)];
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
          Text(CalendarFormatters.monthDayCompact(renderDate, this.isEnglish()) + ' · ' + item.title)
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.tint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .backgroundColor(item.fill)
            .onClick(() => {
              if (interactive) {
                this.presentAllDayDialog(renderDate, CalendarMode.day);
              }
            })
        }, (item: CalendarAllDayItem) => 'selected-all-day-item.' + item.id)
        if (this.allDayItemsOn(renderDate).length > 3) {
          Text('+' + (this.allDayItemsOn(renderDate).length - 3).toString())
            .fontSize(10.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.primary())
            .height(30)
            .padding({ left: 10, right: 10 })
            .borderRadius(15)
            .border({ width: 1, color: AppTheme.border() })
            .backgroundColor(AppTheme.background())
            .onClick(() => {
              if (interactive) {
                this.presentAllDayDialog(renderDate, CalendarMode.day);
              }
            })
        }
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .height(46)
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .width('100%')
    .height(46)
    .backgroundColor(AppTheme.surface())
  }

  @Builder
  weekAllDayItems(renderDate: DateParts, interactive: boolean) {
    Row({ space: 0 }) {
      Text(this.model.text('全天'))
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.secondaryText())
        .width(MobileCalendarTimelineLayout.axisWidth)
        .height(40)
        .textAlign(TextAlign.Center)
      Row({ space: 0 }) {
        ForEach(this.weekDates(renderDate), (day: DateParts) => {
          if (this.allDayItemsOn(day).length === 0) {
            Column()
              .layoutWeight(1)
              .height(40)
          } else {
            Text(this.weekAllDayLabel(day))
              .fontSize(9.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.allDayItemsOn(day)[0].tint)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(36)
              .margin(2)
              .padding({ left: 3, right: 3 })
              .borderRadius(4)
              .backgroundColor(this.allDayItemsOn(day)[0].fill)
              .onClick(() => {
                if (interactive) {
                  this.presentAllDayDialog(day, CalendarMode.week);
                }
              })
          }
        }, (day: DateParts) => 'week-all-day.' + StrictDates.formatDateParts(day))
      }
      .layoutWeight(1)
      .height(40)
    }
    .width('100%')
    .height(40)
    .backgroundColor(AppTheme.surface())
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
    for (const item of this.holidayItemsOn(day)) {
      result.push(new CalendarAllDayItem('holiday-' + item.id(),
        this.model.text(item.type === 'holiday' ? '休' : '班') + ' ' + item.name,
        item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary(), AppTheme.selection(),
        TeachingCalendarLogic.timelineAgendaSortOrder(item.type)));
    }
    const date: string = StrictDates.formatDateParts(day);
    for (const item of this.model.assignmentDeadlinesByDate.get(date) ?? []) {
      result.push(new CalendarAllDayItem('assignment-' + item.id,
        this.model.text('作业') + ' · ' + item.title,
        AppTheme.assignment(), '#153478F6', TeachingCalendarLogic.timelineAgendaSortOrder('assignment')));
    }
    const snapshot: PublicDeadlineSnapshot | undefined = this.model.publicDeadlinesByDate.get(date);
    if (snapshot !== undefined) {
      for (const item of snapshot.items) {
        if (!this.model.deadlineItemEnabled(item)) {
          continue;
        }
        const title: string = item.source === PublicDeadlineSource.schoolNotice ?
          this.model.text('校内') + ' · ' + item.name :
          this.model.text(PublicDeadlineKindInfo.title(item.kind)) + ' · ' + item.name;
        const event: CalendarAllDayItem = new CalendarAllDayItem('deadline-' + item.id, title,
          item.source === PublicDeadlineSource.schoolNotice ?
            AppTheme.schoolNotice() : AppTheme.publicDeadline(),
          item.source === PublicDeadlineSource.schoolNotice ? '#15FF3B30' : '#15C06A00',
          TeachingCalendarLogic.timelineAgendaSortOrder(
            item.source === PublicDeadlineSource.schoolNotice ? 'school_notice' : 'public_deadline'));
        result.push(event);
      }
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

  // ---------- 月视图 ----------

  @Builder
  monthView(renderDate: DateParts, interactive: boolean) {
    Column({ space: 0 }) {
      this.statusArea(false, CalendarMode.month, renderDate)
      this.monthWeekdayHeader()
      ForEach(this.monthWeeks(renderDate), (week: DateParts[], rowIndex: number) => {
        Row({ space: 2 }) {
          ForEach(week, (day: DateParts) => {
            this.monthDayButton(day, rowIndex, renderDate, interactive)
          }, (day: DateParts) => 'month-day.' + StrictDates.formatDateParts(day))
        }
        .width('100%')
        .height(this.monthRowHeight(rowIndex, renderDate))
        .opacity(this.monthRowHeight(rowIndex, renderDate) <= 0 ? 0 : 1)
        .clip(true)
      }, (week: DateParts[], rowIndex: number) => 'month-week.' + rowIndex.toString() + '.' +
        StrictDates.formatDateParts(week[0]))

      this.monthExpansionHandle()
      if (this.monthSheetPosition > 0.01 && this.monthDetailsReady) {
        List({ space: 0, scroller: this.monthDetailsScroller }) {
          ListItem() {
            Column({ space: 10 }) {
              // ArkUI 会复用 Builder 子树；按日期设置 key，翻月后强制刷新详情内容。
              ForEach([renderDate], (day: DateParts) => {
                this.daySummaryCard(day)
                CalendarDailyInfoCards({ day: day })
              }, (day: DateParts) => 'month-summary.' + StrictDates.formatDateParts(day))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 8 })
        .opacity(Math.min(this.monthSheetPosition, 1))
        .enableScrollInteraction(this.monthSheetPosition >=
          TeachingCalendarLogic.monthSheetWeekPosition - 0.01)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .borderRadius(10)
        .backgroundColor(AppTheme.background())
        .clip(true)
        .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
      }
    }
    .padding({ left: 0, right: 0, top: 8, bottom: 0 })
    .width('100%')
    .height('100%')
    .opacity(this.monthPageOpacity)
    .gesture(
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
            this.monthDragging = false;
          }
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
    const dates: DateParts[] = this.monthGridDates(new DateParts(
      renderDate.year, renderDate.month, 1));
    for (let index: number = 0; index < dates.length; index++) {
      if (dates[index].equals(renderDate)) {
        return Math.floor(index / 7);
      }
    }
    return 0;
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

  private expandedMonthCellHeight(): number {
    const reserved: number = 26 + 8 + 28;
    return Math.max(44, Math.min(TeachingCalendarLogic.monthExpandedCellHeight,
      Math.floor((this.contentHeight - reserved) / 6)));
  }

  private monthRowHeight(rowIndex: number, renderDate: DateParts = this.selectedDate()): number {
    return TeachingCalendarLogic.monthRowHeight(this.monthSheetPosition, rowIndex,
      this.selectedMonthWeekIndex(renderDate), this.expandedMonthCellHeight());
  }

  private monthExpansionProgress(): number {
    return TeachingCalendarLogic.monthCellExpansionProgress(this.monthSheetPosition);
  }

  @Builder
  monthDayButton(day: DateParts, rowIndex: number, renderDate: DateParts, interactive: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 0 }) {
        Row({ space: 3 }) {
          Text(day.day.toString())
            .fontSize(15)
            .fontWeight(day.equals(renderDate) ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.monthForeground(day, renderDate))
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
        if (this.monthExpansionProgress() > 0.01) {
          this.expandedMonthEvents(day, renderDate, interactive)
        }
        if (this.monthExpansionProgress() < 0.99) {
          Text(this.compactMonthMarker(day))
            .fontSize(9.5)
            .fontColor(this.monthForeground(day, renderDate))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(TeachingCalendarLogic.interpolateMonthMetric(12, 0,
              this.monthExpansionProgress()))
            .opacity(1 - this.monthExpansionProgress())
        }
      }
      .padding({
        left: TeachingCalendarLogic.interpolateMonthMetric(4, 3, this.monthExpansionProgress()),
        right: TeachingCalendarLogic.interpolateMonthMetric(4, 3, this.monthExpansionProgress()),
        top: 5,
        bottom: TeachingCalendarLogic.interpolateMonthMetric(5, 2, this.monthExpansionProgress())
      })
      .width('100%')
      .height('100%')
      .justifyContent(this.monthExpansionProgress() > 0.01 ? FlexAlign.Start : FlexAlign.Center)
      this.deadlineBorderLayers(day, 10, 7, 6)
    }
    .layoutWeight(1)
    .height(this.monthRowHeight(rowIndex, renderDate))
    .backgroundColor(this.monthBackground(day, renderDate))
    .borderRadius(10)
    .clip(true)
    .onClick(() => {
      if (!interactive) {
        return;
      }
      const target: number = TeachingCalendarLogic.monthSheetDetailsPosition;
      if (!day.equals(renderDate) || Math.round(this.monthSheetPosition) !== target) {
        this.performCalendarHaptic();
      }
      this.monthDetailsReady = false;
      this.setSelectedDate(day);
      this.settleMonthSheet(target, false);
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

  private monthEventCapacity(day: DateParts, renderDate: DateParts): number {
    const height: number = this.monthRowHeight(this.selectedMonthWeekIndex(renderDate), renderDate);
    const available: number = TeachingCalendarLogic.monthEntryAvailableHeight(
      height, this.monthExpansionProgress());
    return TeachingCalendarLogic.monthEntrySlotCapacity(available);
  }

  private visibleMonthEventCount(day: DateParts, renderDate: DateParts): number {
    return TeachingCalendarLogic.visibleMonthEntryCount(
      this.monthEvents(day).length, this.monthEventCapacity(day, renderDate));
  }

  private hiddenMonthEventCount(day: DateParts, renderDate: DateParts): number {
    return TeachingCalendarLogic.hiddenMonthEntryCount(
      this.monthEvents(day).length, this.monthEventCapacity(day, renderDate));
  }

  @Builder
  expandedMonthEvents(day: DateParts, renderDate: DateParts, interactive: boolean) {
    Column({ space: 1 }) {
      ForEach(this.monthEvents(day).slice(0, this.visibleMonthEventCount(day, renderDate)),
        (event: MonthEvent) => {
          this.monthEventItem(event, day.equals(renderDate))
        }, (event: MonthEvent) => 'month-event.' + event.id)
      if (this.hiddenMonthEventCount(day, renderDate) > 0) {
        Text('+' + this.hiddenMonthEventCount(day, renderDate).toString())
          .fontSize(9.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(day.equals(renderDate) ? AppTheme.onPrimary() : AppTheme.text())
          .width('100%')
          .height(14)
          .padding({ left: 3, right: 3 })
          .textAlign(TextAlign.Start)
          .borderRadius(4)
          .backgroundColor(day.equals(renderDate) ? AppTheme.selectedDateStrong() : AppTheme.selection())
          .onClick(() => {
            if (interactive) {
              this.presentAllDayDialog(day, CalendarMode.month);
            }
          })
        }
      }
    .width('100%')
    .height(TeachingCalendarLogic.monthEntryAvailableHeight(
      this.monthRowHeight(this.selectedMonthWeekIndex(renderDate), renderDate), this.monthExpansionProgress()))
    .alignItems(HorizontalAlign.Start)
    .opacity(this.monthExpansionProgress())
  }

  @Builder
  monthEventItem(event: MonthEvent, selected: boolean) {
    Text(event.title)
      .fontSize(9.5)
      .fontWeight(FontWeight.Medium)
      .fontColor(selected ? AppTheme.onPrimary() : event.tint)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 3, right: 3 })
      .width('100%')
      .height(14)
      .textAlign(TextAlign.Start)
      .backgroundColor(selected ? AppTheme.selectedDateStrong() : event.fill)
      .borderRadius(4)
  }

  private monthEvents(day: DateParts): MonthEvent[] {
    const result: MonthEvent[] = [];
    for (const item of this.holidayItemsOn(day)) {
      result.push(new MonthEvent(
        'holiday-' + item.id(), this.model.text(item.type === 'holiday' ? '休' : '班') +
          ' ' + item.name,
        item.type === 'holiday', item.type === 'workday',
        item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary(), AppTheme.selection()));
    }
    for (const course of this.coursesOn(day)) {
      result.push(new MonthEvent('course-' + course.id, course.name, false, false,
        AppTheme.primary(), AppTheme.selection()));
    }
    const date: string = StrictDates.formatDateParts(day);
    for (const item of this.model.assignmentDeadlinesByDate.get(date) ?? []) {
      result.push(new MonthEvent('assignment-' + item.id,
        this.model.text('作业') + ' ' + item.title, false, false,
        AppTheme.assignment(), '#153478F6'));
    }
    const snapshot: PublicDeadlineSnapshot | undefined = this.model.publicDeadlinesByDate.get(date);
    if (snapshot !== undefined) {
      for (const item of snapshot.items) {
        if (this.model.deadlineItemEnabled(item)) {
          const school: boolean = item.source === PublicDeadlineSource.schoolNotice;
          result.push(new MonthEvent('deadline-' + item.id,
            (school ? this.model.text('校内') :
              this.model.text(PublicDeadlineKindInfo.title(item.kind))) + ' ' + item.name,
            false, false,
          school ? AppTheme.schoolNotice() : AppTheme.publicDeadline(),
          school ? '#15FF3B30' : '#15C06A00'));
        }
      }
    }
    return result;
  }

  @Builder
  monthExpansionHandle() {
    Column() {
      Row({ space: 0 }) {
        Column()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(AppTheme.secondaryText())
          .rotate({ angle: -24 * this.monthExpansionProgress(), centerX: '100%', centerY: '50%' })
        Column()
          .width(20)
          .height(4)
          .borderRadius(2)
          .backgroundColor(AppTheme.secondaryText())
          .rotate({ angle: 24 * this.monthExpansionProgress(), centerX: '0%', centerY: '50%' })
      }
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      const rounded: number = Math.round(this.monthSheetPosition);
      const target: number = rounded === 0 ? 1 : (rounded === 1 ? 0 : 1);
      if (rounded === TeachingCalendarLogic.monthSheetExpandedPosition &&
        target > TeachingCalendarLogic.monthSheetExpandedPosition) {
        this.monthDetailsReady = false;
      }
      this.settleMonthSheet(target);
    })
  }

  private monthForeground(day: DateParts, renderDate: DateParts): ResourceColor {
    if (day.equals(renderDate)) {
      return AppTheme.onPrimary();
    }
    if (day.month !== renderDate.month) {
      return AppTheme.secondaryText();
    }
    const holiday: HolidayItem | null = this.firstHoliday(day);
    if (holiday === null) {
      return AppTheme.text();
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
    return this.coursesOn(day).length + Math.max(this.monthEvents(day).length -
      this.holidayItemsOn(day).length - this.coursesOn(day).length, 0);
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
      .padding(16)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
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
      Text(CalendarFormatters.monthLabel(month, this.isEnglish()))
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
            .fontSize(8)
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
            .fontSize(8)
            .fontColor(day.equals(this.selectedDate()) ?
              AppTheme.onPrimary() : AppTheme.text())
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
        this.deadlineBorderLayers(day, 4, 2, 4)
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
        this.setSelectedDate(day);
        this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(day));
        this.presentedDayAnchorX = Number(event.target.area.globalPosition.x) - this.rootGlobalX +
          Number(event.target.area.width) / 2;
        this.presentedDayAnchorY = Number(event.target.area.globalPosition.y) - this.rootGlobalY +
          Number(event.target.area.height) / 2;
        this.presentedDay = day;
      })
    } else {
      Column()
        .width('100%')
        .height(26)
    }
  }

  private yearDeadlinePriorities(day: DateParts): CalendarYearDeadlinePriority[] {
    const date: string = StrictDates.formatDateParts(day);
    const assignmentCount: number = (this.model.assignmentDeadlinesByDate.get(date) ?? []).length;
    let schoolCount: number = 0;
    let otherCount: number = 0;
    const snapshot: PublicDeadlineSnapshot | undefined = this.model.publicDeadlinesByDate.get(date);
    if (snapshot !== undefined) {
      for (const item of snapshot.items) {
        if (!this.model.deadlineItemEnabled(item)) {
          continue;
        }
        if (item.source === PublicDeadlineSource.schoolNotice) {
          schoolCount++;
        } else {
          otherCount++;
        }
      }
    }
    return TeachingCalendarLogic.yearDeadlineBorderLayers(
      assignmentCount, schoolCount, otherCount);
  }

  @Builder
  deadlineBorderLayers(day: DateParts, outerRadius: number, innerRadius: number,
    innerInset: number) {
    ForEach(this.yearDeadlinePriorities(day),
      (priority: CalendarYearDeadlinePriority, index: number) => {
      Column()
        .width(index === 0 ? '100%' : this.deadlineInnerSize(innerInset))
        .height(index === 0 ? '100%' : this.deadlineInnerSize(innerInset))
        .border({
          width: index === 0 ? 1.5 : 1,
          color: this.yearDeadlineBorderColor(priority)
        })
        .borderRadius(index === 0 ? outerRadius : innerRadius)
        .hitTestBehavior(HitTestMode.None)
      }, (priority: CalendarYearDeadlinePriority, index: number) =>
        priority + '.' + index.toString())
  }

  private deadlineInnerSize(innerInset: number): string {
    return 'calc(100% - ' + innerInset.toString() + 'vp)';
  }

  private yearDeadlineBorderColor(priority: CalendarYearDeadlinePriority): ResourceColor {
    if (priority === CalendarYearDeadlinePriority.assignment) {
      return AppTheme.assignment();
    }
    if (priority === CalendarYearDeadlinePriority.schoolNotice) {
      return AppTheme.schoolNotice();
    }
    return AppTheme.publicDeadline();
  }

  // ---------- 月/周全天日程弹窗 ----------

  private presentAllDayDialog(day: DateParts, mode: CalendarMode): void {
    if (TeachingCalendarLogic.agendaDialogChangesSelectedDate(mode)) {
      this.setSelectedDate(day);
    }
    this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(day));
    this.allDayDialogModeRawValue = mode;
    this.allDayDialogDay = day;
  }

  @Builder
  weekAllDayDialogOverlay() {
    this.centeredAllDayDialog(CalendarModeInfo.fromRawValue(this.allDayDialogModeRawValue))
  }

  @Builder
  monthAllDayDialogOverlay() {
    this.centeredAllDayDialog(CalendarMode.month)
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
            Text(TeachingCalendarLogic.allDayDialogTitle(mode, this.isEnglish()))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
            Text(CalendarFormatters.fullDate(this.allDayDialogDay as DateParts, this.isEnglish()))
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
            ForEach(this.allDayItemsOn(this.allDayDialogDay as DateParts),
              (item: CalendarAllDayItem) => {
                Text(item.title)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(item.tint)
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .backgroundColor(item.fill)
              }, (item: CalendarAllDayItem) => 'all-day-dialog.' + mode + '.' + item.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .constraintSize({ maxHeight: Math.max(this.rootHeight - 180, 160) })
        .width('100%')
      }
      .padding(16)
      .width(Math.min(360, Math.max(this.rootWidth - 32, 240)))
      .constraintSize({ maxHeight: Math.max(this.rootHeight - 48, 220) })
      .borderRadius(12)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.surface())
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
          this.presentedDay = null;
        })
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text(CalendarFormatters.monthDayCompact(this.presentedDay as DateParts, this.isEnglish()))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
            .layoutWeight(1)
          Text(this.model.text('完成'))
            .fontSize(14)
            .fontColor(AppTheme.primary())
            .onClick(() => {
              this.presentedDay = null;
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
        .edgeEffect(EdgeEffect.None)
        .layoutWeight(1)
        .width('100%')
      }
      .padding(14)
      .width(this.dayDetailWidth())
      .height(this.dayDetailHeight(this.presentedDay as DateParts))
      .borderRadius(8)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.surface())
      .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Start)
      .position({
        x: this.dayDetailX(),
        y: this.dayDetailY(this.presentedDay as DateParts)
      })
    }
    .width('100%')
    .height('100%')
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
          .border({ width: 1, color: AppTheme.border() })
          .backgroundColor(AppTheme.background())
          .onClick(() => {
            this.performCalendarHaptic();
            this.setSelectedDate(day);
            this.setMode(item);
            this.presentedDay = null;
          })
      }, (item: CalendarMode) => 'year-jump.' + item)
    }
    .width('100%')
  }

  @Builder
  daySummaryCard(day: DateParts, framed: boolean = true) {
    Column({ space: 10 }) {
      Text(CalendarFormatters.fullDate(day, this.isEnglish()))
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
    .border({ width: framed ? 1 : 0, color: AppTheme.border() })
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
      }
      .padding(8)
      .width(230)
      .borderRadius(10)
      .backgroundColor(AppTheme.surface())
      .margin({ top: 44, right: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  private periodTitle(): string {
    return TeachingCalendarLogic.periodTitle(this.selectedDate(), this.mode(), this.isEnglish());
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
    if (this.timelineScrollTimer >= 0) {
      clearTimeout(this.timelineScrollTimer);
    }
    this.timelineScrollTimer = setTimeout(() => {
      this.timelineScrollTimer = -1;
      scroller.scrollTo({
        xOffset: 0,
        yOffset: (hour - 8) * MobileCalendarTimelineLayout.hourHeight
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

  constructor(id: string, title: string, tint: ResourceColor, fill: ResourceColor,
    sortOrder: number) {
    this.id = id;
    this.title = title;
    this.tint = tint;
    this.fill = fill;
    this.sortOrder = sortOrder;
  }
}

// 主题主色的透明度变体（供月/年单元格背景使用；深浅色下均可用）。
class CalendarColors {
  static primaryWithAlpha(alpha: number, dark: boolean): string {
    const clamped: number = Math.min(Math.max(alpha, 0), 1);
    const fg: number[] = dark ? [0x5A, 0xD2, 0xB8] : [0x16, 0x6B, 0x5D];
    const bg: number[] = dark ? [0x00, 0x00, 0x00] : [0xF2, 0xF2, 0xF7];
    const channels: string[] = [];
    for (let i = 0; i < 3; i++) {
      const v: number = Math.round(bg[i] + (fg[i] - bg[i]) * clamped);
      channels.push(v.toString(16).padStart(2, '0'));
    }
    return '#' + channels.join('').toUpperCase();
  }
}
