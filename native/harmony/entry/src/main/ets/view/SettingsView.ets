// 以原生 Android SettingsPage.kt 为手机端视觉与交互基准的设置页。
import { AppModel } from '../model/AppModel';
import { AppMeta } from '../common/AppMeta';
import { AppTheme } from '../common/AppTheme';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { AppContext } from '../store/AppContext';
import { SemesterLogic, SemesterSuggestion } from '../common/SemesterLogic';
import { PrivacyPolicyView } from './PrivacyPolicyView';

@ComponentV2
export struct SettingsView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local contentWidth: number = 350;
  @Local showingPrivacyPolicy: boolean = false;
  private statusDismissRevision: number = 0;

  private static readonly projectURL: string =
    'https://github.com/Nemoyuzx/where_to_study';

  build() {
    if (this.showingPrivacyPolicy) {
      PrivacyPolicyView({
        onClose: (): void => {
          this.setPrivacyPolicyVisible(false);
        }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    } else {
      this.settingsContent()
    }
  }

  private isCompact(): boolean {
    return !AdaptiveLayoutPolicy.useTwoColumn(this.contentWidth);
  }

  private setPrivacyPolicyVisible(visible: boolean): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.showingPrivacyPolicy = visible;
    });
  }

  private dismissStatusMessageAfter(message: string, delay: number = 1800): void {
    this.statusDismissRevision++;
    const revision: number = this.statusDismissRevision;
    setTimeout(() => {
      if (revision === this.statusDismissRevision && this.model.statusMessage === message) {
        this.model.statusMessage = '';
      }
    }, delay);
  }

  private openProjectPage(): void {
    try {
      AppContext.get().openLink(SettingsView.projectURL);
    } catch (e) {
      // 系统无法打开链接时保持在当前页。
    }
  }

  @Builder
  settingsContent() {
    Scroll() {
      Column({ space: 16 }) {
        this.settingsTitle()
        if (AdaptiveLayoutPolicy.useTwoColumn(this.contentWidth)) {
          Row({ space: 16 }) {
            Column() {
              this.accountSurface()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 16 }) {
              this.notificationSurface()
              this.localDataSurface()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
          this.aboutSurface()
        } else {
          Column({ space: 16 }) {
            this.accountSurface()
            this.notificationSurface()
            this.localDataSurface()
            this.aboutSurface()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .padding({
        left: 20,
        right: 20,
        top: this.isCompact() ? 16 : 20,
        bottom: this.isCompact() ? 88 : 28
      })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.contentWidth = Number(newArea.width) - 40;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .align(Alignment.Top)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  settingsTitle() {
    Column({ space: 3 }) {
      Text('Where To Study')
        .fontSize(this.isCompact() ? 11 : 12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.secondaryText())
      Text('设置')
        .fontSize(this.isCompact() ? 28 : 34)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .maxLines(1)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ bottom: this.isCompact() ? 12 : 18 })
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.text())
      .width('100%')
      .padding({ bottom: 12 })
  }

  @Builder
  accountSurface() {
    Column() {
      this.sectionTitle('个人账户')

      this.field('教务账号', this.model.account, InputType.Normal, (value: string): void => {
        this.model.account = value;
      })
      Blank().height(7)
      this.field('密码', this.model.password, InputType.Password, (value: string): void => {
        this.model.password = value;
      })
      if (this.model.canPreserveSavedPassword()) {
        Text('密码已安全保存，留空保持不变')
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
          .padding({ left: 2, right: 2, top: 7 })
      }
      Blank().height(7)
      this.field('学期编号', this.model.termID, InputType.Normal, (value: string): void => {
        this.model.termID = value;
      })
      Blank().height(7)
      this.field('第一周周一（YYYY-MM-DD）', this.model.termStartDate, InputType.Normal,
        (value: string): void => {
          this.model.termStartDate = value;
        })

      Blank().height(7)
      Button('按当前日期自动检测')
        .type(ButtonType.Normal)
        .stateEffect(true)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.primary())
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.primary() })
        .backgroundColor(AppTheme.surface())
        .width('100%')
        .height(36)
        .enabled(!this.model.isSampleMode())
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          const suggested: SemesterSuggestion = SemesterLogic.suggestCurrentPeriod();
          this.model.termID = suggested.termID;
          this.model.termStartDate = suggested.termStartDate;
        })
      if (SemesterLogic.matchesCurrentPeriod(this.model.termID, this.model.termStartDate)) {
        Text('✓ 与当前学期一致')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.primary())
          .width('100%')
          .padding({ left: 2, right: 2, top: 7 })
      } else if (SemesterLogic.isValidTermID(this.model.termID) &&
        SemesterLogic.isValidTermStartDate(this.model.termStartDate)) {
        Text('当前设置与检测结果不同')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.accent())
          .width('100%')
          .padding({ left: 2, right: 2, top: 7 })
      }
      Text('获取/刷新课表后会自动应用教务返回的学期与开学日期，无需手动填写。')
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
        .padding({ left: 2, right: 2, top: 7 })

      Text('默认校区')
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: this.isCompact() ? 10 : 16, bottom: this.isCompact() ? 5 : 7 })
      Select([{ value: '西土城' }, { value: '沙河' }])
        .selected(this.model.campusID === '04' ? 1 : 0)
        .value(this.model.campusID === '04' ? '沙河' : '西土城')
        .font({ size: 15 })
        .fontColor(AppTheme.text())
        .selectedOptionBgColor(AppTheme.primaryFill())
        .selectedOptionFont({ size: 15, weight: FontWeight.Medium })
        .selectedOptionFontColor(AppTheme.onPrimary())
        .optionBgColor(AppTheme.surface())
        .optionFont({ size: 15 })
        .optionFontColor(AppTheme.text())
        .backgroundColor(AppTheme.surface())
        .border({ width: 1, color: AppTheme.border() })
        .borderRadius(6)
        .height(36)
        .width('100%')
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onSelect((index: number) => {
          this.model.campusID = index === 1 ? '04' : '01';
        })

      Blank().height(this.isCompact() ? 12 : 18)
      Button('保存设置')
        .type(ButtonType.Normal)
        .stateEffect(true)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.onPrimary())
        .borderRadius(6)
        .backgroundColor(AppTheme.primaryFill())
        .width('100%')
        .height(36)
        .enabled(!this.model.isSampleMode())
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          const work: Promise<boolean> = this.model.saveSettings();
          work.then((saved: boolean) => {
            if (saved) {
              this.dismissStatusMessageAfter(this.model.statusMessage);
            }
          }).catch(() => {
            // 错误说明已由 AppModel 写入状态消息。
          });
        })

      Blank().height(7)
      Button(this.model.isRefreshingSchedule ? '正在获取…' : '获取/刷新个人课表')
        .type(ButtonType.Normal)
        .stateEffect(true)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.primary())
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.primary() })
        .backgroundColor(AppTheme.surface())
        .width('100%')
        .height(36)
        .enabled(!this.model.isRefreshingSchedule && !this.model.isSampleMode())
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          const work: Promise<void> = (async (): Promise<void> => {
            const saved: boolean = await this.model.saveSettings();
            if (saved) {
              await this.model.refreshSchedule();
            }
          })();
          work.catch(() => {
            // 错误说明已由 AppModel 写入状态消息。
          });
        })

      Text('账号和密码仅保存于本机，并由 HarmonyOS ASSET 安全存储保护。')
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: this.isCompact() ? 8 : 12 })

      if (this.model.statusMessage.length > 0) {
        Text(this.model.statusMessage)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
          .padding({ top: 7 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  field(placeholder: string, value: string, inputType: InputType,
    onChangeValue: (value: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(inputType)
      .fontSize(15)
      .fontColor(AppTheme.text())
      .placeholderColor(AppTheme.secondaryText())
      .backgroundColor(AppTheme.surface())
      .borderRadius(6)
      .border({ width: 1, color: AppTheme.border() })
      .padding({ left: 13, right: 13 })
      .width('100%')
      .height(36)
      .showPasswordIcon(false)
      .enabled(!this.model.isSampleMode())
      .onChange((text: string) => {
        onChangeValue(text);
      })
  }

  @Builder
  notificationSurface() {
    Column() {
      this.sectionTitle('课程提醒')
      Row({ space: 8 }) {
        Text('每天 07:30 发送当日课程摘要')
          .fontSize(15)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.dailyCourseNotificationsEnabled })
          .selectedColor(AppTheme.primaryFill())
          .width(48)
          .height(28)
          .enabled(!this.model.isSampleMode() || this.model.isReviewDemo())
          .onChange((value: boolean) => {
            this.model.setDailyCourseNotificationsEnabled(value);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 36 })
      .alignItems(VerticalAlign.Center)

      Text('仅在当天有课时通知；课表更新或账号变更后会自动重排。')
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: 4 })
      if (this.model.dailyCourseNotificationStatusMessage.length > 0) {
        Text(this.model.dailyCourseNotificationStatusMessage)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
          .padding({ top: 4 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  localDataSurface() {
    Column() {
      this.sectionTitle('本地数据')
      Text('个人课表、空教室缓存、节假日缓存、账号与偏好均只保存在本机。')
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
        .padding({ bottom: this.isCompact() ? 8 : 12 })
      Button('清除本地数据')
        .type(ButtonType.Normal)
        .stateEffect(true)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.danger())
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.danger() })
        .backgroundColor('#14FF3B30')
        .width('100%')
        .height(36)
        .enabled(!this.model.isSampleMode())
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          this.getUIContext().showAlertDialog({
            title: '清除全部本地数据？',
            message: '将删除保存的账号、密码、个人课表、空教室缓存和设置。此操作无法撤销。',
            primaryButton: {
              value: '取消',
              action: () => {
              }
            },
            secondaryButton: {
              value: '确认清除',
              fontColor: AppTheme.danger(),
              action: () => {
                const work: Promise<void> = this.model.clearLocalData();
                work.then(() => {
                  this.dismissStatusMessageAfter(this.model.statusMessage);
                }).catch(() => {
                  // 错误说明已由 AppModel 写入状态消息。
                });
              }
            }
          });
        })
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  aboutSurface() {
    Column() {
      this.sectionTitle('关于本应用')
      Text('Where To Study  ' + AppMeta.version +
        '\n北邮课表与空教室查询的独立非官方客户端，不由北京邮电大学运营。')
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(18)
        .width('100%')
        .padding({ bottom: this.isCompact() ? 8 : 12 })

      this.linkButton('GitHub 项目主页', (): void => {
        this.openProjectPage();
      })
      Blank().height(7)
      this.linkButton('隐私说明', (): void => {
        this.setPrivacyPolicyVisible(true);
      })
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  linkButton(label: string, action: () => void) {
    Button(label)
      .type(ButtonType.Normal)
      .stateEffect(true)
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.primary())
      .borderRadius(6)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.surface())
      .width('100%')
      .height(36)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
      .onClick(() => {
        action();
      })
  }
}
