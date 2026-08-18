// 教学日历一级页面，对应 iOS 端 AdaptiveTeachingCalendarView：
// 窄屏（< 760vp 或半折叠）使用 MobileTeachingCalendarView，
// 宽屏（>= 760vp，含平板展开/2in1/PC）使用 ExpandedTeachingCalendarView。
import { AppModel } from '../model/AppModel';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { MobileTeachingCalendarView } from './calendar/MobileTeachingCalendarView';
import { ExpandedTeachingCalendarView } from './calendar/ExpandedTeachingCalendarView';
import { TeachingCalendarSession } from './calendar/TeachingCalendarSession';

@ComponentV2
export struct CalendarSectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param containerWidth: number = 390;
  @Local session: TeachingCalendarSession = new TeachingCalendarSession();

  build() {
    if (AdaptiveLayoutPolicy.useExpandedCalendar(this.containerWidth)) {
      ExpandedTeachingCalendarView({ session: this.session })
    } else {
      MobileTeachingCalendarView({ session: this.session })
    }
  }
}
