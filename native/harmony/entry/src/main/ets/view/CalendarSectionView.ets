// 教学日历一级页面，对应 iOS 端 AdaptiveTeachingCalendarView：
// 内容宽度不足 868vp 或半折叠时使用 MobileTeachingCalendarView；
// 横屏平板达到七个 96vp 日期列的几何宽度后使用 ExpandedTeachingCalendarView。
import { AppModel } from '../model/AppModel';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { MobileTeachingCalendarView } from './calendar/MobileTeachingCalendarView';
import { ExpandedTeachingCalendarView } from './calendar/ExpandedTeachingCalendarView';
import { TeachingCalendarSession } from './calendar/TeachingCalendarSession';
import { CalendarMode, CalendarModeInfo } from './calendar/CalendarLogic';
import { CalendarViewportPreloadController } from './calendar/CalendarViewportPreloadController';
import { DateParts } from '../common/StrictDates';

@ComponentV2
export struct CalendarSectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param containerWidth: number = 390;
  @Local session: TeachingCalendarSession = new TeachingCalendarSession();
  private viewportPreloader: CalendarViewportPreloadController =
    new CalendarViewportPreloadController();

  aboutToAppear(): void {
    this.prewarmViewport();
  }

  @Monitor('session.selectedDate', 'session.modeRawValue')
  onViewportChange(monitor: IMonitor): void {
    this.prewarmViewport();
  }

  @Monitor('model.competitionDeadlinesEnabled', 'model.conferenceDeadlinesEnabled',
    'model.schoolContestNoticesEnabled',
    'model.summerCampDeadlinesEnabled', 'model.hackathonDeadlinesEnabled',
    'model.customDeadlinesEnabled', 'model.customDeadlinesURL', 'model.favoriteDeadlines',
    'model.almanacEnabled')
  onViewportSourceChange(monitor: IMonitor): void {
    this.prewarmViewport(true);
  }

  private prewarmViewport(refresh: boolean = false): void {
    const mode: CalendarMode = CalendarModeInfo.fromRawValue(this.session.modeRawValue);
    const dates: DateParts[] = mode === CalendarMode.month ? [
      this.session.selectedDate,
      this.session.monthNavigationDestination(-1),
      this.session.monthNavigationDestination(1)
    ] : [this.session.selectedDate];
    for (const date of dates) {
      this.viewportPreloader.prewarm(this.model, mode, date, refresh);
    }
  }

  build() {
    if (AdaptiveLayoutPolicy.useExpandedCalendar(this.containerWidth)) {
      ExpandedTeachingCalendarView({ session: this.session })
    } else {
      MobileTeachingCalendarView({ session: this.session })
    }
  }
}
