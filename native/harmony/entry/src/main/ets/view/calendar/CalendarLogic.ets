// 教学日历的纯逻辑与时间线布局，以原生 Android 实现为移动端基准。
// TeachingCalendarLogic / CalendarTimelineLogic / CalendarTimelineDay。
import { mediaquery } from '@kit.ArkUI';
import { Course, HolidayItem, SlotMetadata } from '../../common/Models';
import { StrictDates, DateParts } from '../../common/StrictDates';

// 深色模式探测：Android Palette 按 uiMode 取色，月/年课程填充色需要在代码里
// 完成混色（对应 UiSupport.kt blend(primary, background, opacity)），
// 无法仅靠资源色，因此需要感知当前深浅色模式。
export class DarkModeProbe {
  private listener: mediaquery.MediaQueryListener | null = null;

  register(callback: (dark: boolean) => void): void {
    this.unregister();
    this.listener = mediaquery.matchMediaSync('(dark-mode: true)');
    callback(this.listener.matches);
    this.listener.on('change', (result: mediaquery.MediaQueryResult) => {
      callback(result.matches);
    });
  }

  unregister(): void {
    if (this.listener !== null) {
      this.listener.off('change');
      this.listener = null;
    }
  }
}

export enum CalendarMode {
  day = '日',
  week = '周',
  month = '月',
  year = '年'
}

// 手势起步后锁定主轴，避免横向翻月在手指轻微偏移时
// 被月视图纵向三档展开手势中途抢占。
export enum CalendarGestureAxis {
  horizontal = 'horizontal',
  vertical = 'vertical'
}

// 月/年视图用至多两层同心边框表达 DDL 类型，课程数量仍由格子底色表达。
// 多个来源落在同一天时保持 assignment > school notice > other 的稳定优先级。
export enum CalendarYearDeadlinePriority {
  none = 'none',
  other = 'other',
  schoolNotice = 'school_notice',
  assignment = 'assignment'
}

export class CalendarModeInfo {
  static readonly all: CalendarMode[] = [
    CalendarMode.day, CalendarMode.week, CalendarMode.month, CalendarMode.year
  ];

  static fromRawValue(rawValue: string): CalendarMode {
    if (rawValue === CalendarMode.day) {
      return CalendarMode.day;
    }
    if (rawValue === CalendarMode.month) {
      return CalendarMode.month;
    }
    if (rawValue === CalendarMode.year) {
      return CalendarMode.year;
    }
    return CalendarMode.week;
  }
}

export class CalendarTimelineDay {
  readonly date: DateParts;
  readonly courses: Course[];
  readonly holidays: HolidayItem[];

  constructor(date: DateParts, courses: Course[], holidays: HolidayItem[]) {
    this.date = date;
    this.courses = courses;
    this.holidays = holidays;
  }
}

export class CalendarTimelineLogic {
  static readonly startMinute: number = 8 * 60;
  static readonly endMinute: number = 22 * 60;

