// 宽屏（>= 760vp，含 2in1/PC 与平板展开态）教学日历，对应 iOS 端
// TeachingCalendarView（非移动端布局）：
// 标题 + 视图分段选择 + 日期导航与课表操作 + 日/周时间线（周视图带列）+
// 常展开的月网格（直接显示课程与节假日条目）+ 12 个月年视图与跳转面板。
import { AppModel } from '../../model/AppModel';
import { Course, HolidayItem } from '../../common/Models';
import { StrictDates, DateParts } from '../../common/StrictDates';
import { AppTheme } from '../../common/AppTheme';
import { DeviceState } from '../../common/DeviceState';
import { PageTitle } from '../SharedComponents';
import {
  CalendarFormatters, CalendarMode, CalendarModeInfo, CalendarTimelineDay,
  CalendarTimelineLogic, CalendarYearDeadlinePriority, DarkModeProbe, TeachingCalendarLogic
} from './CalendarLogic';
import { TeachingCalendarSession } from './TeachingCalendarSession';
import { CoursePlacement, MobileCalendarTimelineView } from './MobileCalendarTimelineView';
import { CalendarDailyInfoCards } from './CalendarDailyInfoCards';
import {
  PublicDeadlineItem, PublicDeadlineKindInfo, PublicDeadlineSource
} from '../../net/CalendarDailyInfoClient';
import { AppLanguage } from '../../common/AppLocalization';

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
  @Local allDayDialogDay: DateParts | null = null;
  @Local allDayDialogModeRawValue: string = CalendarMode.week;
  @Local contentWidth: number = 900;
  @Local contentHeight: number = 700;
  @Local isDarkMode: boolean = false;
  @Local calendarContentOpacity: number = 1;
  @Local calendarContentAnimating: boolean = false;
  // PC（2in1）按 Windows Tauri 布局；平板/折叠屏按 Android 折叠屏布局。
  @Local isPc: boolean = DeviceState.isPc2in1();
  private darkModeProbe: DarkModeProbe = new DarkModeProbe();
  private timelinePlacements: Map<string, CoursePlacement[]> =
    new Map<string, CoursePlacement[]>();

  aboutToAppear(): void {
    this.ensureVisibleHolidays();
    this.ensureVisibleDailyInfo();
    this.darkModeProbe.register((dark: boolean) => {
      this.isDarkMode = dark;
    });
  }

  aboutToDisappear(): void {
    this.darkModeProbe.unregister();
  }

  @Monitor('session.selectedDate')
  onSelectedDateChange(monitor: IMonitor): void {
    this.ensureVisibleHolidays();
    this.ensureVisibleDailyInfo();
  }

  @Monitor('session.modeRawValue')
  onModeChange(monitor: IMonitor): void {
    this.ensureVisibleHolidays();
    this.ensureVisibleDailyInfo();
  }

  @Monitor('model.competitionDeadlinesEnabled', 'model.schoolContestNoticesEnabled',
    'model.summerCampDeadlinesEnabled', 'model.hackathonDeadlinesEnabled',
    'model.customDeadlinesEnabled', 'model.customDeadlinesURL', 'model.favoriteDeadlines')
  onDeadlineFeatureChange(monitor: IMonitor): void {
    this.ensureVisibleDailyInfo();
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

  private ensureVisibleDailyInfo(): void {
    const selected: DateParts = this.selectedDate();
    this.model.loadCalendarDailyInfo(StrictDates.formatDateParts(selected));
    if (this.mode() === CalendarMode.month) {
      this.model.prefetchCalendarMarkers(this.monthGridDates(selected));
    } else if (this.mode() === CalendarMode.week) {
      this.model.prefetchCalendarMarkers(this.weekDates());
    } else if (this.mode() === CalendarMode.year) {
      this.model.prefetchCalendarMarkers(this.yearDates(selected));
    }
  }

  private moveDate(direction: number): void {
    this.animateSelectedDate(TeachingCalendarLogic.movedDate(
      this.selectedDate(), this.mode(), direction));
  }

  private animateSelectedDate(target: DateParts): void {
    if (target.equals(this.selectedDate())) {
      return;
    }
    if (this.calendarContentAnimating) {
      this.setSelectedDate(target);
      return;
    }
    this.calendarContentAnimating = true;
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
      this.calendarContentOpacity = 0.72;
    });
    setTimeout(() => {
      this.setSelectedDate(target);
      this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseOut }, () => {
        this.calendarContentOpacity = 1;
      });
      setTimeout(() => {
        this.calendarContentAnimating = false;
      }, 150);
    }, 96);
  }

  private animateMode(target: CalendarMode): void {
    if (target === this.mode()) {
      return;
    }
    if (this.calendarContentAnimating) {
      this.setMode(target);
      return;
    }
    this.calendarContentAnimating = true;
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
      this.calendarContentOpacity = 0.72;
    });
    setTimeout(() => {
      this.setMode(target);
      this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseOut }, () => {
        this.calendarContentOpacity = 1;
      });
      setTimeout(() => {
        this.calendarContentAnimating = false;
      }, 150);
    }, 96);
  }

  private periodTitle(): string {
    const base: string = TeachingCalendarLogic.periodTitle(
      this.selectedDate(), this.mode(), this.isEnglish());
    const teachingWeek: number | null = this.model.weekNumberOn(this.selectedDate());
    if (this.mode() !== CalendarMode.week || teachingWeek === null) {
      return base;
    }
    return base + (this.isEnglish() ? ' · Teaching week ' : ' · 第') +
      teachingWeek.toString() + (this.isEnglish() ? '' : '教学周');
  }

  private monthWeekLabel(day: DateParts): string {
    if (!this.isPc || StrictDates.weekdayMonday1(day) !== 1) {
      return '';
    }
    const calendarWeek: number = TeachingCalendarLogic.weekOfYear(day);
    const teachingWeek: number | null = this.model.weekNumberOn(day);
    const base: string = this.isEnglish() ? 'W' + calendarWeek.toString() :
      '第' + calendarWeek.toString() + '周';
    if (teachingWeek === null) {
      return base;
    }
    return base + (this.isEnglish() ? ' · T' : ' · 教') + teachingWeek.toString();
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

  private handleDesktopKey(event: KeyEvent): boolean {
    if (!this.isPc || event.type !== KeyType.Down) {
      return false;
    }
    if (event.keyCode === 2068 || event.keyCode === 2014) {
      this.moveDate(-1);
      return true;
    }
    if (event.keyCode === 2069 || event.keyCode === 2015) {
      this.moveDate(1);
      return true;
    }
    if (event.keyCode === 2081) {
      this.animateSelectedDate(StrictDates.todayParts());
      return true;
    }
    const targetMode: CalendarMode | null = event.keyCode === 2020 ? CalendarMode.day :
      (event.keyCode === 2039 ? CalendarMode.week :
        (event.keyCode === 2029 ? CalendarMode.month :
          (event.keyCode === 2041 ? CalendarMode.year : null)));
    if (targetMode !== null) {
      this.animateMode(targetMode);
      return true;
    }
    if (event.keyCode === 2070) {
      this.presentedDay = null;
      this.allDayDialogDay = null;
      return true;
    }
    return false;
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
                Text(this.model.text(item))
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
                    this.animateMode(item);
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

          ForEach(this.statusMessages(), (message: string, index: number) => {
            Text(this.model.text(message))
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
              .width('100%')
          }, (message: string, index: number) => 'status.' + index.toString() + '.' + message)

          Divider()
            .color(AppTheme.border())

          Column() {
            if (this.mode() === CalendarMode.day || this.mode() === CalendarMode.week) {
              this.timelineContent()
            } else if (this.mode() === CalendarMode.month) {
              this.monthContent()
            } else {
              this.yearContent()
            }
          }
          .width('100%')
          .opacity(this.calendarContentOpacity)
        }
        .padding(20)
        .width('100%')
        .constraintSize({ maxWidth: 1200 })
        .alignSelf(ItemAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.contentWidth = Number(newArea.width);
          this.contentHeight = Number(newArea.height);
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)

      if (this.presentedDay !== null) {
        this.jumpOverlay()
      }
      if (this.allDayDialogDay !== null) {
        if (this.allDayDialogModeRawValue === CalendarMode.month) {
          this.monthAllDayDialogOverlay()
        } else {
          this.weekAllDayDialogOverlay()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .focusable(this.isPc)
    .focusOnTouch(this.isPc)
    .onKeyEvent((event: KeyEvent): boolean => this.handleDesktopKey(event))
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

      Text(this.model.text('今天'))
        .fontSize(14)
        .fontColor(AppTheme.text())
        .height(32)
        .padding({ left: 10, right: 10 })
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .onClick(() => {
          this.animateSelectedDate(StrictDates.todayParts());
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

      Text(this.model.isRefreshingSchedule ? this.model.text('正在获取…') :
        this.model.text('获取/刷新个人课表'))
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

      Text(this.model.isImportingCalendar ? this.model.text('正在导入…') :
        this.model.text('导入系统日历'))
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
          placements: this.timelinePlacements,
          selectedDate: this.selectedDate(),
          showsWeekColumns: this.mode() === CalendarMode.week,
          expanded: true,
          tauri: this.isPc,
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
    // 高度随视口自适应（BUG-058 修复），下限保证时间线可用。
    .height(Math.max(this.contentHeight - 280, 360))
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
  allDayRow() {
    if (this.allDayEntries().length > 0) {
      Row({ space: 0 }) {
        Text(this.model.text('全天'))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
          .width(58)
          .height(58)
          .textAlign(TextAlign.Center)
        Row({ space: 4 }) {
          ForEach(this.timelineDays(), (day: CalendarTimelineDay) => {
            Column({ space: 2 }) {
              ForEach(this.allDayItemsOn(day.date).slice(0, 2), (item: ExpandedAllDayItem) => {
                Text(item.title)
                  .fontSize(this.mode() === CalendarMode.week ? 9 : 11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(item.tint)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .height(18)
                  .padding({ left: 5, right: 5 })
                  .borderRadius(4)
                  .backgroundColor(item.fill)
                  .onClick(() => {
                    this.setSelectedDate(day.date);
                  })
              }, (item: ExpandedAllDayItem) => 'wide-all-day.' + item.id)
              if (this.allDayItemsOn(day.date).length > 2) {
                Text('+' + (this.allDayItemsOn(day.date).length - 2).toString())
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppTheme.primary())
                  .width('100%')
                  .height(15)
                  .textAlign(TextAlign.Start)
                  .padding({ left: 5, right: 5 })
                  .onClick(() => {
                    this.presentAllDayDialog(day.date, this.mode());
                  })
              }
            }
            .layoutWeight(1)
            .height(58)
            .justifyContent(FlexAlign.Center)
          }, (day: CalendarTimelineDay) => 'wide-all-day-day.' +
            StrictDates.formatDateParts(day.date))
        }
        .layoutWeight(1)
        .height(58)
      }
      .width('100%')
      .height(58)
      .backgroundColor(AppTheme.surface())
    }
  }

  private allDayItemsOn(day: DateParts): ExpandedAllDayItem[] {
    const result: ExpandedAllDayItem[] = [];
    for (const item of this.holidayItemsOn(day)) {
      result.push(new ExpandedAllDayItem(
        StrictDates.formatDateParts(day) + '.holiday.' + item.id(),
        this.model.text(item.type === 'holiday' ? '休' : '班') + ' ' + item.name,
      item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary(), AppTheme.selection()));
    }
    const date: string = StrictDates.formatDateParts(day);
    for (const item of this.model.assignmentDeadlinesByDate.get(date) ?? []) {
      result.push(new ExpandedAllDayItem(date + '.assignment.' + item.id,
        this.model.text('作业') + ' · ' + item.title,
        AppTheme.assignment(), AppTheme.assignmentSurface()));
    }
    for (const item of this.model.deadlineItems(date)) {
        const title: string = item.source === PublicDeadlineSource.schoolNotice ?
          this.model.text('校内') + ' · ' + item.name :
          this.model.text(PublicDeadlineKindInfo.title(item.kind)) + ' · ' + item.name;
        result.push(new ExpandedAllDayItem(date + '.deadline.' + item.id, title,
          item.source === PublicDeadlineSource.schoolNotice ?
            AppTheme.schoolNotice() : AppTheme.publicDeadline(),
          item.source === PublicDeadlineSource.schoolNotice ?
            AppTheme.schoolNoticeSurface() : AppTheme.publicDeadlineSurface(), item));
    }
    return result;
  }

  private allDayEntries(): ExpandedAllDayItem[] {
    const days: DateParts[] = this.mode() === CalendarMode.week ?
      this.weekDates() : [this.selectedDate()];
    const result: ExpandedAllDayItem[] = [];
    for (const day of days) {
      for (const item of this.allDayItemsOn(day)) {
        result.push(item);
      }
    }
    return result;
  }

  @Builder
  monthContent() {
    Column({ space: 12 }) {
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
      .columnsGap(this.isPc ? 4 : 2)
      .rowsGap(this.isPc ? 4 : 2)
      .width('100%')

      Column({ space: 10 }) {
        this.daySummaryCard(this.selectedDate())
        CalendarDailyInfoCards({ day: this.selectedDate() })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  monthDayCell(day: DateParts) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.monthWeekLabel(day).length > 0) {
        Text(this.monthWeekLabel(day))
          .fontSize(8)
          .fontWeight(FontWeight.Medium)
          .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : AppTheme.secondaryText())
          .maxLines(1)
          .position({ x: 4, y: 4 })
          .zIndex(2)
      }
      Column({ space: 4 }) {
        Row({ space: 3 }) {
          Text(day.day.toString())
            .fontSize(13)
            .fontWeight(day.equals(this.selectedDate()) ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.monthForeground(day))
          if (TeachingCalendarLogic.showsTodayMarker(day.equals(StrictDates.todayParts()))) {
            Column()
              .width(5)
              .height(5)
              .borderRadius(2.5)
              .backgroundColor(AppTheme.nowIndicator())
          }
        }
        .width('100%')
        .height(20)
        .padding({ top: 3 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        Column({ space: 1 }) {
          ForEach(this.monthEvents(day).slice(0, 2), (event: MonthEventItem) => {
            Text(event.title)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : event.tint)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 3, right: 3 })
              .width('100%')
              .height(14)
              .textAlign(TextAlign.Start)
              .backgroundColor(day.equals(this.selectedDate()) ?
                AppTheme.selectedDateStrong() : Color.Transparent)
              .borderRadius(3)
          }, (event: MonthEventItem) => 'month-event.' + event.id)
          if (this.monthEvents(day).length > 2) {
            Text('+' + (this.monthEvents(day).length - 2).toString())
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : AppTheme.secondaryText())
              .width('100%')
              .height(13)
              .textAlign(TextAlign.Start)
              .padding({ left: 2, right: 2 })
              .onClick(() => {
                this.presentAllDayDialog(day, CalendarMode.month);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.isPc ? 4 : 2, right: this.isPc ? 4 : 2,
        bottom: this.isPc ? 4 : 2 })
      this.deadlineBorderLayers(day, this.isPc ? 5 : 9, this.isPc ? 3 : 6, 6)
    }
    .width('100%')
    .height(this.isPc ? 96 : 82)
    .borderRadius(this.isPc ? 5 : 9)
    .backgroundColor(day.equals(this.selectedDate()) ?
      AppTheme.selectedDate() : this.monthBackground(day))
    .clip(true)
    .onClick(() => {
      const selected: DateParts = this.selectedDate();
      if (day.year !== selected.year || day.month !== selected.month) {
        this.animateSelectedDate(day);
      } else {
        this.setSelectedDate(day);
      }
    })
  }

  private monthEvents(day: DateParts): MonthEventItem[] {
    const result: MonthEventItem[] = [];
    for (const item of this.holidayItemsOn(day)) {
      result.push(new MonthEventItem(
        'holiday-' + item.id(), this.model.text(item.type === 'holiday' ? '休' : '班') +
          ' ' + item.name,
        item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary()));
    }
    for (const course of this.coursesOn(day)) {
      result.push(new MonthEventItem('course-' + course.id, course.name, AppTheme.primary()));
    }
    const date: string = StrictDates.formatDateParts(day);
    for (const item of this.model.assignmentDeadlinesByDate.get(date) ?? []) {
      result.push(new MonthEventItem('assignment-' + item.id,
        this.model.text('作业') + ' ' + item.title, AppTheme.assignment()));
    }
    for (const item of this.model.deadlineItems(date)) {
        result.push(new MonthEventItem('deadline-' + item.id,
            item.source === PublicDeadlineSource.schoolNotice ?
              this.model.text('校内') + ' ' + item.name :
              this.model.text(PublicDeadlineKindInfo.title(item.kind)) + ' ' + item.name,
          item.source === PublicDeadlineSource.schoolNotice ?
            AppTheme.schoolNotice() : AppTheme.publicDeadline()));
    }
    return result;
  }

  private markerCount(day: DateParts): number {
    return this.coursesOn(day).length + Math.max(this.monthEvents(day).length -
      this.holidayItemsOn(day).length - this.coursesOn(day).length, 0);
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
    return items[0].type === 'holiday' ? AppTheme.holiday() : AppTheme.primary();
  }

  private monthBackground(day: DateParts): ResourceColor {
    // PC（Tauri）格底为 surface 白底；平板（Android）无课时为透明（页面背景透出）。
    if (this.isPc && this.coursesOn(day).length <= 0) {
      return AppTheme.surface();
    }
    const count: number = this.coursesOn(day).length;
    if (count <= 0) {
      return Color.Transparent;
    }
    const alpha: number = Math.min(0.08 + count * 0.08, 0.36);
    return CalendarColors.primaryWithAlpha(alpha, this.isDarkMode);
  }

  @Builder
  yearContent() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.model.text('颜色越深表示当天日程越多'))
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
    // 对齐 Android YearCalendarView：>=1060 -> 4，>=660 -> 3，否则 2。
    if (this.contentWidth >= 1060) {
      return 4;
    }
    if (this.contentWidth >= 660) {
      return 3;
    }
    return 2;
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
      Text(CalendarFormatters.monthLabel(month, this.isEnglish()))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
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
      Stack({ alignContent: Alignment.Center }) {
        Row({ space: 2 }) {
          Text(day.day.toString())
            .fontSize(9)
            .fontColor(day.equals(this.selectedDate()) ? AppTheme.onPrimary() : AppTheme.text())
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
        this.deadlineBorderLayers(day, 3, 1.5, 4)
      }
      .width('100%')
      .height(30)
      .borderRadius(3)
      .backgroundColor(day.equals(this.selectedDate()) ?
        AppTheme.selectedDate() : CalendarColors.primaryWithAlpha(
          TeachingCalendarLogic.yearCourseOpacity(this.markerCount(day)), this.isDarkMode))
      .clip(true)
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

  private yearDeadlinePriorities(day: DateParts): CalendarYearDeadlinePriority[] {
    const date: string = StrictDates.formatDateParts(day);
    const assignmentCount: number = (this.model.assignmentDeadlinesByDate.get(date) ?? []).length;
    let schoolCount: number = 0;
    let otherCount: number = 0;
    for (const item of this.model.deadlineItems(date)) {
        if (item.source === PublicDeadlineSource.schoolNotice) {
          schoolCount++;
        } else {
          otherCount++;
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

  private presentAllDayDialog(day: DateParts, mode: CalendarMode): void {
    this.setSelectedDate(day);
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
              (item: ExpandedAllDayItem) => {
                Row({ space: 6 }) {
                  Text(item.title)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(item.tint)
                    .maxLines(2)
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
                      this.model.toggleFavoriteDeadline(item.deadlineItem as PublicDeadlineItem)
                        .catch(() => {
                          this.model.statusMessage = '无法保存收藏';
                        });
                    })
                  }
                }
                .width('100%')
                .padding({ left: 10, right: 6, top: 5, bottom: 5 })
                .borderRadius(6)
                .backgroundColor(item.fill)
                .alignItems(VerticalAlign.Center)
              }, (item: ExpandedAllDayItem) => 'wide-all-day-dialog.' + mode + '.' + item.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .constraintSize({ maxHeight: 360 })
        .width('100%')
      }
      .padding(16)
      .width(360)
      .constraintSize({ maxHeight: 440 })
      .borderRadius(10)
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
        Text(CalendarFormatters.fullDate(this.presentedDay as DateParts, this.isEnglish()))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
        Scroll() {
          Column({ space: 10 }) {
            this.daySummaryCard(this.presentedDay as DateParts)
            CalendarDailyInfoCards({ day: this.presentedDay as DateParts })
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 320 })
        .width('100%')
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
      .translate({ x: '-50%' })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  daySummaryCard(day: DateParts) {
    Column({ space: 8 }) {
      Text(CalendarFormatters.fullDate(day, this.isEnglish()))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      ForEach(this.holidayItemsOn(day), (item: HolidayItem) => {
        Text(this.model.text(item.type === 'holiday' ? '休' : '班') + ' ' + item.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(item.type === 'holiday' ? AppTheme.holiday() : AppTheme.primary())
      }, (item: HolidayItem) => 'summary-holiday.' + item.id())
      if (this.coursesOn(day).length === 0) {
        Text(this.model.text('暂无课程'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else {
        ForEach(this.coursesOn(day), (course: Course, index: number) => {
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
              Text(CalendarTimelineLogic.courseMetadata(course)
                .replace('教师：', this.model.text('教师：')))
                .fontSize(11)
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
    .padding({ top: 4 })
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

class ExpandedAllDayItem {
  readonly id: string;
  readonly title: string;
  readonly tint: ResourceColor;
  readonly fill: ResourceColor;
  readonly deadlineItem: PublicDeadlineItem | null;

  constructor(id: string, title: string, tint: ResourceColor, fill: ResourceColor,
    deadlineItem: PublicDeadlineItem | null = null) {
    this.id = id;
    this.title = title;
    this.tint = tint;
    this.fill = fill;
    this.deadlineItem = deadlineItem;
  }
}

// 主题主色与背景的混色（对应 Android UiSupport.kt blend(primary, background, amount)）：
// 深浅色分别用 app_primary / app_background 的十六进制计算不透明结果。
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
