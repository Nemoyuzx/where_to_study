// 教学日历的纯逻辑与时间线布局，对应 iOS 端
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
      return date.year.toString() + '年' + date.month.toString() + '月 第 ' +
        TeachingCalendarLogic.weekOfYear(date).toString() + ' 周';
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
    return new DateParts(date.year + direction, date.month, date.day);
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
    if (Math.abs(horizontal) < 36 || Math.abs(projected) < 80 ||
      Math.abs(horizontal) < Math.abs(vertical) * 1.35) {
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
    return CalendarFormatters.weekdayLabels[StrictDates.weekdayMonday1(day) - 1];
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
