// 教学日历会话状态，对应 iOS 端 TeachingCalendarSessionState。
// selectedDate 使用上海时区日历日（DateParts，不可变，切换即新建实例）。
import { DateParts, StrictDates } from '../../common/StrictDates';
import { TeachingCalendarLogic } from './CalendarLogic';

@ObservedV2
export class TeachingCalendarSession {
  @Trace selectedDate: DateParts = StrictDates.todayParts();
  @Trace modeRawValue: string = '周';
  @Trace monthSheetPosition: number = TeachingCalendarLogic.monthSheetExpandedPosition;
  private preferredDayOfMonth: number = this.selectedDate.day;

  selectDate(date: DateParts): void {
    this.selectedDate = date;
    this.preferredDayOfMonth = date.day;
  }

  monthNavigationDestination(direction: number): DateParts {
    return TeachingCalendarLogic.addMonths(
      this.selectedDate, direction, this.preferredDayOfMonth);
  }

  commitMonthNavigation(date: DateParts): void {
    // 月份分页保留用户最后明确选择的日号，例如
    // 1 月 31 日 -> 2 月 28 日 -> 3 月 31 日。
    this.selectedDate = date;
  }

  setMonthSheetPosition(position: number): void {
    this.monthSheetPosition = TeachingCalendarLogic.clampMonthSheetPosition(position);
  }

  resetToToday(): void {
    this.selectDate(StrictDates.todayParts());
  }
}
