// 教学日历一级页面，对应 iOS 端 AdaptiveTeachingCalendarView：
// 窄屏（< 760vp 或半折叠）使用 MobileTeachingCalendarView，
// 宽屏（>= 760vp，含平板展开/2in1/PC）使用 ExpandedTeachingCalendarView。
import { AppModel } from '../model/AppModel';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { MobileTeachingCalendarView } from './calendar/MobileTeachingCalendarView';
import { ExpandedTeachingCalendarView } from './calendar/ExpandedTeachingCalendarView';
import { TeachingCalendarSession } from './calendar/TeachingCalendarSession';
import { CalendarMode, CalendarModeInfo } from './calendar/CalendarLogic';
import { CalendarViewportPreloadController } from './calendar/CalendarViewportPreloadController';

@ComponentV2
export struct CalendarSectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param containerWidth: number = 390;
  @Event onQueryVisibilityChanged: (visible: boolean) => void = () => {
  };
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
    this.viewportPreloader.prewarm(this.model, mode, this.session.selectedDate, refresh);
  }

  build() {
    if (AdaptiveLayoutPolicy.useExpandedCalendar(this.containerWidth)) {
      ExpandedTeachingCalendarView({
        session: this.session,
        onQueryRequested: (): void => {
          this.onQueryVisibilityChanged(true);
        }
      })
    } else {
      MobileTeachingCalendarView({
        session: this.session,
        onQueryRequested: (): void => {
          this.onQueryVisibilityChanged(true);
        }
      })
    }
  }
}
