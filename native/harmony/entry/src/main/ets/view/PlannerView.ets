// 空教室页（对应 iOS PlannerView.swift）。移植轮次中实现。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';

@Component
export struct PlannerView {
  @Consumer('appModel') model: AppModel;

  build() {
    Column() {
      Text('空教室')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
