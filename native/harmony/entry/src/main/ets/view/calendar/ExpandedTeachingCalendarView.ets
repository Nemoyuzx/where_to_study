// 宽屏（>= 760vp，含 2in1/PC 与平板展开态）教学日历，对应 iOS 端
// TeachingCalendarView（非移动端布局）：
// 标题 + 视图分段选择 + 日期导航与课表操作 + 日/周时间线（周视图带列）+
// 常展开的月网格（直接显示课程与节假日条目）+ 12 个月年视图与跳转面板。
import { AppModel } from '../../model/AppModel';
import { Course, HolidayItem } from '../../common/Models';
import { StrictDates, DateParts } from '../../common/StrictDates';
import { AppTheme } from '../../common/AppTheme';
import { PageTitle } from '../SharedComponents';
import {
  CalendarFormatters, CalendarMode, CalendarModeInfo, CalendarTimelineDay,
  CalendarTimelineLogic, TeachingCalendarLogic
} from './CalendarLogic';
import { TeachingCalendarSession } from './TeachingCalendarSession';
import { MobileCalendarTimelineView } from './MobileCalendarTimelineView';

class MonthEventItem {
  readonly id: string;
  readonly title: string;
  readonly tint: ResourceColor;

  constructor(id: string, title: string, tint: ResourceColor) {
    this.id = id;
    this.title = title;
    this.tint = tint;
  }
}

