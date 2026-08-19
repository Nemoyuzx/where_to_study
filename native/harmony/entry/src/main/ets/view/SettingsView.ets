// 与 iOS 端 SettingsView.swift 对应的设置页。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { PageTitle, SurfaceCard, SectionHeader } from './SharedComponents';
import { PrivacyPolicyView } from './PrivacyPolicyView';

@ComponentV2
export struct SettingsView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local contentWidth: number = 350;
  @Local showingPrivacyPolicy: boolean = false;

  build() {
    if (this.showingPrivacyPolicy) {
      PrivacyPolicyView({
        onClose: (): void => {
          this.showingPrivacyPolicy = false;
        }
      })
    } else {
      this.settingsContent()
    }
  }

  @Builder
  settingsContent() {
    Scroll() {
      Column({ space: 16 }) {
        PageTitle({ eyebrow: 'Where To Study', title: '设置' })
        if (AdaptiveLayoutPolicy.useTwoColumn(this.contentWidth)) {
          Row({ space: 16 }) {
            Column({ space: 16 }) {
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
      .padding(20)
      .width('100%')
      .constraintSize({ maxWidth: 720 })
      .alignItems(HorizontalAlign.Start)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.contentWidth = Number(newArea.width) - 40;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .align(Alignment.Top)
  }

  @Builder
  accountSurface() {
    SurfaceCard() {
      Column({ space: 14 }) {
        SectionHeader({ icon: $r('sys.symbol.person'), title: '个人账户' })

        this.field('学号', this.model.account, 'field.account',
          InputType.Normal, (value: string): void => {
            this.model.account = value;
          })
        this.field(
          this.model.canPreserveSavedPassword() ? '已安全保存，留空保持不变' : '教务密码',
          this.model.password, 'field.password', InputType.Password,
          (value: string): void => {
            this.model.password = value;
          })
        this.field('学期编号', this.model.termID, 'field.term-id', InputType.Normal,
          (value: string): void => {
            this.model.termID = value;
          })
        this.field('第一周周一（YYYY-MM-DD）', this.model.termStartDate, 'field.term-start-date',
          InputType.Normal, (value: string): void => {
            this.model.termStartDate = value;
          })

        Row({ space: 8 }) {
          Text('默认校区')
            .fontSize(14)
            .fontColor(AppTheme.text())
            .width(72)
          ForEach(['01', '04'], (id: string) => {
            Text(id === '01' ? '西土城' : '沙河')
              .fontSize(13)
              .fontColor(this.model.campusID === id ? AppTheme.onPrimary() : AppTheme.text())
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(30)
              .backgroundColor(this.model.campusID === id ?
                AppTheme.primaryFill() : Color.Transparent)
              .borderRadius(6)
              .onClick(() => {
                this.model.campusID = id;
              })
          }, (id: string) => 'default.campus.' + id)
        }
        .width('100%')
        .padding(2)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.border() })
        .backgroundColor(AppTheme.background())

        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(16)
              .fontColor([AppTheme.onPrimary()])
            Text('保存设置')
              .fontSize(14)
              .fontColor(AppTheme.onPrimary())
          }
        }
        .type(ButtonType.Normal)
        .borderRadius(6)
        .backgroundColor(AppTheme.primaryFill())
        .width('100%')
        .height(36)
        .enabled(!this.model.isSampleMode())
        .onClick(() => {
          this.model.saveSettings();
        })

        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(16)
              .fontColor([AppTheme.text()])
            Text(this.model.isRefreshingSchedule ? '正在获取…' : '获取/刷新个人课表')
              .fontSize(14)
              .fontColor(AppTheme.text())
          }
        }
        .type(ButtonType.Normal)
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .backgroundColor(AppTheme.background())
        .width('100%')
        .height(36)
        .enabled(!this.model.isRefreshingSchedule && !this.model.isSampleMode())
        .onClick(() => {
          const work: Promise<void> = (async (): Promise<void> => {
            const saved: boolean = await this.model.saveSettings();
            if (saved) {
              await this.model.refreshSchedule();
            }
          })();
          work.catch(() => {
            // 已在内部处理。
          });
        })

        if (this.model.statusMessage.length > 0) {
          Text(this.model.statusMessage)
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  field(placeholder: string, value: string, key: string, inputType: InputType,
    onChangeValue: (value: string) => void) {
    TextInput({ placeholder: placeholder, text: value })
      .type(inputType)
      .fontSize(14)
      .fontColor(AppTheme.text())
      .placeholderColor(AppTheme.secondaryText())
      .backgroundColor(AppTheme.background())
      .borderRadius(6)
      .border({ width: 1, color: AppTheme.border() })
      .width('100%')
      .height(38)
      .enabled(!this.model.isSampleMode())
      .onChange((text: string) => {
        onChangeValue(text);
      })
  }

  @Builder
  notificationSurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.bell'), title: '课程提醒' })
        Row({ space: 8 }) {
          Text('每天 07:30 发送当日课程摘要')
            .fontSize(14)
            .fontColor(AppTheme.text())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.model.dailyCourseNotificationsEnabled })
            .selectedColor(AppTheme.primaryFill())
            .enabled(!this.model.isSampleMode() || this.model.isReviewDemo())
            .onChange((value: boolean) => {
              this.model.setDailyCourseNotificationsEnabled(value);
            })
        }
        .width('100%')

        Text('仅在当天有课时通知；课表更新或账号变更后会自动重排。')
          .fontSize(14)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
        if (this.model.dailyCourseNotificationStatusMessage.length > 0) {
          Text(this.model.dailyCourseNotificationStatusMessage)
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  localDataSurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.externaldrive'), title: '本地数据' })
        Text('清除已保存的教务账户与密码、个人课表、空教室和节假日缓存，并恢复本地设置。')
          .fontSize(14)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
        Button() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(16)
              .fontColor([AppTheme.danger()])
            Text('清除本地数据')
              .fontSize(14)
              .fontColor(AppTheme.danger())
          }
        }
        .type(ButtonType.Normal)
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.border() })
        .backgroundColor(AppTheme.background())
        .width('100%')
        .height(36)
        .enabled(!this.model.isSampleMode())
        .onClick(() => {
          this.getUIContext().showAlertDialog({
            title: '清除本地数据？',
            message: '此操作会删除本机保存的账户密码、个人课表、空教室和节假日缓存，且无法撤销。',
            primaryButton: {
              value: '取消',
              action: () => {
              }
            },
            secondaryButton: {
              value: '清除本地数据',
              fontColor: AppTheme.danger(),
              action: () => {
                this.model.clearLocalData();
              }
            }
          });
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  aboutSurface() {
    SurfaceCard() {
      Column({ space: 10 }) {
        SectionHeader({ icon: $r('sys.symbol.info_circle'), title: '关于本应用' })
        Text('Where To Study 是独立开发的非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。')
          .fontSize(14)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
        if (this.model.isSampleMode()) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.eye'))
              .fontSize(14)
              .fontColor([AppTheme.primary()])
            Text('内置示例模式已开启，不会连接教务服务或读写真实用户数据。')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.primary())
          }
          .width('100%')
          if (this.model.canExitSampleMode()) {
            this.borderedButton('返回真实数据', $r('sys.symbol.arrow_counterclockwise'), (): void => {
              this.model.exitReviewDemo();
            })
          }
        } else {
          this.borderedButton('浏览内置示例数据', $r('sys.symbol.eye'), (): void => {
            this.model.enterReviewDemo();
          }, !this.model.isImportingCalendar)
        }
        Divider()
          .color(AppTheme.border())
        this.borderedButton('隐私说明', $r('sys.symbol.lock'), (): void => {
          this.showingPrivacyPolicy = true;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  borderedButton(label: string, icon: Resource, action: () => void, interactive: boolean = true) {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph(icon)
          .fontSize(16)
          .fontColor([AppTheme.text()])
        Text(label)
          .fontSize(14)
          .fontColor(AppTheme.text())
      }
    }
    .type(ButtonType.Normal)
    .borderRadius(6)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.background())
    .width('100%')
    .height(36)
    .enabled(interactive)
    .opacity(interactive ? 1 : 0.5)
    .onClick(() => {
      if (interactive) {
        action();
      }
    })
  }
}
