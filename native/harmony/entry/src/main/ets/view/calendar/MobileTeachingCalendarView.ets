// 移动端教学日历页，对应 iOS 端 MobileTeachingCalendarView.swift。
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
import { MobileCalendarTimelineLayout, MobileCalendarTimelineView } from './MobileCalendarTimelineView';

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
  private timelineScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.ensureVisibleHolidays();
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

  private navigateTo(date: DateParts): void {
    this.setSelectedDate(date);
  }

  private handlePeriodSwipe(offsetX: number, offsetY: number, velocityX: number): void {
    if (this.mode() === CalendarMode.year) {
      return;
    }
    const predicted: number = Math.abs(velocityX) > 200 ? velocityX * 0.25 : offsetX;
    const direction: number | null = TeachingCalendarLogic.swipeDirection(offsetX, offsetY, predicted);
    if (direction !== null) {
      this.moveDate(direction);
    }
  }

  private handleMonthGesture(offsetX: number, offsetY: number, velocityX: number): void {
    const predicted: number = Math.abs(velocityX) > 200 ? velocityX * 0.25 : offsetX;
    const direction: number | null = TeachingCalendarLogic.swipeDirection(offsetX, offsetY, predicted);
    if (direction !== null) {
      this.moveDate(direction);
      return;
    }
    const action: number | null = TeachingCalendarLogic.monthExpansionAction(offsetX, offsetY);
    if (action === null) {
      return;
    }
    if (action > 0 && this.session.isMonthExpanded) {
      return;
    }
    if (action < 0 && !this.session.isMonthExpanded) {
      return;
    }
    this.session.isMonthExpanded = action > 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.compactHeader()
        this.statusArea()
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
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text(this.periodTitle())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .maxLines(1)
          .layoutWeight(1)

        Text('今天')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.primary())
          .onClick(() => {
            this.navigateTo(StrictDates.todayParts());
          })

        Text('‹')
          .fontSize(24)
          .fontColor(AppTheme.text())
          .width(30)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.moveDate(-1);
          })

        Text('›')
          .fontSize(24)
          .fontColor(AppTheme.text())
          .width(30)
          .height(36)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.moveDate(1);
          })

        Text('⋯')
          .fontSize(20)
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

      Row() {
        ForEach(CalendarModeInfo.all, (item: CalendarMode) => {
          Text(item)
            .fontSize(14)
            .fontWeight(this.mode() === item ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.mode() === item ? AppTheme.onPrimary() : AppTheme.text())
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(30)
            .backgroundColor(this.mode() === item ? AppTheme.primaryFill() : Color.Transparent)
            .borderRadius(6)
            .onClick(() => {
              this.setMode(item);
            })
        }, (item: CalendarMode) => 'mode.' + item)
      }
      .width('100%')
      .padding(2)
      .borderRadius(8)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.background())

      if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
        this.weekDateStrip()
      }
    }
    .padding({
      left: 16,
      right: 16,
      top: 8,
      bottom: this.mode() === CalendarMode.day || this.mode() === CalendarMode.week ? 8 : 6
    })
    .width('100%')
    .backgroundColor(AppTheme.surface())
  }

  @Builder
  weekDateStrip() {
    Row({ space: 0 }) {
      if (this.mode() === CalendarMode.week) {
        Column({ space: 0 }) {
          Text(TeachingCalendarLogic.weekOfYear(this.selectedDate()).toString())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.secondaryText())
          Text('周')
            .fontSize(10)
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
        .fontWeight(FontWeight.Medium)
      Text(day.day.toString())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
      Row({ space: 2 }) {
        if (this.firstHoliday(day) !== null) {
          Text(this.firstHoliday(day)?.type === 'holiday' ? '休' : '班')
            .fontSize(8)
            .fontWeight(FontWeight.Bold)
        }
        if (this.coursesOn(day).length > 0) {
          Column()
            .width(4)
            .height(4)
            .borderRadius(2)
            .backgroundColor(this.stripForeground(this.firstHoliday(day)))
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
  statusArea() {
    if (this.statusMessages().length > 0) {
      Column({ space: 4 }) {
        ForEach(this.statusMessages(), (message: string) => {
          Text(message)
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
            .maxLines(2)
            .width('100%')
        }, (message: string) => 'status.' + message)
      }
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#14166B5D')
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
      this.allDayItems()
      Scroll(this.timelineScroller) {
        Column() {
          MobileCalendarTimelineView({
            days: this.timelineDays(),
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
  }

  private timelineDays(): CalendarTimelineDay[] {
    const days: DateParts[] = this.mode() === CalendarMode.week ?
      this.weekDates() : [this.selectedDate()];
    const result: CalendarTimelineDay[] = [];
    for (const day of days) {
      result.push(new CalendarTimelineDay(day, this.coursesOn(day), this.holidayItemsOn(day)));
    }
    return result;
  }

  @Builder
  selectedDateSummary() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text(CalendarFormatters.fullDate(this.selectedDate()))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Text(this.coursesOn(this.selectedDate()).length === 0 ? '暂无课程' :
          this.coursesOn(this.selectedDate()).length.toString() + ' 门课')
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(this.coursesOn(this.selectedDate()), (course: Course) => {
        Column({ space: 2 }) {
          Text(course.name)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.text())
            .maxLines(1)
          Text(this.courseSubtitle(course))
            .fontSize(11)
            .fontColor(AppTheme.secondaryText())
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }, (course: Course) => 'summary.' + course.id)
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
      Scroll() {
        Row({ space: 8 }) {
          Text('全天')
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
          ForEach(this.allDayEntries(), (entry: AllDayEntry) => {
            Text(CalendarFormatters.monthDayCompact(entry.day) + ' · ' + entry.item.name)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(entry.item.type === 'holiday' ? AppTheme.danger() : AppTheme.primary())
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .backgroundColor('#14166B5D')
              .onClick(() => {
                this.navigateTo(entry.day);
              })
          }, (entry: AllDayEntry) => entry.item.id())
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .backgroundColor(AppTheme.surface())
    }
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
      this.monthWeekdayHeader()
      Grid() {
        ForEach(this.monthGridDates(new DateParts(
          this.selectedDate().year, this.selectedDate().month, 1)),
          (day: DateParts) => {
            GridItem() {
              this.monthDayButton(day)
            }
          }, (day: DateParts) => 'month-day.' + StrictDates.formatDateParts(day))
      }
      .columnsTemplate('repeat(7, 1fr)')
      .columnsGap(4)
      .rowsGap(4)
      .width('100%')

      this.monthExpansionHandle()
      if (!this.session.isMonthExpanded) {
        this.daySummaryCard(this.selectedDate())
      }
      Blank()
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .width('100%')
    .height('100%')
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 18 })
        .onActionEnd((event: GestureEvent) => {
          this.handleMonthGesture(event.offsetX, event.offsetY, event.velocityX);
        })
    )
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

  private monthCellHeight(): number {
    if (!this.session.isMonthExpanded) {
      return 46;
    }
    const reserved: number = 18 + 8 + 20 + 16;
    return Math.max(44, Math.min(82, Math.floor((this.contentHeight - reserved) / 6)));
  }

  @Builder
  monthDayButton(day: DateParts) {
    Column({ space: this.session.isMonthExpanded ? 4 : 3 }) {
      Text(day.day.toString())
        .fontSize(14)
        .fontWeight(day.equals(this.selectedDate()) ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.monthForeground(day))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: this.session.isMonthExpanded ? 3 : 0 })
      if (this.session.isMonthExpanded) {
        this.expandedMonthEvents(day)
      } else {
        Row({ space: 2 }) {
          if (this.firstHoliday(day) !== null) {
            Text(this.firstHoliday(day)?.type === 'holiday' ? '休' : '班')
              .fontSize(8)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.monthForeground(day))
          }
          if (this.coursesOn(day).length > 0) {
            Column()
              .width(3)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.monthForeground(day))
          }
        }
        .height(7)
      }
    }
    .padding({ left: this.session.isMonthExpanded ? 2 : 3, right: this.session.isMonthExpanded ? 2 : 3 })
    .width('100%')
    .height(this.monthCellHeight())
    .justifyContent(this.session.isMonthExpanded ? FlexAlign.Start : FlexAlign.Center)
    .backgroundColor(this.monthBackground(day))
    .borderRadius(9)
    .border({
      width: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ? 2 : 0,
      color: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ?
        AppTheme.primary() : Color.Transparent
    })
    .clip(true)
    .onClick(() => {
      this.navigateTo(day);
    })
  }

  @Builder
  expandedMonthEvents(day: DateParts) {
    Column({ space: 2 }) {
      ForEach(this.monthEvents(day).slice(0, this.monthEventLayoutFor(day)[0]),
        (event: MonthEvent) => {
          this.monthEventItem(event)
        }, (event: MonthEvent) => 'month-event.' + event.id)
      if (this.monthEventLayoutFor(day)[1] > 0) {
        Text('+' + this.monthEventLayoutFor(day)[1].toString())
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : AppTheme.secondaryText())
          .width('100%')
          .height(14)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .backgroundColor('#C766B5B5')
          .border({ width: 0.75, color: AppTheme.border() })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  monthEventItem(event: MonthEvent) {
    Text(event.title)
      .fontSize(9)
      .fontWeight(FontWeight.Medium)
      .fontColor(event.isHoliday ? AppTheme.danger() : AppTheme.primary())
      .maxLines(1)
      .padding({ left: 3, right: 3 })
      .width('100%')
      .height(14)
      .textAlign(TextAlign.Center)
      .backgroundColor('#C7FFFFFF')
      .borderRadius(4)
      .border({ width: 0.75, color: AppTheme.border() })
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

  private monthEventLayoutFor(day: DateParts): number[] {
    const events: MonthEvent[] = this.monthEvents(day);
    const rowLimit: number = this.monthCellHeight() >= 58 ? 2 : 1;
    return TeachingCalendarLogic.monthEventLayout(events.length, rowLimit);
  }

  @Builder
  monthExpansionHandle() {
    Column({ space: 4 }) {
      Row({ space: 14 }) {
        Column()
          .width(21)
          .height(4)
          .borderRadius(2)
          .backgroundColor('#8C66000000')
          .rotate({ angle: this.session.isMonthExpanded ? -24 : 0 })
        Column()
          .width(21)
          .height(4)
          .borderRadius(2)
          .backgroundColor('#8C66000000')
          .rotate({ angle: this.session.isMonthExpanded ? 24 : 0 })
      }
    }
    .width('100%')
    .height(28)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.session.isMonthExpanded = !this.session.isMonthExpanded;
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
    return this.contentWidth >= 720 ? 3 : 2;
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
    Column({ space: 6 }) {
      Text(CalendarFormatters.monthLabel(month))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
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

      Grid() {
        ForEach(this.monthGridDates(new DateParts(this.selectedDate().year, month, 1)),
          (day: DateParts) => {
            GridItem() {
              this.yearDayButton(day, month)
            }
          }, (day: DateParts) => 'year-day.' + StrictDates.formatDateParts(day))
      }
      .columnsTemplate('repeat(7, 1fr)')
      .columnsGap(1)
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
        .fontColor(AppTheme.text())
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(24)
        .borderRadius(4)
        .backgroundColor(CalendarColors.primaryWithAlpha(
          TeachingCalendarLogic.yearCourseOpacity(this.coursesOn(day).length)))
        .border({
          width: day.equals(StrictDates.todayParts()) ? 2 : 0.5,
          color: day.equals(StrictDates.todayParts()) ? AppTheme.primary() : AppTheme.border()
        })
        .onClick(() => {
          this.setSelectedDate(day);
          this.presentedDay = day;
        })
    } else {
      Column()
        .width('100%')
        .height(24)
    }
  }

  // ---------- 详情卡片 ----------

  @Builder
  dayDetailOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
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
        .constraintSize({ maxHeight: 420 })
        .width('100%')
      }
      .padding(16)
      .width('100%')
      .borderRadius({ topLeft: 16, topRight: 16 })
      .backgroundColor(AppTheme.background())
      .position({ x: 0, y: '60%' })
      .height('40%')
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
        ForEach(this.coursesOn(day), (course: Course) => {
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
        }, (course: Course) => 'summary-course.' + course.id)
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
    setTimeout(() => {
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