@ComponentV2
export struct ExpandedTeachingCalendarView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: TeachingCalendarSession = new TeachingCalendarSession();
  @Local presentedDay: DateParts | null = null;
  @Local contentWidth: number = 900;

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

  private periodTitle(): string {
    return TeachingCalendarLogic.periodTitle(this.selectedDate(), this.mode());
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 16 }) {
          Row({ space: 24 }) {
            PageTitle({ eyebrow: 'BUPT Classroom Planner', title: this.periodTitle() })
              .layoutWeight(1)
            Row() {
              ForEach(CalendarModeInfo.all, (item: CalendarMode) => {
                Text(item)
                  .fontSize(14)
                  .fontWeight(this.mode() === item ? FontWeight.Medium : FontWeight.Regular)
                  .fontColor(this.mode() === item ? AppTheme.onPrimary() : AppTheme.text())
                  .textAlign(TextAlign.Center)
                  .width(64)
                  .height(30)
                  .backgroundColor(this.mode() === item ?
                    AppTheme.primaryFill() : Color.Transparent)
                  .borderRadius(6)
                  .onClick(() => {
                    this.setMode(item);
                  })
              }, (item: CalendarMode) => 'mode.' + item)
            }
            .padding(2)
            .borderRadius(8)
            .border({ width: 1, color: AppTheme.border() })
            .backgroundColor(AppTheme.background())
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)

          this.dateControls()

          ForEach(this.statusMessages(), (message: string) => {
            Text(message)
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
              .width('100%')
          }, (message: string) => 'status.' + message)

          Divider()
            .color(AppTheme.border())

          if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
            this.timelineContent()
          } else if (this.mode() === CalendarMode.month) {
            this.monthContent()
          } else {
            this.yearContent()
          }
        }
        .padding(20)
        .width('100%')
        .constraintSize({ maxWidth: 1200 })
        .alignItems(HorizontalAlign.Start)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.contentWidth = Number(newArea.width);
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)

      if (this.presentedDay !== null) {
        this.jumpOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
  }

  @Builder
  dateControls() {
    Row({ space: 8 }) {
      Text('‹')
        .fontSize(20)
        .fontColor(AppTheme.text())
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .onClick(() => {
          this.moveDate(-1);
        })

      Row({ space: 7 }) {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(14)
          .fontColor([AppTheme.text()])
        Text(StrictDates.formatDateParts(this.selectedDate()))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
      }
      .height(32)
      .padding({ left: 10, right: 10 })
      .borderRadius(7)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.background())

      Text('今天')
        .fontSize(14)
        .fontColor(AppTheme.text())
        .height(32)
        .padding({ left: 10, right: 10 })
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .onClick(() => {
          this.setSelectedDate(StrictDates.todayParts());
        })

      Text('›')
        .fontSize(20)
        .fontColor(AppTheme.text())
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .onClick(() => {
          this.moveDate(1);
        })

      Blank()
        .width(12)

      Text(this.model.isRefreshingSchedule ? '正在获取…' : '获取/刷新个人课表')
        .fontSize(13)
        .fontColor(AppTheme.text())
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .backgroundColor(AppTheme.background())
        .onClick(() => {
          if (!this.model.isRefreshingSchedule && !this.model.isImportingCalendar) {
            this.model.refreshSchedule();
          }
        })

      Text(this.model.isImportingCalendar ? '正在导入…' : '导入系统日历')
        .fontSize(13)
        .fontColor(AppTheme.text())
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .backgroundColor(AppTheme.background())
        .onClick(() => {
          if (this.model.schedule !== null && !this.model.isRefreshingSchedule &&
            !this.model.isImportingCalendar) {
            this.model.importScheduleToCalendar();
          }
        })
    }
    .width('100%')
  }

  @Builder
  timelineContent() {
    Column({ space: 12 }) {
      this.allDayRow()
      Scroll() {
        MobileCalendarTimelineView({
          days: this.timelineDays(),
          selectedDate: this.selectedDate(),
          showsWeekColumns: this.mode() === CalendarMode.week,
          onSelectDay: (day: DateParts): void => {
            this.setSelectedDate(day);
          }
        })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .width('100%')
    }
    .width('100%')
    .height(720)
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
  allDayRow() {
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
                this.setSelectedDate(entry.day);
              })
          }, (entry: AllDayEntry) => entry.item.id())
        }
        .padding({ top: 4, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
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

  @Builder
  monthContent() {
    Column({ space: 12 }) {
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

      Grid() {
        ForEach(this.monthGridDates(new DateParts(
          this.selectedDate().year, this.selectedDate().month, 1)),
          (day: DateParts) => {
            GridItem() {
              this.monthDayCell(day)
            }
          }, (day: DateParts) => 'month-day.' + StrictDates.formatDateParts(day))
      }
      .columnsTemplate('repeat(7, 1fr)')
      .columnsGap(4)
      .rowsGap(4)
      .width('100%')

      this.daySummaryCard(this.selectedDate())
    }
    .width('100%')
  }

  @Builder
  monthDayCell(day: DateParts) {
    Column({ space: 4 }) {
      Text(day.day.toString())
        .fontSize(13)
        .fontWeight(day.equals(this.selectedDate()) ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.monthForeground(day))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 3 })
      Column({ space: 2 }) {
        ForEach(this.monthEvents(day).slice(0, 2), (event: MonthEventItem) => {
          Text(event.title)
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : event.tint)
            .maxLines(1)
            .padding({ left: 3, right: 3 })
            .width('100%')
            .height(14)
            .textAlign(TextAlign.Center)
            .backgroundColor('#C7FFFFFF')
            .borderRadius(4)
            .border({ width: 0.75, color: AppTheme.border() })
        }, (event: MonthEventItem) => 'month-event.' + event.id)
        if (this.monthEvents(day).length > 2) {
          Text('+' + (this.monthEvents(day).length - 2).toString())
            .fontSize(10)
            .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : AppTheme.secondaryText())
            .width('100%')
            .height(14)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .padding({ left: 2, right: 2, bottom: 2 })
    .width('100%')
    .height(76)
    .borderRadius(5)
    .backgroundColor(day.equals(this.selectedDate()) ?
      AppTheme.primaryFill() : this.monthBackground(day))
    .border({
      width: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ? 2 : 1,
      color: day.equals(StrictDates.todayParts()) && !day.equals(this.selectedDate()) ?
        AppTheme.danger() : AppTheme.border()
    })
    .clip(true)
    .onClick(() => {
      this.setSelectedDate(day);
    })
  }

  private monthEvents(day: DateParts): MonthEventItem[] {
    const result: MonthEventItem[] = [];
    for (const item of this.holidayItemsOn(day)) {
      result.push(new MonthEventItem(
        'holiday-' + item.id(), (item.type === 'holiday' ? '休 ' : '班 ') + item.name,
        item.type === 'holiday' ? AppTheme.danger() : AppTheme.primary()));
    }
    for (const course of this.coursesOn(day)) {
      result.push(new MonthEventItem('course-' + course.id, course.name, AppTheme.primary()));
    }
    return result;
  }

  private monthForeground(day: DateParts): ResourceColor {
    if (day.equals(this.selectedDate())) {
      return AppTheme.onPrimary();
    }
    if (day.month !== this.selectedDate().month) {
      return AppTheme.secondaryText();
    }
    const items: HolidayItem[] = this.holidayItemsOn(day);
    if (items.length === 0) {
      return AppTheme.text();
    }
    return items[0].type === 'holiday' ? AppTheme.danger() : AppTheme.primary();
  }

  private monthBackground(day: DateParts): ResourceColor {
    const count: number = this.coursesOn(day).length;
    if (count <= 0) {
      return Color.Transparent;
    }
    const alpha: number = Math.min(0.08 + count * 0.08, 0.36);
    return CalendarColors.primaryWithAlpha(alpha);
  }

  @Builder
  yearContent() {
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
        .columnsGap(14)
        .rowsGap(18)
        .width('100%')
      }
      .padding({ top: 4, bottom: 16 })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
  }

  private yearColumnCount(): number {
    if (this.contentWidth >= 1080) {
      return 5;
    }
    if (this.contentWidth >= 880) {
      return 4;
    }
    return 3;
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
        .fontSize(15)
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

  @Builder
  jumpOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#33000000')
        .onClick(() => {
          this.presentedDay = null;
        })
      Column({ space: 12 }) {
        Text(CalendarFormatters.fullDate(this.presentedDay as DateParts))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
        Scroll() {
          this.daySummaryCard(this.presentedDay as DateParts)
        }
        .constraintSize({ maxHeight: 320 })
        .width('100%')
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
                this.setSelectedDate(this.presentedDay as DateParts);
                this.setMode(item);
                this.presentedDay = null;
              })
          }, (item: CalendarMode) => 'year-jump.' + item)
        }
        .width('100%')
      }
      .padding(16)
      .width(320)
      .borderRadius(10)
      .backgroundColor(AppTheme.surface())
      .position({ x: '50%', y: '30%' })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  daySummaryCard(day: DateParts) {
    Column({ space: 8 }) {
      Text(CalendarFormatters.fullDate(day))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      ForEach(this.holidayItemsOn(day), (item: HolidayItem) => {
        Text((item.type === 'holiday' ? '休 ' : '班 ') + item.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(item.type === 'holiday' ? AppTheme.danger() : AppTheme.primary())
      }, (item: HolidayItem) => 'summary-holiday.' + item.id())
      if (this.coursesOn(day).length === 0) {
        Text('暂无课程')
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else {
        ForEach(this.coursesOn(day), (course: Course) => {
          Row({ space: 8 }) {
            Text(course.timeRange)
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
              .width(110)
            Column({ space: 2 }) {
              Text(course.name)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.text())
              Text(CalendarTimelineLogic.courseMetadata(course))
                .fontSize(11)
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
    .padding({ top: 4 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

class CalendarColors {
  static primaryWithAlpha(alpha: number): string {
    const clamped: number = Math.min(Math.max(alpha, 0), 1);
    const hexAlpha: string = Math.round(clamped * 255).toString(16).padStart(2, '0');
    return '#' + hexAlpha.toUpperCase() + '166B5D';
  }
}
