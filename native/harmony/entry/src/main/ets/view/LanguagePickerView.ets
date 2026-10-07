import { AppLanguage, AppLanguageInfo } from '../common/AppLocalization';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { PhoneNavigationLayout } from '../common/DeviceState';
import { AppModel } from '../model/AppModel';

// 独立语言页由 Root 持有；14项不会挤压分段，也不卸载下层设置草稿/滚动。
@ComponentV2
export struct LanguagePickerView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Event onSelect: (value: AppLanguage) => void = () => {};
  @Event onClose: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Button(this.model.text('返回'))
          .type(ButtonType.Normal)
          .fontColor(AppTheme.primary())
          .backgroundColor(AppTheme.surfaceVariant())
          .height(ControlMetrics.height)
          .id('settings.language.back')
          .onClick(() => this.onClose())
        Text(this.model.text('选择语言'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      Scroll() {
        Column({ space: 0 }) {
          ForEach(AppLanguageInfo.all, (language: AppLanguage, index: number) => {
            Row({ space: 10 }) {
              Text(AppLanguageInfo.label(language, this.model.resolvedLanguage()))
                .fontSize(16)
                .fontWeight(this.model.languageSetting() === language ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(AppTheme.text())
                .textDirection(TextDirection.AUTO)
                .maxLines(2)
                .layoutWeight(1)
              if (this.model.languageSetting() === language) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(17)
                  .fontColor([AppTheme.primary()])
              }
            }
            .width('100%')
            .constraintSize({ minHeight: 52 })
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.model.languageSetting() === language ? AppTheme.selection() : Color.Transparent)
            .borderRadius(8)
            .accessibilityText(AppLanguageInfo.label(language, this.model.resolvedLanguage()))
            .accessibilitySelected(this.model.languageSetting() === language)
            .id('settings.language.option.' + language)
            .onClick(() => this.onSelect(language))
            if (index < AppLanguageInfo.all.length - 1) {
              Divider().strokeWidth(0.5).color(AppTheme.border())
            }
          }, (language: AppLanguage) => language)
        }
        .width('100%')
        .padding({ left: 20, right: 20,
          bottom: PhoneNavigationLayout.minimumContentBottomInsetVp })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .id('settings.language.picker')
  }
}
