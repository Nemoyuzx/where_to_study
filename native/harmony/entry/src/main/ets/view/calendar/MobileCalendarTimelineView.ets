// 移动端日历时间线，以原生 Android CalendarTimelineView.kt 为基准。
// 08:00–22:00，每小时 72vp，共 1008vp；左侧小时轴 + 网格线 + 课程块 +
// 当前时间红线。用普通组件定位代替 Canvas，避免画布 API 的平台差异。
import { Course, SlotMetadata } from '../../common/Models';
import { DateParts, StrictDates } from '../../common/StrictDates';
import { AppTheme } from '../../common/AppTheme';
import { AppModel } from '../../model/AppModel';
import { CalendarFormatters, CalendarTimelineDay, CalendarTimelineLogic } from './CalendarLogic';

export class MobileCalendarTimelineLayout {
  static readonly startMinute: number = 8 * 60;
  static readonly endMinute: number = 22 * 60;
  static readonly hourHeight: number = 72;
  static readonly axisWidth: number = 48;
  static readonly bottomContentInset: number = 84;
  static readonly timelineHeight: number =
    (MobileCalendarTimelineLayout.endMinute - MobileCalendarTimelineLayout.startMinute) / 60 *
    MobileCalendarTimelineLayout.hourHeight;

  static hours(): number[] {
    const result: number[] = [];
    for (let hour = 8; hour <= 22; hour++) {
      result.push(hour);
    }
    return result;
  }

  static yPosition(minute: number): number {
    const clamped: number = Math.min(Math.max(minute, MobileCalendarTimelineLayout.startMinute),
      MobileCalendarTimelineLayout.endMinute);
    return (clamped - MobileCalendarTimelineLayout.startMinute) / 60 *
      MobileCalendarTimelineLayout.hourHeight;
  }

  static initialVisibleHour(currentHour: number, includesToday: boolean): number {
    return 8;
  }
}

export class CoursePlacement {
  readonly course: Course;
  readonly track: number;

  constructor(course: Course, track: number) {
    this.course = course;
    this.track = track;
  }
}

