// 移动端日历时间线，对应 iOS 端 MobileCalendarTimelineView.swift。
// 08:00–22:00，每小时 72vp，共 1008vp；左侧小时轴 + 网格线 + 课程块 +
// 当前时间红线。用普通组件定位代替 Canvas，避免画布 API 的平台差异。
import { Course, SlotMetadata } from '../../common/Models';
import { DateParts, StrictDates } from '../../common/StrictDates';
import { AppTheme } from '../../common/AppTheme';
import { CalendarFormatters, CalendarTimelineDay, CalendarTimelineLogic } from './CalendarLogic';

export class MobileCalendarTimelineLayout {
  static readonly startMinute: number = 8 * 60;
  static readonly endMinute: number = 22 * 60;
  static readonly hourHeight: number = 72;
  static readonly axisWidth: number = 56;
  static readonly bottomContentInset: number = 104;
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
    if (!includesToday) {
      return 8;
    }
    return Math.min(Math.max(currentHour - 1, 8), 20);
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
  @Param days: CalendarTimelineDay[] = [];
  @Param selectedDate: DateParts = StrictDates.todayParts();
  @Param showsWeekColumns: boolean = false;
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
    return this.viewportWidth / this.dayCount();
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
    Stack({ alignContent: Alignment.TopStart }) {
      // 小时轴
      Column() {
        ForEach(this.hours, (hour: number) => {
          Text(CalendarFormatters.hourLabel(hour))
            .fontSize(11)
            .fontColor(AppTheme.secondaryText())
            .width(MobileCalendarTimelineLayout.axisWidth - 8)
            .textAlign(TextAlign.End)
            .position({
              x: 0,
              y: MobileCalendarTimelineLayout.yPosition(hour * 60) + this.adjustedHourLabelY(hour)
            })
        }, (hour: number) => 'hour-label.' + hour.toString())
      }
      .width(MobileCalendarTimelineLayout.axisWidth)
      .height(MobileCalendarTimelineLayout.timelineHeight)
      .alignItems(HorizontalAlign.Start)

      // 右侧网格视口
      Stack({ alignContent: Alignment.TopStart }) {
        // 小时线
        ForEach(this.hours, (hour: number) => {
          Divider()
            .strokeWidth(1)
            .color(AppTheme.border())
            .width(this.viewportWidth)
            .position({ x: 0, y: MobileCalendarTimelineLayout.yPosition(hour * 60) })
        }, (hour: number) => 'grid-hour.' + hour.toString())

        // 非整点节次边界线（iOS 为虚线，这里用细实线近似）
        ForEach(CalendarTimelineLogic.nonHourlyCourseBoundaryMinutes(), (minute: number) => {
          Divider()
            .strokeWidth(0.7)
            .color(AppTheme.border())
            .opacity(0.24)
            .width(this.viewportWidth)
            .position({ x: 0, y: MobileCalendarTimelineLayout.yPosition(minute) })
        }, (minute: number) => 'grid-slot.' + minute.toString())

        // 周视图列分隔线
        if (this.showsWeekColumns) {
          ForEach(this.days, (day: CalendarTimelineDay, index: number) => {
            Divider()
              .vertical(true)
              .strokeWidth(1)
              .color(AppTheme.border())
              .opacity(0.7)
              .height(MobileCalendarTimelineLayout.timelineHeight)
              .position({ x: index * this.dayWidthValue(), y: 0 })
          }, (day: CalendarTimelineDay) => 'grid-column.' + this.dayKey(day))
        }

        // 选中列高亮
        if (this.showsWeekColumns) {
          ForEach(this.days, (day: CalendarTimelineDay, index: number) => {
            if (day.date.equals(this.selectedDate)) {
              Column()
                .width(this.dayWidthValue())
                .height(MobileCalendarTimelineLayout.timelineHeight)
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
              .height(MobileCalendarTimelineLayout.timelineHeight)
              .backgroundColor(Color.Transparent)
              .position({ x: index * this.dayWidthValue(), y: 0 })
              .onClick(() => {
                this.onSelectDay(day.date);
              })
          }, (day: CalendarTimelineDay) => 'column-click.' + this.dayKey(day))
        }
      }
      .width(this.viewportWidth)
      .height(MobileCalendarTimelineLayout.timelineHeight)
      .position({ x: MobileCalendarTimelineLayout.axisWidth, y: 0 })
      .clip(true)
    }
    .width(this.viewportWidth + MobileCalendarTimelineLayout.axisWidth)
    .height(MobileCalendarTimelineLayout.timelineHeight)
    .backgroundColor(AppTheme.surface())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.viewportWidth = Math.max(Number(newArea.width) - MobileCalendarTimelineLayout.axisWidth, 1);
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

  @Builder
  slotGuide(slot: SlotMetadata) {
    Text('第' + slot.label + '节 ' + slot.start + '-' + slot.end)
      .fontSize(9)
      .fontColor(AppTheme.secondaryText())
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor(AppTheme.surface())
      .border({ width: 0.5, color: AppTheme.border() })
      .position({
        x: 66,
        y: this.slotGuideY(slot)
      })
  }

  private slotGuideY(slot: SlotMetadata): number {
    const startMinute: number = CalendarTimelineLogic.minuteOf(slot.start) ?? 0;
    const endMinute: number = CalendarTimelineLogic.minuteOf(slot.end) ?? 0;
    return (MobileCalendarTimelineLayout.yPosition(startMinute) +
      MobileCalendarTimelineLayout.yPosition(endMinute)) / 2 - 9;
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
      if (this.blockHeight(placement.course) >= 44 &&
        this.courseMetadataOf(placement.course).length > 0) {
        Text(this.courseMetadataOf(placement.course))
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(6)
    .width(this.viewportWidth - 6)
    .height(this.blockHeight(placement.course))
    .borderRadius(6)
    .backgroundColor(AppTheme.primaryFill())
    .position({ x: 3, y: this.blockTop(placement.course) })
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
        Text(placement.course.room.length === 0 ? '地点未标注' : placement.course.room)
          .fontSize(10)
          .fontColor(AppTheme.onPrimary())
          .maxLines(3)
        Text(placement.course.teacher.length === 0 ? '教师未标注' : '教师：' + placement.course.teacher)
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
    return MobileCalendarTimelineLayout.yPosition(this.blockStartMinute(course)) + 2;
  }

  private blockHeight(course: Course): number {
    const top: number = this.blockTop(course);
    const bottom: number = Math.max(top + 38,
      MobileCalendarTimelineLayout.yPosition(this.blockEndMinute(course)) - 2);
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
        .color(AppTheme.danger())
        .width(this.indicatorWidth())
        .position({ x: this.indicatorLeft(), y: 0 })
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(AppTheme.danger())
        .position({ x: this.indicatorLeft(), y: -3 })
      if (!this.showsWeekColumns) {
        Text(this.timeLabel())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.onPrimary())
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(9)
          .backgroundColor(AppTheme.danger())
          .position({ x: this.indicatorLeft() + 26, y: -15 })
      }
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
    return MobileCalendarTimelineLayout.yPosition(this.shanghaiMinuteOfDay());
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

  private dayKey(day: CalendarTimelineDay): string {
    return StrictDates.formatDateParts(day.date);
  }
}
