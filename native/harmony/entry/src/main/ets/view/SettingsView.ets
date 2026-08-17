// 设置页（对应 iOS SettingsView.swift）。移植轮次中实现。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';

@Component
export struct SettingsView {
  @Consume('appModel') model: AppModel;

  build() {
    Column() {
      Text('设置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
