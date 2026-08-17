// 教学日历一级页面，对应 iOS 端 AdaptiveTeachingCalendarView：
// 手机与宽屏共用 MobileTeachingCalendarView（日/周/月/年视图、滑动翻页、
// 月视图展开/收起），内容区随窗口自适应。
import { AppModel } from '../model/AppModel';
import { MobileTeachingCalendarView } from './calendar/MobileTeachingCalendarView';
import { TeachingCalendarSession } from './calendar/TeachingCalendarSession';

@ComponentV2
export struct CalendarSectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param containerWidth: number = 390;
  @Local session: TeachingCalendarSession = new TeachingCalendarSession();

  build() {
    MobileTeachingCalendarView({ session: this.session })
  }
}
