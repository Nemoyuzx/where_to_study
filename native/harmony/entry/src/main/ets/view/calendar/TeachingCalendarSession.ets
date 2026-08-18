// 教学日历会话状态，对应 iOS 端 TeachingCalendarSessionState。
// selectedDate 使用上海时区日历日（DateParts，不可变，切换即新建实例）。
import { DateParts, StrictDates } from '../../common/StrictDates';

@ObservedV2
export class TeachingCalendarSession {
  @Trace selectedDate: DateParts = StrictDates.todayParts();
  @Trace modeRawValue: string = '周';
  @Trace isMonthExpanded: boolean = true;

  resetToToday(): void {
    this.selectedDate = StrictDates.todayParts();
  }
}
