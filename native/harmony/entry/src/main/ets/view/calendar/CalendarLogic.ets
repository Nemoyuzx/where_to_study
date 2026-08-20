// 教学日历的纯逻辑与时间线布局，以原生 Android 实现为移动端基准。
// TeachingCalendarLogic / CalendarTimelineLogic / CalendarTimelineDay。
import { Course, HolidayItem, SlotMetadata } from '../../common/Models';
import { StrictDates, DateParts } from '../../common/StrictDates';

export enum CalendarMode {
  day = '日',
  week = '周',
  month = '月',
  year = '年'
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

  static yearCourseOpacity(courseCount: number): number {
    if (courseCount <= 0) {
      return 0;
    }
    const count: number = courseCount;
    return 0.12 + 0.72 * count / (count + 3);
  }

  static periodTitle(date: DateParts, mode: CalendarMode): string {
    if (mode === CalendarMode.day) {
      return date.year.toString() + '年' + date.month.toString() + '月' + date.day.toString() + '日';
    }
    if (mode === CalendarMode.week) {
      return date.year.toString() + '年' + date.month.toString() + '月 第' +
        TeachingCalendarLogic.weekOfYear(date).toString() + '周';
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

  static addMonths(date: DateParts, direction: number): DateParts {
    const zeroBased: number = date.month - 1 + direction;
    const year: number = date.year + Math.floor(zeroBased / 12);
    let month: number = zeroBased % 12;
    if (month < 0) {
      month += 12;
    }
    const maxDay: number = StrictDates.daysInMonth(year, month + 1);
    const day: number = Math.min(date.day, maxDay);
    return new DateParts(year, month + 1, day);
  }

  // 与 Calendar.shanghai（firstWeekday=2，minDaysInFirstWeek=1）的 weekOfYear 一致。
  static weekOfYear(date: DateParts): number {
    const dayOfYear: number =
      StrictDates.epochDay(date.year, date.month, date.day) -
      StrictDates.epochDay(date.year, 1, 1) + 1;
    const jan1Weekday: number = StrictDates.weekdayMonday1(new DateParts(date.year, 1, 1));
    return Math.floor((dayOfYear - 1 + (jan1Weekday - 1)) / 7) + 1;
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

  static monthExpansionAction(horizontal: number, vertical: number): number | null {
    // 返回 1 = expand，-1 = collapse，null = 无动作。
    if (Math.abs(vertical) < 44 || Math.abs(vertical) < Math.abs(horizontal) * 1.25) {
      return null;
    }
    return vertical > 0 ? 1 : -1;
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

  static monthRowHeight(position: number, rowIndex: number, selectedWeekIndex: number,
    expandedHeight: number = TeachingCalendarLogic.monthExpandedCellHeight): number {
    const expandedProgress: number = TeachingCalendarLogic.monthCellExpansionProgress(position);
    const fullHeight: number = TeachingCalendarLogic.interpolateMonthMetric(
      TeachingCalendarLogic.monthCollapsedCellHeight, expandedHeight, expandedProgress);
    if (rowIndex === selectedWeekIndex) {
      return fullHeight;
    }
    return Math.max(Math.round(fullHeight *
      (1 - TeachingCalendarLogic.monthSelectedWeekProgress(position))), 0);
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

export class CalendarFormatters {
  static readonly weekdayLabels: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  static weekdayLabel(day: DateParts): string {
    return '周' + CalendarFormatters.weekdayLabels[StrictDates.weekdayMonday1(day) - 1];
  }

  // 2026年8月18日 星期二
  static fullDate(day: DateParts): string {
    const weekdays: string[] = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return day.year.toString() + '年' + day.month.toString() + '月' + day.day.toString() + '日 ' +
      weekdays[StrictDates.weekdayMonday1(day) - 1];
  }

  static monthDayCompact(day: DateParts): string {
    return day.month.toString() + '月' + day.day.toString() + '日';
  }

  static monthLabel(month: number): string {
    return month.toString() + '月';
  }

  static hourLabel(hour: number): string {
    return (hour < 10 ? '0' + hour.toString() : hour.toString()) + ':00';
  }
}