@ComponentV2
export struct MobileCalendarTimelineView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param days: CalendarTimelineDay[] = [];
  @Param selectedDate: DateParts = StrictDates.todayParts();
  @Param showsWeekColumns: boolean = false;
  // 宽屏（平板/PC）形态：与 Android CalendarTimelineView 的 expanded 参数对应。
  // 宽屏显示日头行（72vp）、课程节次轴、小时高、最小日宽。
  @Param expanded: boolean = false;
  // PC（2in1）使用 Windows Tauri 数值（轴 52+104、时高 64、最小日宽 118）；
  // 平板/折叠屏使用 Android 数值（轴 48+96、时高 68、最小日宽 156）。
  @Param tauri: boolean = false;
  // 各天课程布局缓存（BUG-046 修复）：由父组件在构造 days 时一次算好。
  @Param placements: Map<string, CoursePlacement[]> = new Map<string, CoursePlacement[]>();
  @Event onSelectDay: (day: DateParts) => void = () => {
  };
  @Local nowEpochMs: number = Date.now();
  @Local viewportWidth: number = 300;
  private scroller: Scroller = new Scroller();
  private timerId: number = -1;
  private viewVisible: boolean = true;
  private readonly hours: number[] = MobileCalendarTimelineLayout.hours();

  aboutToAppear(): void {
    this.startTimerIfNeeded();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  // BUG-052 修复：标签页不可见时暂停 30 秒刷新定时器，避免后台空转。
  private startTimerIfNeeded(): void {
    if (this.timerId >= 0 || !this.viewVisible) {
      return;
    }
    this.timerId = setInterval(() => {
      this.nowEpochMs = Date.now();
    }, 30000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private placementsOf(day: CalendarTimelineDay): CoursePlacement[] {
    return this.placements.get(this.dayKey(day)) ?? [];
  }

  private dayCount(): number {
    return Math.max(this.days.length, 1);
  }

  private dayWidthValue(): number {
    return Math.max(this.viewportWidth / this.dayCount(), this.dayWidthMin());
  }

  // 宽屏布局数值（对齐 Android CalendarTimelineLogic 的 expanded 参数）：
  // axisWidth = 48 小时轴 + 96 节次轴；小时高 68；日头高 72；最小日宽 156。
  private axisWidth(): number {
    if (!this.expanded) {
      return MobileCalendarTimelineLayout.axisWidth;
    }
    return this.tauri ? 156 : 144;
  }

  private hourAxisWidth(): number {
    return this.expanded ? (this.tauri ? 52 : 48) : 48;
  }

  private slotAxisWidth(): number {
    if (!this.expanded) {
      return 0;
    }
    return this.tauri ? 104 : 96;
  }

  private hourHeight(): number {
    if (!this.expanded) {
      return MobileCalendarTimelineLayout.hourHeight;
    }
    return this.tauri ? 64 : 68;
  }

  private headerHeight(): number {
    return this.expanded ? 72 : 0;
  }

  private bodyHeight(): number {
    return (MobileCalendarTimelineLayout.endMinute - MobileCalendarTimelineLayout.startMinute) / 60 *
      this.hourHeight();
  }

  private totalHeight(): number {
    return this.headerHeight() + this.bodyHeight();
  }

  private yPos(minute: number): number {
    const clamped: number = Math.min(Math.max(minute, MobileCalendarTimelineLayout.startMinute),
      MobileCalendarTimelineLayout.endMinute);
    return (clamped - MobileCalendarTimelineLayout.startMinute) / 60 * this.hourHeight();
  }

  private dayWidthMin(): number {
    if (!this.expanded) {
      return 0;
    }
    return this.tauri ? 118 : 156;
  }

  private shanghaiMinuteOfDay(): number {
    const shanghaiMs: number = (this.nowEpochMs + 8 * 3600 * 1000) % 86400000;
    return Math.floor(shanghaiMs / 60000);
  }

  private includesToday(): boolean {
    const today: DateParts = StrictDates.todayParts();
    for (const day of this.days) {
      if (day.date.equals(today)) {
        return true;
      }
    }
    return false;
  }

  // 为各天一次计算课程布局（BUG-046 修复）。
  static placementsFor(days: CalendarTimelineDay[]): Map<string, CoursePlacement[]> {
    const result: Map<string, CoursePlacement[]> = new Map<string, CoursePlacement[]>();
    for (const day of days) {
      result.set(StrictDates.formatDateParts(day.date),
        MobileCalendarTimelineView.placeCourses(day.courses));
    }
    return result;
  }

  static placeCourses(courses: Course[]): CoursePlacement[] {
    const sorted: Course[] = courses.slice().sort((lhs: Course, rhs: Course) => {
      if (lhs.startSlot !== rhs.startSlot) {
        return lhs.startSlot - rhs.startSlot;
      }
      if (lhs.endSlot !== rhs.endSlot) {
        return lhs.endSlot - rhs.endSlot;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    const trackEnds: number[] = [];
    const result: CoursePlacement[] = [];
    for (const course of sorted) {
      let track: number = -1;
      for (let i = 0; i < trackEnds.length; i++) {
        if (trackEnds[i] < course.startSlot) {
          track = i;
          break;
        }
      }
      if (track < 0) {
        track = trackEnds.length;
        trackEnds.push(course.endSlot);
      } else {
        trackEnds[track] = course.endSlot;
      }
      result.push(new CoursePlacement(course, track));
    }
    return result;
  }

  build() {
    Column() {
      // 宽屏日头行（对齐 Android expanded 的 72vp day header + Tauri .time-day-head）
      if (this.expanded) {
        this.dayHeaderRow()
      }
      Stack({ alignContent: Alignment.TopStart }) {
        // 小时轴
        Column() {
          ForEach(this.hours, (hour: number) => {
            if (!this.hourLabelObscured(hour)) {
              Text(CalendarFormatters.hourLabel(hour))
                .fontSize(9)
                .fontColor(AppTheme.secondaryText())
                .width(this.hourAxisWidth() - 8)
                .textAlign(TextAlign.Center)
                .position({
                  x: 0,
                  y: this.yPos(hour * 60) + this.adjustedHourLabelY(hour)
                })
            }
          }, (hour: number) => 'hour-label.' + hour.toString())
          if (this.isNowVisible()) {
            Text(this.timeLabel())
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.onPrimary())
              .width(40)
              .height(18)
              .textAlign(TextAlign.Center)
              .borderRadius(9)
              .backgroundColor(AppTheme.nowIndicator())
              .position({ x: 4, y: this.indicatorY() - 9 })
          }
        }
        .width(this.hourAxisWidth())
        .height(this.bodyHeight())
        .alignItems(HorizontalAlign.Start)

        // 宽屏课程节次轴（对应 Android 96vp slot axis / Tauri .slot-time-labels）
        if (this.expanded) {
          ForEach(SlotMetadata.defaults, (slot: SlotMetadata) => {
            this.slotAxisLabel(slot)
          }, (slot: SlotMetadata) => 'slot-axis.' + slot.index.toString())
        }

        // 右侧网格视口
        Stack({ alignContent: Alignment.TopStart }) {
          // 小时线
          ForEach(this.hours, (hour: number) => {
            Divider()
              .strokeWidth(0.5)
              .color(AppTheme.border())
              .width(this.viewportWidth)
              .position({ x: 0, y: this.yPos(hour * 60) })
          }, (hour: number) => 'grid-hour.' + hour.toString())

          // 课程节次边界使用更清晰的虚线，避免在深色模式和周视图窄列中消失。
          ForEach(CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes(), (minute: number) => {
            Column()
              .width(this.viewportWidth)
              .height(2)
              .border({
                width: { top: 1.2 },
                color: AppTheme.border(),
                style: BorderStyle.Dashed
              })
              .opacity(0.56)
              .position({ x: 0, y: this.yPos(minute) })
          }, (minute: number) => 'grid-slot.' + minute.toString())

          // 周视图列分隔线
          if (this.showsWeekColumns) {
            ForEach(this.days, (day: CalendarTimelineDay, index: number) => {
              Divider()
                .vertical(true)
                .strokeWidth(0.5)
                .color(AppTheme.border())
                .opacity(0.7)
                .height(this.bodyHeight())
                .position({ x: index * this.dayWidthValue(), y: 0 })
            }, (day: CalendarTimelineDay) => 'grid-column.' + this.dayKey(day))
          }

          // 选中列高亮
          if (this.showsWeekColumns) {
            ForEach(this.days, (day: CalendarTimelineDay, index: number) => {
              if (day.date.equals(this.selectedDate)) {
                Column()
                  .width(this.dayWidthValue())
                  .height(this.bodyHeight())
                  .backgroundColor('#0B166B5D')
                  .hitTestBehavior(HitTestMode.None)
                  .position({ x: index * this.dayWidthValue(), y: 0 })
              }
            }, (day: CalendarTimelineDay) => 'selected-column.' + this.dayKey(day))
          }

          // 单日模式的节次胶囊
          if (!this.showsWeekColumns) {
            ForEach(SlotMetadata.defaults, (slot: SlotMetadata) => {
              this.slotGuide(slot)
            }, (slot: SlotMetadata) => 'slot-guide.' + slot.index.toString())
          }

          // 课程块
          ForEach(this.days, (day: CalendarTimelineDay, dayIndex: number) => {
            ForEach(this.placementsOf(day), (placement: CoursePlacement) => {
              this.courseBlock(dayIndex, placement)
            }, (placement: CoursePlacement) => this.dayKey(day) + '|' + placement.course.id + '|' +
              placement.track.toString())
          }, (day: CalendarTimelineDay) => 'day-blocks.' + this.dayKey(day))

          // 当前时间指示
          if (this.isNowVisible()) {
            this.currentTimeIndicator()
          }

          // 周视图列点击
          if (this.showsWeekColumns) {
            ForEach(this.days, (day: CalendarTimelineDay, index: number) => {
              Column()
                .width(this.dayWidthValue())
                .height(this.bodyHeight())
                .backgroundColor(Color.Transparent)
                .position({ x: index * this.dayWidthValue(), y: 0 })
                .onClick(() => {
                  this.onSelectDay(day.date);
                })
            }, (day: CalendarTimelineDay) => 'column-click.' + this.dayKey(day))
          }
        }
        .width(this.viewportWidth)
        .height(this.bodyHeight())
        .position({ x: this.axisWidth(), y: 0 })
        .clip(true)
      }
      .width('100%')
      .height(this.bodyHeight())
    }
    .width('100%')
    .height(this.totalHeight())
    .backgroundColor(AppTheme.surface())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.viewportWidth = Math.max(Number(newArea.width) - this.axisWidth(), 1);
    })
    .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number): void => {
      this.viewVisible = isVisible;
      if (isVisible) {
        this.startTimerIfNeeded();
      } else {
        this.stopTimer();
      }
    })
  }

  // 宽屏日头行：左侧角标（整点/课程节次）+ 每天日头（星期 + 月/日 + 课程数）。
  @Builder
  dayHeaderRow() {
    Row({ space: 0 }) {
      Row() {
        Text(this.model.text('整点'))
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
          .textAlign(TextAlign.Center)
          .width(this.hourAxisWidth())
        Text(this.model.text('课程节次'))
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
          .textAlign(TextAlign.Center)
          .width(this.slotAxisWidth())
      }
      .width(this.axisWidth())
      .height(this.headerHeight())
      .justifyContent(FlexAlign.Center)
      .border({ width: { bottom: 1, right: 1 }, color: AppTheme.border() })

      ForEach(this.days, (day: CalendarTimelineDay, index: number) => {
        Column({ space: 3 }) {
          Row({ space: 4 }) {
            Text(CalendarFormatters.weekdayLabels[StrictDates.weekdayMonday1(day.date) - 1])
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
            Text(day.date.month.toString() + '/' + day.date.day.toString())
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
          }
          Text(this.model.text(day.courses.length === 0 ? '无课程' :
            day.courses.length.toString() + ' 门课'))
            .fontSize(10)
            .fontColor(day.courses.length > 0 ? AppTheme.primary() : AppTheme.secondaryText())
            .maxLines(1)
          // 今日红条：日头底部 3vp systemRed 横条（对应 Tauri inset 0 -3px 0 #FF3B30）。
          if (day.date.equals(StrictDates.todayParts())) {
            Column()
              .width('100%')
              .height(3)
              .backgroundColor(AppTheme.nowIndicator())
              .position({ x: 0, y: this.headerHeight() - 3 })
          }
        }
        .width(this.dayWidthValue())
        .height(this.headerHeight())
        .justifyContent(FlexAlign.Center)
        .border({ width: { left: 1, bottom: 1 }, color: AppTheme.border() })
        .backgroundColor(day.date.equals(this.selectedDate) ? '#0B166B5D' : AppTheme.surface())
        .onClick(() => {
          this.onSelectDay(day.date);
        })
      }, (day: CalendarTimelineDay) => 'day-head.' + this.dayKey(day))
    }
    .width('100%')
    .height(this.headerHeight())
  }

  // 宽屏课程节次轴标签：第 N 节（bold）+ 起止时间。
  @Builder
  slotAxisLabel(slot: SlotMetadata) {
    Column({ space: 1 }) {
      Text(this.model.text('第' + slot.label + '节'))
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.secondaryText())
        .maxLines(1)
      Text(slot.start + '-' + slot.end)
        .fontSize(9)
        .fontColor(AppTheme.secondaryText())
        .maxLines(1)
    }
    .width(this.slotAxisWidth())
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.hourAxisWidth(), y: this.slotAxisCenterY(slot) })
  }

  private slotAxisCenterY(slot: SlotMetadata): number {
    const startMinute: number = CalendarTimelineLogic.minuteOf(slot.start) ?? 0;
    const endMinute: number = CalendarTimelineLogic.minuteOf(slot.end) ?? 0;
    return (this.yPos(startMinute) + this.yPos(endMinute)) / 2 - 10;
  }

  @Builder
  slotGuide(slot: SlotMetadata) {
    Text(this.model.text('第' + slot.label + '节') + ' ' + slot.start + '-' + slot.end)
      .fontSize(9)
      .fontColor(AppTheme.secondaryText())
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor(AppTheme.surface())
      .border({ width: 0.5, color: AppTheme.border() })
      .position({
        x: 8,
        y: this.slotGuideY(slot)
      })
  }

  private slotGuideY(slot: SlotMetadata): number {
    const startMinute: number = CalendarTimelineLogic.minuteOf(slot.start) ?? 0;
    const endMinute: number = CalendarTimelineLogic.minuteOf(slot.end) ?? 0;
    return (this.yPos(startMinute) + this.yPos(endMinute)) / 2 - 9;
  }

  @Builder
  courseBlock(dayIndex: number, placement: CoursePlacement) {
    if (this.showsWeekColumns) {
      this.courseBlockForWeek(dayIndex, placement)
    } else {
      this.courseBlockForDay(dayIndex, placement)
    }
  }

  @Builder
  courseBlockForDay(dayIndex: number, placement: CoursePlacement) {
    Column({ space: 2 }) {
      Text(placement.course.name)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.onPrimary())
        .maxLines(1)
      if (this.blockHeight(placement.course) >= 38) {
        Text(placement.course.timeRange)
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(1)
      }
      if (this.blockHeight(placement.course) >= 60) {
        Text(placement.course.room)
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(1)
      }
      if (this.blockHeight(placement.course) >= 76 && placement.course.teacher.length > 0) {
        Text(placement.course.teacher)
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(6)
    .width(this.blockDayWidth(dayIndex, placement))
    .height(this.blockHeight(placement.course))
    .borderRadius(6)
    .border({ width: { left: 3 }, color: AppTheme.accent() })
    .backgroundColor(AppTheme.primaryFill())
    .position({ x: this.blockDayX(dayIndex, placement), y: this.blockTop(placement.course) })
  }

  @Builder
  courseBlockForWeek(dayIndex: number, placement: CoursePlacement) {
    Column({ space: 1 }) {
      Text(placement.course.name)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.onPrimary())
        .maxLines(3)
      if (this.blockHeight(placement.course) >= 38) {
        Text(placement.course.timeRange)
          .fontSize(8)
          .fontColor(AppTheme.onPrimary())
          .maxLines(2)
      }
      if (this.blockHeight(placement.course) >= 48) {
        Text(placement.course.room.length === 0 ? this.model.text('地点未标注') :
          placement.course.room)
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(3)
        Text(placement.course.teacher.length === 0 ? this.model.text('教师未标注') :
          this.model.text('教师：') + placement.course.teacher)
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(3)
      } else if (this.blockHeight(placement.course) >= 44 &&
        this.courseMetadataOf(placement.course).length > 0) {
        Text(this.courseMetadataOf(placement.course))
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(5)
    .width(this.blockWeekWidth(dayIndex, placement))
    .height(this.blockHeight(placement.course))
    .borderRadius(6)
    .border({ width: { left: 3 }, color: AppTheme.accent() })
    .backgroundColor(AppTheme.primaryFill())
    .position({
      x: this.blockWeekX(dayIndex, placement),
      y: this.blockTop(placement.course)
    })
  }

  private blockStartMinute(course: Course): number {
    return CalendarTimelineLogic.minuteOf(
      SlotMetadata.defaults[course.startSlot].start) ?? 0;
  }

  private blockEndMinute(course: Course): number {
    return CalendarTimelineLogic.minuteOf(
      SlotMetadata.defaults[course.endSlot].end) ?? 0;
  }

  private blockTop(course: Course): number {
    return this.yPos(this.blockStartMinute(course)) + 2;
  }

  private blockHeight(course: Course): number {
    const top: number = this.blockTop(course);
    const bottom: number = Math.max(top + 38,
      this.yPos(this.blockEndMinute(course)) - 2);
    return bottom - top;
  }

  private courseMetadataOf(course: Course): string {
    return CalendarTimelineLogic.courseMetadata(course);
  }

  private blockTrackCount(dayIndex: number): number {
    const placements: CoursePlacement[] = this.placementsOf(this.days[dayIndex]);
    let trackCount: number = 1;
    for (const item of placements) {
      if (item.track + 1 > trackCount) {
        trackCount = item.track + 1;
      }
    }
    return trackCount;
  }

  private blockTrackWidth(dayIndex: number): number {
    return this.dayWidthValue() / this.blockTrackCount(dayIndex);
  }

  private blockDayWidth(dayIndex: number, placement: CoursePlacement): number {
    return Math.max(this.blockTrackWidth(dayIndex) - 6, 8);
  }

  private blockDayX(dayIndex: number, placement: CoursePlacement): number {
    return dayIndex * this.dayWidthValue() +
      placement.track * this.blockTrackWidth(dayIndex) + 3;
  }

  private blockWeekWidth(dayIndex: number, placement: CoursePlacement): number {
    return Math.max(this.blockTrackWidth(dayIndex) - 2, 8);
  }

  private blockWeekX(dayIndex: number, placement: CoursePlacement): number {
    return dayIndex * this.dayWidthValue() +
      placement.track * this.blockTrackWidth(dayIndex) + 1;
  }

  @Builder
  currentTimeIndicator() {
    Column() {
      Divider()
        .strokeWidth(2)
        .color(AppTheme.nowIndicator())
        .width(this.indicatorWidth())
        .position({ x: this.indicatorLeft(), y: 0 })
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(AppTheme.nowIndicator())
        .position({ x: this.indicatorLeft(), y: -3 })
    }
    .width(this.viewportWidth)
    .height(2)
    .position({ x: 0, y: this.indicatorY() })
    .hitTestBehavior(HitTestMode.None)
  }

  private indicatorLeft(): number {
    if (!this.showsWeekColumns) {
      return 0;
    }
    const today: DateParts = StrictDates.todayParts();
    for (let i = 0; i < this.days.length; i++) {
      if (this.days[i].date.equals(today)) {
        return i * this.dayWidthValue();
      }
    }
    return 0;
  }

  private indicatorWidth(): number {
    return this.showsWeekColumns ? this.dayWidthValue() : this.viewportWidth;
  }

  private indicatorY(): number {
    return this.yPos(this.shanghaiMinuteOfDay());
  }

  private isNowVisible(): boolean {
    const minute: number = this.shanghaiMinuteOfDay();
    if (minute < MobileCalendarTimelineLayout.startMinute ||
      minute > MobileCalendarTimelineLayout.endMinute) {
      return false;
    }
    return this.includesToday();
  }

  private timeLabel(): string {
    const minute: number = this.shanghaiMinuteOfDay();
    const hour: number = Math.floor(minute / 60);
    const rest: number = minute % 60;
    return (hour < 10 ? '0' + hour.toString() : hour.toString()) + ':' +
      (rest < 10 ? '0' + rest.toString() : rest.toString());
  }

  private adjustedHourLabelY(hour: number): number {
    if (hour === 8) {
      return 8;
    }
    if (hour === 22) {
      return -8;
    }
    return 0;
  }

  private hourLabelObscured(hour: number): boolean {
    if (!this.isNowVisible()) {
      return false;
    }
    return Math.abs(hour * 60 - this.shanghaiMinuteOfDay()) <= 12;
  }

  private dayKey(day: CalendarTimelineDay): string {
    return StrictDates.formatDateParts(day.date);
  }
}
