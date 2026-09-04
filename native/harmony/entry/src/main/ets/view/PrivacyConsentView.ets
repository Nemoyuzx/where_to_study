// 首次启动隐私同意界面。用户同意前不构建 RootView，因而不会触发主功能或网络请求。
import { AppTheme } from '../common/AppTheme';
import { AppModel } from '../model/AppModel';

@ComponentV2
export struct PrivacyConsentView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param declined: boolean = false;
  @Param persistenceFailed: boolean = false;
  @Param accepting: boolean = false;
  @Event onOpenPolicy: () => void = () => {
  };
  @Event onAccept: () => void = () => {
  };
  @Event onDecline: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 10 }) {
        Text('Where To Study')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())

        Text(this.model.text('隐私政策提示'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .width('100%')

        Text(this.model.text(
          '欢迎使用 Where To Study。请在使用前阅读并同意隐私政策，了解教务账号、课表、系统日历、天气及公开活动数据的处理方式。'))
          .fontSize(15)
          .lineHeight(22)
          .fontColor(AppTheme.secondaryText())
          .width('100%')

        Button(this.model.text('阅读完整隐私政策'))
          .type(ButtonType.Normal)
          .stateEffect(true)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.primary())
          .borderRadius(7)
          .border({ width: 1, color: AppTheme.primary() })
          .backgroundColor(AppTheme.surface())
          .width('100%')
          .height(42)
          .id('privacy_consent_open_policy')
          .accessibilityText(this.model.text('阅读完整隐私政策'))
          .onClick(() => {
            this.onOpenPolicy();
          })

        Text(this.model.text('同意状态仅保存在本机，不会上传。'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')

        if (this.declined) {
          Text(this.model.text('你已拒绝隐私政策，无法进入应用主功能。你仍可阅读政策并重新选择。'))
            .fontSize(13)
            .lineHeight(19)
            .fontColor(AppTheme.danger())
            .width('100%')
            .id('privacy_consent_declined_message')
        }

        if (this.persistenceFailed) {
          Text(this.model.text('无法在本机保存同意状态，请稍后重试。'))
            .fontSize(13)
            .lineHeight(19)
            .fontColor(AppTheme.danger())
            .width('100%')
            .id('privacy_consent_save_error')
        }

        Row({ space: 10 }) {
          Button(this.model.text('拒绝'))
            .type(ButtonType.Normal)
            .stateEffect(true)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.text())
            .borderRadius(7)
            .border({ width: 1, color: AppTheme.border() })
            .backgroundColor(AppTheme.surface())
            .layoutWeight(1)
            .height(42)
            .enabled(!this.accepting)
            .id('privacy_consent_decline')
            .onClick(() => {
              this.onDecline();
            })

          Button(this.accepting ? this.model.text('正在保存…') : this.model.text('同意并继续'))
            .type(ButtonType.Normal)
            .stateEffect(true)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.onPrimary())
            .borderRadius(7)
            .backgroundColor(AppTheme.primaryFill())
            .layoutWeight(1)
            .height(42)
            .enabled(!this.accepting)
            .id('privacy_consent_accept')
            .onClick(() => {
              this.onAccept();
            })
        }
        .width('100%')
      }
      .width('calc(100% - 40vp)')
      .constraintSize({ maxWidth: 520 })
      .padding(22)
      .borderRadius(14)
      .backgroundColor(AppTheme.surface())
      .shadow({ radius: 16, color: '#33000000', offsetY: 6 })
      .alignItems(HorizontalAlign.Start)
      .id('privacy_consent_dialog')
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24 })
    .backgroundColor(AppTheme.background())
  }
}
