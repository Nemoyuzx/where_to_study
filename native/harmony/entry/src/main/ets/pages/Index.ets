import { AppModel } from '../model/AppModel';
import { AppLaunchConfiguration } from '../model/LaunchSupport';
import { RootView } from '../view/RootView';
import { AppTheme } from '../common/AppTheme';
import { PrivacyConsentStore } from '../store/PrivacyConsentStore';
import { PrivacyConsentView } from '../view/PrivacyConsentView';
import { PrivacyPolicyView } from '../view/PrivacyPolicyView';

enum PrivacyConsentPhase {
  loading = 'loading',
  required = 'required',
  declined = 'declined',
  accepted = 'accepted'
}

// 应用根页面：唯一的 AppModel 在这里创建并通过 @Provider 注入整个组件树，
// 与 iOS 端 @StateObject AppModel + environmentObject 的注入方式对应。
@Entry
@ComponentV2
struct Index {
  @Provider('appModel') model: AppModel = AppLaunchConfiguration.makeModel();
  @Local privacyConsentPhase: PrivacyConsentPhase = PrivacyConsentPhase.loading;
  @Local showingPrivacyPolicy: boolean = false;
  @Local privacyConsentPersistenceFailed: boolean = false;
  @Local acceptingPrivacyConsent: boolean = false;
  private readonly privacyConsentStore: PrivacyConsentStore = new PrivacyConsentStore();

  aboutToAppear(): void {
    this.restorePrivacyConsent();
  }

  private restorePrivacyConsent(): void {
    if (AppLaunchConfiguration.hasAcceptedPrivacyConsentForTesting()) {
      this.privacyConsentPhase = PrivacyConsentPhase.accepted;
      return;
    }
    this.privacyConsentStore.isAccepted().then((accepted: boolean): void => {
      this.privacyConsentPhase = accepted ? PrivacyConsentPhase.accepted : PrivacyConsentPhase.required;
    }).catch((): void => {
      // 存储读取失败时按未同意处理，绝不进入主功能。
      this.privacyConsentPhase = PrivacyConsentPhase.required;
      this.privacyConsentPersistenceFailed = true;
    });
  }

  private acceptPrivacyConsent(): void {
    if (this.acceptingPrivacyConsent) {
      return;
    }
    this.acceptingPrivacyConsent = true;
    this.privacyConsentPersistenceFailed = false;
    this.privacyConsentStore.accept().then((): void => {
      this.privacyConsentPhase = PrivacyConsentPhase.accepted;
      this.acceptingPrivacyConsent = false;
    }).catch((): void => {
      // 必须先成功写入本机，才允许构建并进入 RootView。
      this.privacyConsentPhase = PrivacyConsentPhase.required;
      this.privacyConsentPersistenceFailed = true;
      this.acceptingPrivacyConsent = false;
    });
  }

  build() {
    Stack() {
      if (this.privacyConsentPhase === PrivacyConsentPhase.accepted) {
        RootView()
      } else if (this.showingPrivacyPolicy) {
        PrivacyPolicyView({
          onClose: (): void => {
            this.showingPrivacyPolicy = false;
          }
        })
      } else if (this.privacyConsentPhase === PrivacyConsentPhase.loading) {
        Column({ space: 12 }) {
          Progress({ value: 20, type: ProgressType.ScaleRing })
            .width(34)
            .height(34)
            .color(AppTheme.primary())
          Text(this.model.text('正在读取隐私设置…'))
            .fontSize(14)
            .fontColor(AppTheme.secondaryText())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        PrivacyConsentView({
          declined: this.privacyConsentPhase === PrivacyConsentPhase.declined,
          persistenceFailed: this.privacyConsentPersistenceFailed,
          accepting: this.acceptingPrivacyConsent,
          onOpenPolicy: (): void => {
            this.showingPrivacyPolicy = true;
          },
          onAccept: (): void => {
            this.acceptPrivacyConsent();
          },
          onDecline: (): void => {
            this.privacyConsentPhase = PrivacyConsentPhase.declined;
            this.privacyConsentPersistenceFailed = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
  }
}