  static minuteOf(value: string): number | null {
    const parts: string[] = value.split(':');
    if (parts.length !== 2) {
      return null;
    }
    const hour: number = Number(parts[0]);
    const minute: number = Number(parts[1]);
    if (Number.isNaN(hour) || Number.isNaN(minute) || hour < 0 || hour > 23 ||
      minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static position(minute: number): number {
    const raw: number = (minute - CalendarTimelineLogic.startMinute) /
      (CalendarTimelineLogic.endMinute - CalendarTimelineLogic.startMinute);
    return Math.min(Math.max(raw, 0), 1);
  }

  static courseBoundaryMinutes(): number[] {
    const seen: Set<number> = new Set<number>();
    for (const slot of SlotMetadata.defaults) {
      const start: number | null = CalendarTimelineLogic.minuteOf(slot.start);
      const end: number | null = CalendarTimelineLogic.minuteOf(slot.end);
      if (start !== null) {
        seen.add(start);
      }
      if (end !== null) {
        seen.add(end);
      }
    }
    const result: number[] = [];
    for (const value of seen) {
      result.push(value);
    }
    result.sort((a: number, b: number) => a - b);
    return result;
  }

  static nonHourlyCourseBoundaryMinutes(): number[] {
    const result: number[] = [];
    for (const value of CalendarTimelineLogic.courseBoundaryMinutes()) {
      if (value % 60 !== 0) {
        result.push(value);
      }
    }
    return result;
  }

  static courseMetadata(course: Course): string {
    const parts: string[] = [];
    if (course.room.length > 0) {
      parts.push(course.room);
    }
    if (course.teacher.length > 0) {
      parts.push('教师：' + course.teacher);
    }
    return parts.join(' · ');
  }
}

export class TeachingCalendarLogic {
  static mobilePageIdentity(mode: CalendarMode, date: DateParts): string {
    if (mode === CalendarMode.year) {
      return mode + '.' + date.year.toString();
    }
    const dateKey: string = StrictDates.formatDateParts(date);
    return mode + '.' + (mode === CalendarMode.month ? dateKey.substring(0, 7) : dateKey);
  }

  static monthWeekIndex(date: DateParts): number {
    const first: DateParts = new DateParts(date.year, date.month, 1);
    return Math.floor((StrictDates.weekdayMonday1(first) - 1 + date.day - 1) / 7);
  }

  static readonly pageTransitionDuration: number = 300;
  static readonly swipeThreshold: number = 72;
  static readonly expansionVelocityThreshold: number = 640;
  static readonly monthSheetExpandedPosition: number = 0;
  static readonly monthSheetDetailsPosition: number = 1;
  static readonly monthSheetWeekPosition: number = 2;
  static readonly monthExpandedCellHeight: number = 82;
  static readonly monthCollapsedCellHeight: number = 46;

  static modeTransitionDirection(fromMode: CalendarMode, toMode: CalendarMode): number {
    const fromIndex: number = CalendarModeInfo.all.indexOf(fromMode);
    const toIndex: number = CalendarModeInfo.all.indexOf(toMode);
    if (toIndex > fromIndex) {
      return 1;
    }
    if (toIndex < fromIndex) {
      return -1;
    }
    return 0;
  }

  static showsCompactDateStrip(mode: CalendarMode): boolean {
    return mode === CalendarMode.day || mode === CalendarMode.week;
  }

  static showsCompactWeekAxis(mode: CalendarMode): boolean {
    return mode === CalendarMode.week;
  }

  static pageTransitionOffsets(direction: number, distance: number): CalendarPageTransitionOffsets {
    const resolvedDirection: number = Math.sign(direction);
    const resolvedDistance: number = Math.abs(distance);
    return new CalendarPageTransitionOffsets(
      resolvedDirection * resolvedDistance,
      -resolvedDirection * resolvedDistance);
  }

  static yearCourseOpacity(courseCount: number): number {
    if (courseCount <= 0) {
      return 0;
    }
    const count: number = courseCount;
    return 0.12 + 0.72 * count / (count + 3);
  }

  static yearDeadlinePriority(assignmentCount: number, schoolNoticeCount: number,
    otherDeadlineCount: number): CalendarYearDeadlinePriority {
    const priorities: CalendarYearDeadlinePriority[] =
      TeachingCalendarLogic.yearDeadlineBorderLayers(
        assignmentCount, schoolNoticeCount, otherDeadlineCount);
    return priorities.length > 0 ? priorities[0] : CalendarYearDeadlinePriority.none;
  }

  static yearDeadlineBorderLayers(assignmentCount: number, schoolNoticeCount: number,
    otherDeadlineCount: number): CalendarYearDeadlinePriority[] {
    const result: CalendarYearDeadlinePriority[] = [];
    if (assignmentCount > 0) {
      result.push(CalendarYearDeadlinePriority.assignment);
    }
    if (schoolNoticeCount > 0 && result.length < 2) {
      result.push(CalendarYearDeadlinePriority.schoolNotice);
    }
    if (otherDeadlineCount > 0 && result.length < 2) {
      result.push(CalendarYearDeadlinePriority.other);
    }
    return result;
  }

  static allDayDialogTitle(mode: CalendarMode, english: boolean): string {
    if (english) {
      if (mode === CalendarMode.day) {
        return 'Day View · All-day';
      }
      if (mode === CalendarMode.month) {
        return 'Month View · All-day';
      }
      return 'Week View · All-day';
    }
    return mode + '视图 · 全天';
  }

  static showsTodayMarker(isToday: boolean): boolean {
    return isToday;
  }

  static timelineCourseSummaryDate(mode: CalendarMode, selectedDate: DateParts): DateParts {
    // 手机日/周共用一个课程折叠区；mode 只决定下方时间线的列数。
    return selectedDate;
  }

  static timelineAgendaSortOrder(category: string): number {
    if (category === 'holiday' || category === 'workday') {
      return 0;
    }
    if (category === 'assignment') {
      return 1;
    }
    if (category === 'school_notice') {
      return 2;
    }
    return 3;
  }

  static agendaDialogChangesSelectedDate(mode: CalendarMode): boolean {
    return mode === CalendarMode.day;
  }

  static supportsAllDayDialog(mode: CalendarMode): boolean {
    return mode === CalendarMode.day || mode === CalendarMode.week;
  }

  static expandedMonthGridShowsChip(kind: string): boolean {
    return kind === 'course';
  }

  static allDayTimeLabel(value: string, allDayLabel: string = '全天'): string {
    if (value.length >= 16 && (value.charAt(10) === 'T' || value.charAt(10) === ' ')) {
      return value.substring(11, 16);
    }
    return allDayLabel;
  }

  static allDayCardAction(linkURL: string | null): string {
    return linkURL !== null && linkURL.length > 0 ? 'link' : 'details';
  }

  static expandedYearDetailScrollHeight(viewportHeight: number): number {
    return Math.min(Math.max(Math.floor(viewportHeight * 0.52), 240), 420);
  }

  static expandedYearDetailPanelHeight(viewportHeight: number): number {
    const availableHeight: number = Math.max(Math.floor(viewportHeight) - 32, 0);
    const desiredHeight: number =
      TeachingCalendarLogic.expandedYearDetailScrollHeight(viewportHeight) + 108;
    return Math.min(desiredHeight, availableHeight);
  }

  static expandedYearDetailPosition(anchorX: number, anchorY: number,
    viewportWidth: number, viewportHeight: number, panelWidth: number,
    panelHeight: number, margin: number = 16, gap: number = 10): CalendarPopoverPosition {
    const maximumX: number = Math.max(viewportWidth - panelWidth - margin, margin);
    const x: number = Math.min(Math.max(anchorX - panelWidth / 2, margin), maximumX);
    const below: number = anchorY + gap;
    const above: number = anchorY - panelHeight - gap;
    const preferredY: number = below + panelHeight <= viewportHeight - margin ? below : above;
    const maximumY: number = Math.max(viewportHeight - panelHeight - margin, margin);
    const y: number = Math.min(Math.max(preferredY, margin), maximumY);
    return new CalendarPopoverPosition(x, y);
  }

  static periodTitle(date: DateParts, mode: CalendarMode, english: boolean = false): string {
    if (english) {
      if (mode === CalendarMode.day) {
        return CalendarFormatters.englishMonth(date.month) + ' ' + date.day.toString() + ', ' +
          date.year.toString();
      }
      if (mode === CalendarMode.week) {
        return CalendarFormatters.englishMonth(date.month) + ' ' + date.year.toString();
      }
      if (mode === CalendarMode.year) {
        return date.year.toString();
      }
      return CalendarFormatters.englishMonth(date.month) + ' ' + date.year.toString();
    }
    if (mode === CalendarMode.day) {
      return date.year.toString() + '年' + date.month.toString() + '月' + date.day.toString() + '日';
    }
    if (mode === CalendarMode.week) {
      return date.year.toString() + '年' + date.month.toString() + '月';
    }
    if (mode === CalendarMode.year) {
      return date.year.toString() + '年';
    }
    return date.year.toString() + '年' + date.month.toString() + '月';
  }

  static movedDate(date: DateParts, mode: CalendarMode, direction: number): DateParts {
    if (mode === CalendarMode.day) {
      return StrictDates.addDays(date, direction);
    }
    if (mode === CalendarMode.week) {
      return StrictDates.addDays(date, direction * 7);
    }
    if (mode === CalendarMode.month) {
      return TeachingCalendarLogic.addMonths(date, direction);
    }
    // 年视图：2 月 29 日跨年时按目标年钳制，避免产生非法日期（BUG-048 修复）。
    const nextYear: number = date.year + direction;
    return new DateParts(nextYear, date.month,
      Math.min(date.day, StrictDates.daysInMonth(nextYear, date.month)));
  }

  static addMonths(date: DateParts, direction: number,
    preferredDayOfMonth: number = date.day): DateParts {
    const zeroBased: number = date.month - 1 + direction;
    const year: number = date.year + Math.floor(zeroBased / 12);
    let month: number = zeroBased % 12;
    if (month < 0) {
      month += 12;
    }
    const maxDay: number = StrictDates.daysInMonth(year, month + 1);
    const day: number = Math.min(Math.max(Math.floor(preferredDayOfMonth), 1), maxDay);
    return new DateParts(year, month + 1, day);
  }

  static swipeDirection(
    horizontal: number, vertical: number, predictedHorizontal: number
  ): number | null {
    const projected: number = Math.abs(predictedHorizontal) > Math.abs(horizontal) ?
      predictedHorizontal : horizontal;
    if (Math.abs(horizontal) < TeachingCalendarLogic.swipeThreshold ||
      Math.abs(projected) < TeachingCalendarLogic.swipeThreshold ||
      Math.abs(horizontal) <= Math.abs(vertical) * 1.4) {
      return null;
    }
    return projected < 0 ? 1 : -1;
  }

  static gestureAxis(horizontal: number, vertical: number,
    activationDistance: number = 8): CalendarGestureAxis | null {
    const horizontalDistance: number = Math.abs(horizontal);
    const verticalDistance: number = Math.abs(vertical);
    if (Math.max(horizontalDistance, verticalDistance) < activationDistance) {
      return null;
    }
    return horizontalDistance > verticalDistance ?
      CalendarGestureAxis.horizontal : CalendarGestureAxis.vertical;
  }

  static monthExpansionAction(horizontal: number, vertical: number): number | null {
    // 返回 1 = expand，-1 = collapse，null = 无动作。
    if (Math.abs(vertical) < 44 || Math.abs(vertical) < Math.abs(horizontal) * 1.25) {
      return null;
    }
    return vertical > 0 ? 1 : -1;
  }

  static monthHandleTargetPosition(position: number): number {
    const rounded: number = Math.round(
      TeachingCalendarLogic.clampMonthSheetPosition(position));
    if (rounded === TeachingCalendarLogic.monthSheetExpandedPosition) {
      return TeachingCalendarLogic.monthSheetDetailsPosition;
    }
    if (rounded === TeachingCalendarLogic.monthSheetDetailsPosition) {
      return TeachingCalendarLogic.monthSheetExpandedPosition;
    }
    return TeachingCalendarLogic.monthSheetDetailsPosition;
  }

  static monthDaySelectionTargetPosition(): number {
    return TeachingCalendarLogic.monthSheetDetailsPosition;
  }

  static monthDetailsCanScrollAtGestureStart(position: number): boolean {
    return TeachingCalendarLogic.clampMonthSheetPosition(position) >=
      TeachingCalendarLogic.monthSheetWeekPosition - 0.001;
  }

  static canMoveMonthSheet(horizontal: number, vertical: number,
    currentPosition: number, threshold: number = 6): boolean {
    if (Math.abs(vertical) < threshold || Math.abs(vertical) <= Math.abs(horizontal) * 1.2) {
      return false;
    }
    if (vertical < 0) {
      return currentPosition < TeachingCalendarLogic.monthSheetWeekPosition;
    }
    if (vertical > 0) {
      return currentPosition > TeachingCalendarLogic.monthSheetExpandedPosition;
    }
    return false;
  }

  static monthSheetOwnsGesture(vertical: number, currentPosition: number,
    detailsAtTopAtGestureStart: boolean): boolean {
    if (vertical < 0) {
      // 中间档先收窄到选中周；已到第三档后交给详情列表滚动。
      return currentPosition < TeachingCalendarLogic.monthSheetWeekPosition;
    }
    if (vertical > 0) {
      // 手势开始时详情未到顶，整次手势均归列表；不在中途抢占。
      return currentPosition > TeachingCalendarLogic.monthSheetExpandedPosition &&
        detailsAtTopAtGestureStart;
    }
    return false;
  }

  static monthSheetDragPosition(vertical: number, startPosition: number,
    travel: number = (TeachingCalendarLogic.monthExpandedCellHeight -
      TeachingCalendarLogic.monthCollapsedCellHeight) * 6): number {
    if (travel <= 0) {
      return TeachingCalendarLogic.clampMonthSheetPosition(startPosition);
    }
    return TeachingCalendarLogic.clampMonthSheetPosition(startPosition - vertical / travel);
  }

  static settledMonthSheetPosition(position: number, velocityY: number): number {
    const resolved: number = TeachingCalendarLogic.clampMonthSheetPosition(position);
    if (Math.abs(velocityY) >= TeachingCalendarLogic.expansionVelocityThreshold) {
      if (velocityY < 0) {
        return Math.min(Math.floor(resolved + 0.001) + 1,
          TeachingCalendarLogic.monthSheetWeekPosition);
      }
      return Math.max(Math.ceil(resolved - 0.001) - 1,
        TeachingCalendarLogic.monthSheetExpandedPosition);
    }
    return Math.min(Math.max(Math.round(resolved), 0), 2);
  }

  static clampMonthSheetPosition(position: number): number {
    return Math.min(Math.max(position, TeachingCalendarLogic.monthSheetExpandedPosition),
      TeachingCalendarLogic.monthSheetWeekPosition);
  }

  static monthCellExpansionProgress(position: number): number {
    return 1 - Math.min(Math.max(position,
      TeachingCalendarLogic.monthSheetExpandedPosition),
    TeachingCalendarLogic.monthSheetDetailsPosition);
  }

  static monthSelectedWeekProgress(position: number): number {
    return Math.min(Math.max(position - TeachingCalendarLogic.monthSheetDetailsPosition, 0), 1);
  }

  static interpolateMonthMetric(collapsed: number, expanded: number, progress: number): number {
    const resolved: number = Math.min(Math.max(progress, 0), 1);
    return Math.round(collapsed + (expanded - collapsed) * resolved);
  }

  static monthRowHeight(position: number, _rowIndex: number, _selectedWeekIndex: number,
    expandedHeight: number = TeachingCalendarLogic.monthExpandedCellHeight): number {
    const expandedProgress: number = TeachingCalendarLogic.monthCellExpansionProgress(position);
    // 第二段上划通过裁剪并平移完整月网格完成；每一周本身始终保持
    // 相同高度，避免日期小方框被逐行压扁。
    return TeachingCalendarLogic.interpolateMonthMetric(
      TeachingCalendarLogic.monthCollapsedCellHeight, expandedHeight, expandedProgress);
  }

  static monthGridViewportHeight(position: number, rowCount: number, rowHeight: number): number {
    const resolvedRows: number = Math.max(Math.floor(rowCount), 0);
    const resolvedRowHeight: number = Math.max(Math.floor(rowHeight), 0);
    if (resolvedRows === 0) {
      return 0;
    }
    const fullHeight: number = resolvedRows * resolvedRowHeight;
    return Math.max(Math.round(fullHeight - (fullHeight - resolvedRowHeight) *
      TeachingCalendarLogic.monthSelectedWeekProgress(position)), resolvedRowHeight);
  }

  static monthGridContentHeight(rowCount: number, rowHeight: number): number {
    return Math.max(Math.floor(rowCount), 0) * Math.max(Math.floor(rowHeight), 0);
  }

  static monthGridTranslationY(position: number, selectedWeekIndex: number,
    rowHeight: number): number {
    return -Math.round(Math.max(Math.floor(selectedWeekIndex), 0) *
      Math.max(Math.floor(rowHeight), 0) *
      TeachingCalendarLogic.monthSelectedWeekProgress(position));
  }

  static monthEntryAvailableHeight(cellHeight: number, expandedProgress: number): number {
    const bottomPadding: number = TeachingCalendarLogic.interpolateMonthMetric(5, 2,
      expandedProgress);
    const markerHeight: number = TeachingCalendarLogic.interpolateMonthMetric(12, 0,
      expandedProgress);
    return Math.max(cellHeight - 5 - bottomPadding - 24 - markerHeight, 0);
  }

  static monthEntrySlotCapacity(availableHeight: number, entryHeight: number = 14,
    entrySpacing: number = 1): number {
    if (availableHeight <= 0 || entryHeight <= 0) {
      return 0;
    }
    return Math.max(Math.floor((availableHeight + entrySpacing) /
      (entryHeight + entrySpacing)), 0);
  }

  static visibleMonthEntryCount(entryCount: number, slotCapacity: number): number {
    const count: number = Math.max(entryCount, 0);
    const capacity: number = Math.max(slotCapacity, 0);
    return count > capacity ? Math.max(capacity - 1, 0) : count;
  }

  static hiddenMonthEntryCount(entryCount: number, slotCapacity: number): number {
    return Math.max(entryCount - TeachingCalendarLogic.visibleMonthEntryCount(
      entryCount, slotCapacity), 0);
  }

  static monthEventLayout(totalCount: number, maximumRows: number): number[] {
    const total: number = Math.max(totalCount, 0);
    const rows: number = Math.max(maximumRows, 0);
    if (total <= rows) {
      return [total, 0];
    }
    if (rows <= 0) {
      return [0, total];
    }
    return [rows - 1, total - rows + 1];
  }
}

export class CalendarPageTransitionOffsets {
  readonly incomingStartX: number;
  readonly outgoingEndX: number;

  constructor(incomingStartX: number, outgoingEndX: number) {
    this.incomingStartX = incomingStartX;
    this.outgoingEndX = outgoingEndX;
  }
}

export class CalendarPopoverPosition {
  readonly x: number;
  readonly y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

export class CalendarFormatters {
  static readonly weekdayLabels: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  static weekdayLabel(day: DateParts, english: boolean = false): string {
    if (english) {
      const labels: string[] = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return labels[StrictDates.weekdayMonday1(day) - 1];
    }
    return '周' + CalendarFormatters.weekdayLabels[StrictDates.weekdayMonday1(day) - 1];
  }

  // 2026年8月18日 星期二
  static fullDate(day: DateParts, english: boolean = false): string {
    if (english) {
      const weekdays: string[] = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ];
      return weekdays[StrictDates.weekdayMonday1(day) - 1] + ', ' +
        CalendarFormatters.englishMonth(day.month) + ' ' + day.day.toString() + ', ' +
        day.year.toString();
    }
    const weekdays: string[] = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return day.year.toString() + '年' + day.month.toString() + '月' + day.day.toString() + '日 ' +
      weekdays[StrictDates.weekdayMonday1(day) - 1];
  }

  static monthDayCompact(day: DateParts, english: boolean = false): string {
    if (english) {
      return CalendarFormatters.englishMonth(day.month) + ' ' + day.day.toString();
    }
    return day.month.toString() + '月' + day.day.toString() + '日';
  }

  static monthLabel(month: number, english: boolean = false): string {
    return english ? CalendarFormatters.englishMonth(month) : month.toString() + '月';
  }

  static englishMonth(month: number): string {
    const months: string[] = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return month >= 1 && month <= 12 ? months[month - 1] : month.toString();
  }

  static hourLabel(hour: number): string {
    return (hour < 10 ? '0' + hour.toString() : hour.toString()) + ':00';
  }
}
