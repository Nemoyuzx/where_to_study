// 教学日历页（对应 iOS AdaptiveTeachingCalendarView：
// 窄屏 MobileTeachingCalendarView，宽屏 TeachingCalendarView）。
// 移植轮次中实现。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';

@ComponentV2
export struct CalendarSectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param containerWidth: number = 390;

  build() {
    Column() {
      Text('教学日历')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
