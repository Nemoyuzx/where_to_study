// 教学日历视口数据的独立预热控制器。
// 日历视图和过渡动画只读取 AppModel 缓存；日期/模式变化由 CalendarSectionView
// 转交本控制器，统一计算视口并调用 AppModel 的 single-flight 预热入口。
import { DateParts, StrictDates } from '../../common/StrictDates';
import {
  CalendarViewportPreloadPlan, CalendarViewportPreloadTarget
} from '../../common/CalendarViewportPreload';
import { CalendarMode } from './CalendarLogic';

export { CalendarViewportPreloadPlan, CalendarViewportPreloadTarget };

export class CalendarViewportPreloadPlanner {
  static plan(mode: CalendarMode, selectedDate: DateParts): CalendarViewportPreloadPlan {
    const days: DateParts[] = mode === CalendarMode.day ? [selectedDate] :
      (mode === CalendarMode.week ? CalendarViewportPreloadPlanner.weekDays(selectedDate) :
        (mode === CalendarMode.month ? CalendarViewportPreloadPlanner.monthDays(selectedDate) :
          CalendarViewportPreloadPlanner.yearDays(selectedDate.year)));
    const years: Set<number> = new Set<number>();
    for (const day of days) {
      years.add(day.year);
    }
    const holidayYears: number[] = [];
    for (const year of years) {
      holidayYears.push(year);
    }
    holidayYears.sort((left: number, right: number): number => left - right);
    return new CalendarViewportPreloadPlan(selectedDate, days, holidayYears);
  }

  private static weekDays(containing: DateParts): DateParts[] {
    const first: DateParts = StrictDates.addDays(
      containing, 1 - StrictDates.weekdayMonday1(containing));
    const result: DateParts[] = [];
    for (let offset = 0; offset < 7; offset++) {
      result.push(StrictDates.addDays(first, offset));
    }
    return result;
  }

  private static monthDays(containing: DateParts): DateParts[] {
    const first: DateParts = new DateParts(containing.year, containing.month, 1);
    const gridStart: DateParts = StrictDates.addDays(
      first, 1 - StrictDates.weekdayMonday1(first));
    const result: DateParts[] = [];
    for (let offset = 0; offset < 42; offset++) {
      result.push(StrictDates.addDays(gridStart, offset));
    }
    return result;
  }

  private static yearDays(year: number): DateParts[] {
    const count: number = StrictDates.isLeapYear(year) ? 366 : 365;
    const first: DateParts = new DateParts(year, 1, 1);
    const result: DateParts[] = [];
    for (let offset = 0; offset < count; offset++) {
      result.push(StrictDates.addDays(first, offset));
    }
    return result;
  }
}

export class CalendarViewportPreloadController {
  private signatures: string[] = [];
  private readonly signatureCapacity: number;

  constructor(signatureCapacity: number = 12) {
    this.signatureCapacity = Math.max(Math.floor(signatureCapacity), 1);
  }

  prewarm(target: CalendarViewportPreloadTarget, mode: CalendarMode,
    selectedDate: DateParts, refresh: boolean = false): void {
    const signature: string = mode + ':' + StrictDates.formatDateParts(selectedDate);
    if (!refresh && this.signatures.includes(signature)) {
      return;
    }
    this.remember(signature);
    const plan: CalendarViewportPreloadPlan =
      CalendarViewportPreloadPlanner.plan(mode, selectedDate);
    target.prewarmCalendarViewport(plan.selectedDate, plan.markerDays, plan.holidayYears);
  }

  private remember(signature: string): void {
    const existing: number = this.signatures.indexOf(signature);
    if (existing >= 0) {
      this.signatures.splice(existing, 1);
    }
    this.signatures.push(signature);
    while (this.signatures.length > this.signatureCapacity) {
      this.signatures.shift();
    }
  }
}
