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
  CalendarTimelineLogic, TeachingCalendarLogic
} from './CalendarLogic';
import { TeachingCalendarSession } from './TeachingCalendarSession';
import { CoursePlacement, MobileCalendarTimelineLayout, MobileCalendarTimelineView } from './MobileCalendarTimelineView';
import { vibrator } from '@kit.SensorServiceKit';

class MonthEvent {
  readonly id: string;
  readonly title: string;
  readonly isHoliday: boolean;
  readonly isWorkday: boolean;

  constructor(id: string, title: string, isHoliday: boolean, isWorkday: boolean) {
    this.id = id;
    this.title = title;
    this.isHoliday = isHoliday;
    this.isWorkday = isWorkday;
  }
}

@ComponentV2
export struct MobileTeachingCalendarView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: TeachingCalendarSession = new TeachingCalendarSession();
  @Local presentedDay: DateParts | null = null;
  @Local showingActions: boolean = false;
  @Local contentWidth: number = 350;
  @Local contentHeight: number = 500;
  @Local pageOffsetX: number = 0;
  @Local monthSheetPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local monthDragStartPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  @Local monthDragging: boolean = false;
  private pageAnimating: boolean = false;
  private timelineScroller: Scroller = new Scroller();
  private timelineScrollTimer: number = -1;
  private timelinePlacements: Map<string, CoursePlacement[]> =
    new Map<string, CoursePlacement[]>();

  aboutToAppear(): void {
    this.monthSheetPosition = this.session.isMonthExpanded ?
      TeachingCalendarLogic.monthSheetExpandedPosition :
      TeachingCalendarLogic.monthSheetDetailsPosition;
    this.ensureVisibleHolidays();
  }

  aboutToDisappear(): void {
    // 清理延迟滚动定时器，避免对已销毁 Scroller 操作（BUG-012 修复）。
    if (this.timelineScrollTimer >= 0) {
      clearTimeout(this.timelineScrollTimer);
      this.timelineScrollTimer = -1;
    }
  }

  @Monitor('session.selectedDate')
  onSelectedDateChange(monitor: IMonitor): void {
    this.ensureVisibleHolidays();
  }

  @Monitor('session.modeRawValue')
  onModeChange(monitor: IMonitor): void {
    this.ensureVisibleHolidays();
  }

  private mode(): CalendarMode {
    return CalendarModeInfo.fromRawValue(this.session.modeRawValue);
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
    this.animatePageChange(direction, (): void => {
      this.setMode(mode);
    });
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

  private weekDates(): DateParts[] {
    const weekday: number = StrictDates.weekdayMonday1(this.selectedDate());
    const start: DateParts = StrictDates.addDays(this.selectedDate(), 1 - weekday);
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

  private visibleHolidayYears(): number[] {
    const result: Set<number> = new Set<number>();
    if (this.mode() === CalendarMode.week) {
      for (const day of this.weekDates()) {
        result.add(day.year);
      }
    } else if (this.mode() === CalendarMode.month) {
      for (const day of this.monthGridDates(this.selectedDate())) {
        result.add(day.year);
      }
    } else {
      result.add(this.selectedDate().year);
    }
    const list: number[] = [];
    for (const year of result) {
      list.push(year);
    }
    return list;
  }

  private holidayStatus(): string {
    for (const year of this.visibleHolidayYears()) {
      const status: string | undefined = this.model.holidayStatusByYear.get(year);
      if (status !== undefined && status.length > 0) {
        return status;
      }
    }
    return '';
  }

  private ensureVisibleHolidays(): void {
    for (const year of this.visibleHolidayYears()) {
      this.model.ensureHolidays(year, false);
    }
  }

  private moveDate(direction: number): void {
    this.setSelectedDate(TeachingCalendarLogic.movedDate(
      this.selectedDate(), this.mode(), direction));
  }

  private animateDate(direction: number): void {
    this.animatePageChange(direction, (): void => {
      this.moveDate(direction);
    });
  }

  private animatePageChange(direction: number, change: () => void): void {
    if (direction === 0 || this.pageAnimating) {
      return;
    }
    this.performCalendarHaptic();
    this.pageAnimating = true;
    const distance: number = Math.max(this.contentWidth, 320);
    animateTo({ duration: 150, curve: Curve.EaseIn }, (): void => {
      this.pageOffsetX = -direction * distance;
    });
    setTimeout(() => {
      change();
      this.pageOffsetX = direction * distance;
      animateTo({ duration: 150, curve: Curve.EaseOut }, (): void => {
        this.pageOffsetX = 0;
      });
      setTimeout(() => {
        this.pageAnimating = false;
      }, 160);
    }, 150);
  }

  private navigateTo(date: DateParts): void {
    if (!date.equals(this.selectedDate())) {
      this.performCalendarHaptic();
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
  }

  private updateMonthGesture(offsetX: number, offsetY: number): void {
    if (!this.monthDragging && TeachingCalendarLogic.canMoveMonthSheet(
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
    this.settleMonthSheet(Math.round(this.monthDragStartPosition));
  }

  private settleMonthSheet(position: number, haptic: boolean = true): void {
    const target: number = Math.min(Math.max(Math.round(position), 0), 2);
    if (haptic && target !== Math.round(this.monthSheetPosition)) {
      this.performCalendarHaptic();
    }
    animateTo({ duration: 120 + 160 * Math.abs(target - this.monthSheetPosition),
      curve: Curve.EaseInOut }, (): void => {
      this.monthSheetPosition = target;
    });
    this.session.isMonthExpanded = target === TeachingCalendarLogic.monthSheetExpandedPosition;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.compactHeader()
        Column() {
          if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
            this.timelineContent()
          } else if (this.mode() === CalendarMode.month) {
            this.monthView()
          } else {
            this.yearView()
          }
        }
        .layoutWeight(1)
        .width('100%')
        .translate({ x: this.pageOffsetX })
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
      if (this.showingActions) {
        this.actionsOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
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

        Text('今天')
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
          Text(item)
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
          Text('周')
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
      Text(CalendarFormatters.weekdayLabel(day))
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
          Text(this.firstHoliday(day)?.type === 'holiday' ? '休' : '班')
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
    .backgroundColor(day.equals(this.selectedDate()) ? AppTheme.primaryFill() : Color.Transparent)
    .borderRadius(10)
    .border({
      width: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ? 2 : 0,
      color: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ?
        AppTheme.primary() : Color.Transparent
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
    return holiday.type === 'holiday' ? AppTheme.danger() : AppTheme.primary();
  }

  private firstHoliday(day: DateParts): HolidayItem | null {
    const items: HolidayItem[] = this.holidayItemsOn(day);
    return items.length > 0 ? items[0] : null;
  }

  @Builder
  statusArea(useSurface: boolean = true) {
    if (this.statusMessages().length > 0) {
      Column({ space: 4 }) {
        ForEach(this.statusMessages(), (message: string, index: number) => {
          Text(message)
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

  private statusMessages(): string[] {
    const result: string[] = [];
    const holiday: string = this.holidayStatus();
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
  timelineContent() {
    Column({ space: 0 }) {
      this.selectedDateSummary()
      this.statusArea()
      this.allDayItems()
      Scroll(this.timelineScroller) {
        Column() {
          MobileCalendarTimelineView({
            days: this.timelineDays(),
            placements: this.timelinePlacements,
            selectedDate: this.selectedDate(),
            showsWeekColumns: this.mode() === CalendarMode.week,
            onSelectDay: (day: DateParts): void => {
              this.navigateTo(day);
            }
          })
          Column()
            .height(MobileCalendarTimelineLayout.bottomContentInset)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .width('100%')
      .onAppear(() => {
        this.scrollTimelineToInitialHour();
      })
    }
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          this.handlePeriodSwipe(event.offsetX, event.offsetY, event.velocityX);
        })
    )
  }

  private timelineDays(): CalendarTimelineDay[] {
    const days: DateParts[] = this.mode() === CalendarMode.week ?
      this.weekDates() : [this.selectedDate()];
    const result: CalendarTimelineDay[] = [];
    for (const day of days) {
      result.push(new CalendarTimelineDay(day, this.coursesOn(day), this.holidayItemsOn(day)));
    }
    // 一次算好课程布局，供时间线复用（BUG-046 修复）。
    this.timelinePlacements = MobileCalendarTimelineView.placementsFor(result);
    return result;
  }

  @Builder
  selectedDateSummary() {
    Row({ space: 8 }) {
      Text(CalendarFormatters.fullDate(this.selectedDate()))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .maxLines(1)
        .layoutWeight(1)
      Text(this.coursesOn(this.selectedDate()).length === 0 ? '暂无课程' :
        this.coursesOn(this.selectedDate()).length.toString() + ' 门课')
        .fontSize(11)
        .fontColor(AppTheme.secondaryText())
    }
    .height(36)
    .padding({ left: 16, right: 16, top: 5, bottom: 5 })
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.surface())
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          this.handlePeriodSwipe(event.offsetX, event.offsetY, event.velocityX);
        })
    )
  }

  private courseSubtitle(course: Course): string {
    const parts: string[] = [course.timeRange, CalendarTimelineLogic.courseMetadata(course)];
    return parts.filter((value: string) => value.length > 0).join(' · ');
  }

  @Builder
  allDayItems() {
    if (this.allDayEntries().length > 0) {
      Row({ space: 0 }) {
        Text('全天')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
          .width(MobileCalendarTimelineLayout.axisWidth)
          .height(40)
          .textAlign(TextAlign.Center)
        Row({ space: 0 }) {
          ForEach(this.timelineDays(), (day: CalendarTimelineDay) => {
            Text(this.allDayLabel(day))
              .fontSize(this.mode() === CalendarMode.week ? 9.5 : 11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.allDayForeground(day))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(36)
              .margin({ left: 2, right: 2 })
              .padding({ left: 3, right: 3 })
              .borderRadius(4)
              .backgroundColor(day.holidays.length > 0 ? AppTheme.selection() : Color.Transparent)
              .onClick(() => {
                if (day.holidays.length > 0) {
                  this.navigateTo(day.date);
                }
              })
          }, (day: CalendarTimelineDay) => 'all-day.' + StrictDates.formatDateParts(day.date))
        }
        .layoutWeight(1)
        .height(40)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(40)
      .backgroundColor(AppTheme.surface())
    }
  }

  private allDayLabel(day: CalendarTimelineDay): string {
    const parts: string[] = [];
    for (const item of day.holidays) {
      parts.push((item.type === 'holiday' ? '休 ' : '班 ') + item.name);
    }
    return parts.join(' · ');
  }

  private allDayForeground(day: CalendarTimelineDay): ResourceColor {
    for (const item of day.holidays) {
      if (item.type === 'holiday') {
        return AppTheme.danger();
      }
    }
    return AppTheme.primary();
  }

  private allDayEntries(): AllDayEntry[] {
    const days: DateParts[] = this.mode() === CalendarMode.week ?
      this.weekDates() : [this.selectedDate()];
    const result: AllDayEntry[] = [];
    for (const day of days) {
      for (const item of this.holidayItemsOn(day)) {
        result.push(new AllDayEntry(day, item));
      }
    }
    return result;
  }

  // ---------- 月视图 ----------

  @Builder
  monthView() {
    Column({ space: 0 }) {
      this.statusArea(false)
      this.monthWeekdayHeader()
      ForEach(this.monthWeeks(), (week: DateParts[], rowIndex: number) => {
        Row({ space: 2 }) {
          ForEach(week, (day: DateParts) => {
            this.monthDayButton(day, rowIndex)
          }, (day: DateParts) => 'month-day.' + StrictDates.formatDateParts(day))
        }
        .width('100%')
        .height(this.monthRowHeight(rowIndex))
        .opacity(this.monthRowHeight(rowIndex) <= 0 ? 0 : 1)
        .clip(true)
      }, (week: DateParts[], rowIndex: number) => 'month-week.' + rowIndex.toString() + '.' +
        StrictDates.formatDateParts(week[0]))

      this.monthExpansionHandle()
      if (this.monthSheetPosition > 0.01) {
        Scroll() {
          Column() {
            // ArkUI 会复用 Builder 子树；按日期设置 key，翻月后强制刷新详情内容。
            ForEach([this.selectedDate()], (day: DateParts) => {
              this.daySummaryCard(day)
            }, (day: DateParts) => 'month-summary.' + StrictDates.formatDateParts(day))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .opacity(Math.min(this.monthSheetPosition, 1))
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
      }
    }
    .padding({ left: 0, right: 0, top: 8, bottom: 0 })
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 18 })
        .onActionStart(() => {
          this.beginMonthGesture();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateMonthGesture(event.offsetX, event.offsetY);
        })
        .onActionEnd((event: GestureEvent) => {
          this.finishMonthGesture(event.offsetX, event.offsetY, event.velocityX, event.velocityY);
        })
        .onActionCancel(() => {
          this.settleMonthSheet(Math.round(this.monthDragStartPosition));
          this.monthDragging = false;
        })
    )
  }

  private monthWeeks(): DateParts[][] {
    const dates: DateParts[] = this.monthGridDates(new DateParts(
      this.selectedDate().year, this.selectedDate().month, 1));
    const weeks: DateParts[][] = [];
    for (let row: number = 0; row < 6; row++) {
      weeks.push(dates.slice(row * 7, row * 7 + 7));
    }
    return weeks;
  }

  private selectedMonthWeekIndex(): number {
    const dates: DateParts[] = this.monthGridDates(new DateParts(
      this.selectedDate().year, this.selectedDate().month, 1));
    for (let index: number = 0; index < dates.length; index++) {
      if (dates[index].equals(this.selectedDate())) {
        return Math.floor(index / 7);
      }
    }
    return 0;
  }

  @Builder
  monthWeekdayHeader() {
    Row({ space: 4 }) {
      ForEach(CalendarFormatters.weekdayLabels, (label: string) => {
        Text(label)
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

  private monthRowHeight(rowIndex: number): number {
    return TeachingCalendarLogic.monthRowHeight(this.monthSheetPosition, rowIndex,
      this.selectedMonthWeekIndex(), this.expandedMonthCellHeight());
  }

  private monthExpansionProgress(): number {
    return TeachingCalendarLogic.monthCellExpansionProgress(this.monthSheetPosition);
  }

  @Builder
  monthDayButton(day: DateParts, rowIndex: number) {
    Column({ space: 0 }) {
      Text(day.day.toString())
        .fontSize(15)
        .fontWeight(day.equals(this.selectedDate()) ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.monthForeground(day))
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(24)
      if (this.monthExpansionProgress() > 0.01) {
        this.expandedMonthEvents(day)
      }
      if (this.monthExpansionProgress() < 0.99) {
        Text(this.compactMonthMarker(day))
          .fontSize(9.5)
          .fontColor(this.monthForeground(day))
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
    .layoutWeight(1)
    .height(this.monthRowHeight(rowIndex))
    .justifyContent(this.monthExpansionProgress() > 0.01 ? FlexAlign.Start : FlexAlign.Center)
    .backgroundColor(this.monthBackground(day))
    .borderRadius(10)
    .border({
      width: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ? 2 : 0,
      color: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ?
        AppTheme.primary() : Color.Transparent
    })
    .clip(true)
    .onClick(() => {
      const target: number = TeachingCalendarLogic.monthSheetDetailsPosition;
      if (!day.equals(this.selectedDate()) || Math.round(this.monthSheetPosition) !== target) {
        this.performCalendarHaptic();
      }
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

  private monthEventCapacity(day: DateParts): number {
    const height: number = this.monthRowHeight(this.selectedMonthWeekIndex());
    const available: number = TeachingCalendarLogic.monthEntryAvailableHeight(
      height, this.monthExpansionProgress());
    return TeachingCalendarLogic.monthEntrySlotCapacity(available);
  }

  private visibleMonthEventCount(day: DateParts): number {
    return TeachingCalendarLogic.visibleMonthEntryCount(
      this.monthEvents(day).length, this.monthEventCapacity(day));
  }

  private hiddenMonthEventCount(day: DateParts): number {
    return TeachingCalendarLogic.hiddenMonthEntryCount(
      this.monthEvents(day).length, this.monthEventCapacity(day));
  }

  @Builder
  expandedMonthEvents(day: DateParts) {
    Column({ space: 1 }) {
      ForEach(this.monthEvents(day).slice(0, this.visibleMonthEventCount(day)),
        (event: MonthEvent) => {
          this.monthEventItem(event, day.equals(this.selectedDate()))
        }, (event: MonthEvent) => 'month-event.' + event.id)
      if (this.hiddenMonthEventCount(day) > 0) {
        Text('+' + this.hiddenMonthEventCount(day).toString())
          .fontSize(9.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : AppTheme.text())
          .width('100%')
          .height(14)
          .padding({ left: 3, right: 3 })
          .textAlign(TextAlign.Start)
          .borderRadius(4)
          .backgroundColor(day.equals(this.selectedDate()) ? AppTheme.primary() : AppTheme.selection())
        }
      }
    .width('100%')
    .height(TeachingCalendarLogic.monthEntryAvailableHeight(
      this.monthRowHeight(this.selectedMonthWeekIndex()), this.monthExpansionProgress()))
    .alignItems(HorizontalAlign.Start)
    .opacity(this.monthExpansionProgress())
  }

  @Builder
  monthEventItem(event: MonthEvent, selected: boolean) {
    Text(event.title)
      .fontSize(9.5)
      .fontWeight(FontWeight.Medium)
      .fontColor(selected ? AppTheme.onPrimary() : AppTheme.text())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 3, right: 3 })
      .width('100%')
      .height(14)
      .textAlign(TextAlign.Start)
      .backgroundColor(selected ? AppTheme.primary() : AppTheme.selection())
      .borderRadius(4)
  }

  private monthEvents(day: DateParts): MonthEvent[] {
    const result: MonthEvent[] = [];
    for (const item of this.holidayItemsOn(day)) {
      result.push(new MonthEvent(
        'holiday-' + item.id(), (item.type === 'holiday' ? '休 ' : '班 ') + item.name,
        item.type === 'holiday', item.type === 'workday'));
    }
    for (const course of this.coursesOn(day)) {
      result.push(new MonthEvent('course-' + course.id, course.name, false, false));
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
      this.settleMonthSheet(target);
    })
  }

  private monthForeground(day: DateParts): ResourceColor {
    if (day.equals(this.selectedDate())) {
      return AppTheme.onPrimary();
    }
    if (day.month !== this.selectedDate().month) {
      return AppTheme.secondaryText();
    }
    const holiday: HolidayItem | null = this.firstHoliday(day);
    if (holiday === null) {
      return AppTheme.text();
    }
    return holiday.type === 'holiday' ? AppTheme.danger() : AppTheme.primary();
  }

  private monthBackground(day: DateParts): ResourceColor {
    if (day.equals(this.selectedDate())) {
      return AppTheme.primaryFill();
    }
    const count: number = this.coursesOn(day).length;
    if (count <= 0) {
      return Color.Transparent;
    }
    const alpha: number = Math.min(0.08 + count * 0.08, 0.36);
    return CalendarColors.primaryWithAlpha(alpha);
  }

  // ---------- 年视图 ----------

  @Builder
  yearView() {
    Scroll() {
      Column({ space: 12 }) {
        this.statusArea(false)
        Text('颜色越深表示当天课程越多')
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
        Grid() {
          ForEach(this.monthsOfYear(), (month: number) => {
            GridItem() {
              this.miniMonth(month)
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
  miniMonth(month: number) {
    Column({ space: 0 }) {
      Text(CalendarFormatters.monthLabel(month))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .width('100%')
        .height(28)
        .textAlign(TextAlign.Start)
        .onClick(() => {
          this.setSelectedDate(new DateParts(this.selectedDate().year, month, 1));
          this.animateMode(CalendarMode.month);
        })
      Row({ space: 1 }) {
        ForEach(CalendarFormatters.weekdayLabels, (label: string) => {
          Text(label)
            .fontSize(8)
            .fontColor(AppTheme.secondaryText())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
        }, (label: string) => 'year-weekday.' + month.toString() + '.' + label)
      }
      .width('100%')
      .height(14)

      Grid() {
        ForEach(this.monthGridDates(new DateParts(this.selectedDate().year, month, 1)),
          (day: DateParts) => {
            GridItem() {
              this.yearDayButton(day, month)
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
  yearDayButton(day: DateParts, month: number) {
    if (day.month === month) {
      Text(day.day.toString())
        .fontSize(8)
        .fontColor(this.presentedDay !== null && day.equals(this.presentedDay as DateParts) ?
          AppTheme.onPrimary() : AppTheme.text())
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(26)
        .borderRadius(4)
        .backgroundColor(this.presentedDay !== null && day.equals(this.presentedDay as DateParts) ?
          AppTheme.primaryFill() : CalendarColors.primaryWithAlpha(
            TeachingCalendarLogic.yearCourseOpacity(this.coursesOn(day).length)))
        .border({
          width: day.equals(StrictDates.todayParts()) ? 2 : 0.5,
          color: day.equals(StrictDates.todayParts()) ? AppTheme.primary() : AppTheme.border()
        })
        .onClick(() => {
          this.performCalendarHaptic();
          this.setSelectedDate(day);
          this.presentedDay = day;
        })
    } else {
      Column()
        .width('100%')
        .height(26)
    }
  }

  // ---------- 详情卡片 ----------

  @Builder
  dayDetailOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.presentedDay = null;
        })
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(CalendarFormatters.monthDayCompact(this.presentedDay as DateParts))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
            .layoutWeight(1)
          Text('完成')
            .fontSize(14)
            .fontColor(AppTheme.primary())
            .onClick(() => {
              this.presentedDay = null;
            })
        }
        .width('100%')

        this.yearNavigationCommands(this.presentedDay as DateParts)
        Scroll() {
          this.daySummaryCard(this.presentedDay as DateParts)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .padding(14)
      .width(Math.min(300, this.contentWidth - 32))
      .height(Math.min(420, this.contentHeight * 0.68))
      .borderRadius(8)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.surface())
      .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  yearNavigationCommands(day: DateParts) {
    Row({ space: 8 }) {
      ForEach(CalendarModeInfo.all.slice(0, 3), (item: CalendarMode) => {
        Text(item + '视图')
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
  daySummaryCard(day: DateParts) {
    Column({ space: 10 }) {
      Text(CalendarFormatters.fullDate(day))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      ForEach(this.holidayItemsOn(day), (item: HolidayItem) => {
        Row({ space: 6 }) {
          SymbolGlyph(item.type === 'holiday' ? $r('sys.symbol.calendar_badge_clock') :
            $r('sys.symbol.briefcase'))
            .fontSize(14)
            .fontColor([item.type === 'holiday' ? AppTheme.danger() : AppTheme.primary()])
          Text(item.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.type === 'holiday' ? AppTheme.danger() : AppTheme.primary())
        }
        .width('100%')
      }, (item: HolidayItem) => 'summary-holiday.' + item.id())

      if (this.coursesOn(day).length === 0) {
        Text('暂无课程')
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
    .padding(14)
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
  }

  // ---------- 操作菜单 ----------

  @Builder
  actionsOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
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
          Text(this.model.isRefreshingSchedule ? '正在获取…' : '获取/刷新个人课表')
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
          Text(this.model.isImportingCalendar ? '正在导入…' : '导入系统日历')
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
      .position({ x: 8, y: 40 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  private periodTitle(): string {
    return TeachingCalendarLogic.periodTitle(this.selectedDate(), this.mode());
  }

  private shanghaiHour(): number {
    const shanghaiMs: number = (Date.now() + 8 * 3600 * 1000) % 86400000;
    return Math.floor(Math.floor(shanghaiMs / 60000) / 60);
  }

  private scrollTimelineToInitialHour(): void {
    const days: CalendarTimelineDay[] = this.timelineDays();
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
      this.timelineScroller.scrollTo({
        xOffset: 0,
        yOffset: (hour - 8) * MobileCalendarTimelineLayout.hourHeight
      });
    }, 150);
  }
}

class AllDayEntry {
  readonly day: DateParts;
  readonly item: HolidayItem;

  constructor(day: DateParts, item: HolidayItem) {
    this.day = day;
    this.item = item;
  }
}

// 主题主色的透明度变体（供月/年单元格背景使用；深浅色下均可用）。
class CalendarColors {
  static primaryWithAlpha(alpha: number): string {
    const clamped: number = Math.min(Math.max(alpha, 0), 1);
    const hexAlpha: string = Math.round(clamped * 255).toString(16).padStart(2, '0');
    return '#' + hexAlpha.toUpperCase() + '166B5D';
  }
}
