// 以原生 Android SettingsPage.kt 为手机端视觉与交互基准的设置页。
import { AppModel } from '../model/AppModel';
import { AppMeta } from '../common/AppMeta';
import { AppTheme } from '../common/AppTheme';
import { AdaptiveLayoutPolicy, PhoneNavigationLayout } from '../common/DeviceState';
import { AppContext } from '../store/AppContext';
import { SemesterLogic, SemesterSuggestion } from '../common/SemesterLogic';
import { PrivacyPolicyView } from './PrivacyPolicyView';
import {
  TodayCourseWidgetData, WidgetCoursePreferences, WidgetArchive, CoursePhase
} from '../widget/TodayCourseWidgetData';
import { AppLanguage, AppLanguageInfo } from '../common/AppLocalization';
import { PublicDeadlineItem, PublicDeadlineKindInfo,
  PublicDeadlineSource } from '../net/CalendarDailyInfoClient';

@ComponentV2
export struct SettingsView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param favoriteManagerOnly: boolean = false;
  @Event onFavoriteManagerVisibilityChanged: (visible: boolean) => void = () => {
  };
  @Local contentWidth: number = 350;
  @Local showingPrivacyPolicy: boolean = false;
  @Local customDeadlineURLDraft: string = '';
  // 样式预览容量（紧凑 1 / 标准 3 / 展开 6，对应 Android 预览 Spinner）。
  @Local previewCapacity: number = 3;
  private statusDismissRevision: number = 0;

  private static readonly projectURL: string =
    'https://github.com/Nemoyuzx/where_to_study';

  aboutToAppear(): void {
    this.customDeadlineURLDraft = this.model.customDeadlinesURL;
  }

  build() {
    if (this.showingPrivacyPolicy) {
      PrivacyPolicyView({
        onClose: (): void => {
          this.setPrivacyPolicyVisible(false);
        }
      })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    } else if (this.favoriteManagerOnly) {
      this.favoriteManagerView()
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

  private setFavoriteManagerVisible(visible: boolean): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.onFavoriteManagerVisibilityChanged(visible);
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

  private openAppFilingPage(): void {
    try {
      AppContext.get().openLink(AppMeta.appFilingURL);
    } catch (e) {
      // 系统无法打开链接时保持在当前页。
    }
  }

  @Builder
  settingsContent() {
    Scroll() {
      Column({ space: 16 }) {
        this.settingsTitle()
        this.referenceNotice()
        this.reviewDemoSurface()
        if (AdaptiveLayoutPolicy.useTwoColumn(this.contentWidth)) {
          Row({ space: 16 }) {
            Column({ space: 16 }) {
              this.accountSurface()
              this.semesterSurface()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 16 }) {
              this.notificationSurface()
              this.dailyInfoSurface()
              this.widgetSurface()
              this.languageSurface()
              this.aboutSurface()
              this.localDataSurface()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
        } else {
          Column({ space: 16 }) {
            this.accountSurface()
            this.semesterSurface()
            this.notificationSurface()
            this.dailyInfoSurface()
            this.widgetSurface()
            this.languageSurface()
            this.aboutSurface()
            this.localDataSurface()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .padding({
        left: 20,
        right: 20,
        top: this.isCompact() ? 16 : 20,
        bottom: this.isCompact() ? PhoneNavigationLayout.minimumContentBottomInsetVp : 28
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
      Text(this.model.text('设置'))
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
  referenceNotice() {
    Column({ space: 4 }) {
      Text(this.model.text('显示数据仅供参考，请以实际情况为准。'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.text())
    }
    .padding(12)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  reviewDemoSurface() {
    Column({ space: 8 }) {
      if (this.model.isSampleMode()) {
        Text(this.model.text('内置示例模式已开启，不会连接教务服务或读写真实用户数据。'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.primary())
          .lineHeight(18)
          .width('100%')
        if (this.model.canExitSampleMode()) {
          this.linkButton('返回真实数据', (): void => {
            this.model.exitReviewDemo();
          })
        }
      } else {
        Text(this.model.text('无需教务账号即可浏览内置虚构课表、空教室和教学日历。'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
          .lineHeight(18)
          .width('100%')
        this.linkButton('浏览内置示例数据', (): void => {
          this.model.enterReviewDemo();
        }, this.model.canEnterReviewDemo())
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sectionTitle(title: string) {
    Text(this.model.text(title))
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.text())
      .width('100%')
      .padding({ bottom: 12 })
  }

  @Builder
  segmentedOptions(labels: string[], selectedIndex: number,
    onSelect: (index: number) => void, compactText: boolean = false) {
    Row() {
      ForEach(labels, (label: string, index: number) => {
        Text(label)
          .fontSize(compactText ? 11 : 13.5)
          .fontWeight(selectedIndex === index ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(AppTheme.text())
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .layoutWeight(1)
          .height(32)
          .backgroundColor(selectedIndex === index ?
            AppTheme.segmentedSelection() : Color.Transparent)
          .borderRadius(6)
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
              onSelect(index);
            });
          })
      }, (label: string, index: number) => 'segment.' + label + '.' + index.toString())
    }
    .width('100%')
    .height(38)
    .padding(3)
    .borderRadius(9)
    .backgroundColor(AppTheme.surfaceVariant())
  }

  @Builder
  languageSurface() {
    Column({ space: 8 }) {
      this.sectionTitle('语言')
      this.segmentedOptions([
        AppLanguageInfo.label(AppLanguage.system, this.model.resolvedLanguage()),
        AppLanguageInfo.label(AppLanguage.simplifiedChinese, this.model.resolvedLanguage()),
        AppLanguageInfo.label(AppLanguage.english, this.model.resolvedLanguage())
      ], AppLanguageInfo.all.indexOf(this.model.languageSetting()), (index: number): void => {
          const target: AppLanguage = AppLanguageInfo.all[Math.min(Math.max(index, 0), 2)];
          this.model.setLanguageSetting(target);
        }, true)
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .id('settings_language_surface')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  accountSurface() {
    Column() {
      this.sectionTitle('个人账户')

      this.field('教务账号', this.model.account, InputType.Normal, (value: string): void => {
        this.model.account = value;
      }, true, 'settings_account_input')
      Blank().height(7)
      this.field('密码', this.model.password, InputType.Password, (value: string): void => {
        this.model.password = value;
      }, true, 'settings_password_input')
      if (this.model.canPreserveSavedPassword()) {
        Text(this.model.text('密码已安全保存，留空保持不变'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
          .padding({ left: 2, right: 2, top: 7 })
      }
      Text(this.model.text('默认校区'))
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: this.isCompact() ? 10 : 16, bottom: this.isCompact() ? 5 : 7 })
      this.segmentedOptions(
        [this.model.text('西土城'), this.model.text('沙河')],
        this.model.campusID === '04' ? 1 : 0,
        (index: number): void => {
          this.model.campusID = index === 1 ? '04' : '01';
        })

      Blank().height(this.isCompact() ? 12 : 18)
      Button(this.model.text('保存设置'))
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
      Button(this.model.isRefreshingSchedule ? this.model.text('正在获取…') :
        this.model.text('获取/刷新个人课表'))
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

      Text(this.model.text('账号和密码仅保存于本机，并由 HarmonyOS ASSET 安全存储保护。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: this.isCompact() ? 8 : 12 })

      Blank().height(7)
      Button(this.model.text('阅读隐私政策'))
        .type(ButtonType.Normal)
        .stateEffect(true)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.primary())
        .borderRadius(6)
        .border({ width: 1, color: AppTheme.primary() })
        .backgroundColor(AppTheme.surface())
        .width('100%')
        .height(36)
        .id('settings_account_privacy_policy')
        .accessibilityText(this.model.text('阅读隐私政策'))
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          this.setPrivacyPolicyVisible(true);
        })

      if (this.model.statusMessage.length > 0) {
        Text(this.model.text(this.model.statusMessage))
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
    onChangeValue: (value: string) => void, enabled: boolean = true,
    accessibilityID: string = '') {
    TextInput({ placeholder: this.model.text(placeholder), text: value })
      .id(accessibilityID)
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
      .enabled(!this.model.isSampleMode() && enabled)
      .opacity(this.model.isSampleMode() || !enabled ? 0.62 : 1)
      .focusable(true)
      .focusOnTouch(true)
      .enableKeyboardOnFocus(true)
      .onChange((text: string) => {
        onChangeValue(text);
      })
  }

  // 学期设置独立卡片（对齐 Android SettingsPage.semesterSurface）：
  // 自动检测开关 + 手动学期字段（自动检测开启时禁用）+ 说明 + 保存学期设置。
  @Builder
  semesterSurface() {
    Column() {
      this.sectionTitle('学期设置')
      Row({ space: 8 }) {
        Text(this.model.text('自动检测当前学期'))
          .fontSize(15)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.automaticTermDetection })
          .selectedColor(AppTheme.primaryFill())
          .width(48)
          .height(28)
          .enabled(!this.model.isSampleMode())
          .onChange((value: boolean) => {
            this.model.automaticTermDetection = value;
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 36 })
      .alignItems(VerticalAlign.Center)

      Blank().height(7)
      this.field('学期编号', this.model.termID, InputType.Normal, (value: string): void => {
        this.model.termID = value;
      }, !this.model.automaticTermDetection)
      Blank().height(7)
      this.field('第一周周一（YYYY-MM-DD）', this.model.termStartDate, InputType.Normal,
        (value: string): void => {
          this.model.termStartDate = value;
        }, !this.model.automaticTermDetection)

      Text(this.model.text(this.model.automaticTermDetection ?
        '启动或获取/刷新课表后，会自动应用教务返回的学期与开学日期。' :
        '关闭自动检测后，将使用手动填写的学期信息。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
        .padding({ left: 2, right: 2, top: 8 })

      Blank().height(this.isCompact() ? 10 : 12)
      Button(this.model.text('保存学期设置'))
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
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          const work: Promise<boolean> = this.model.saveSemesterSettings();
          work.then((saved: boolean) => {
            if (saved) {
              this.dismissStatusMessageAfter(this.model.statusMessage);
            }
          }).catch(() => {
            // 错误说明已由 AppModel 写入状态消息。
          });
        })
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  // 桌面小组件设置卡片（对齐 Android widgetSurface）：
  // 显示课程地点/任课教师开关 + 课程数量 + 样式预览。
  @Builder
  widgetSurface() {
    Column() {
      this.sectionTitle('桌面小组件')

      Row({ space: 8 }) {
        Text(this.model.text('显示课程地点'))
          .fontSize(15)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.widgetShowsLocation })
          .selectedColor(AppTheme.primaryFill())
          .width(48)
          .height(28)
          .enabled(!this.model.isSampleMode())
          .onChange((value: boolean) => {
            this.model.setWidgetShowsLocation(value);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 36 })
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Text(this.model.text('显示任课教师'))
          .fontSize(15)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.widgetShowsTeacher })
          .selectedColor(AppTheme.primaryFill())
          .width(48)
          .height(28)
          .enabled(!this.model.isSampleMode())
          .onChange((value: boolean) => {
            this.model.setWidgetShowsTeacher(value);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: 36 })
      .alignItems(VerticalAlign.Center)

      Text(this.model.text('显示课程数量'))
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: this.isCompact() ? 10 : 14, bottom: 5 })
      this.segmentedOptions(['1', '2', '3', '4', '5', '6'],
        this.model.widgetCourseLimit - 1, (index: number): void => {
          this.model.setWidgetCourseLimit(index + 1);
        }, true)

      Divider()
        .strokeWidth(1)
        .color(AppTheme.border())
        .margin({ top: 14, bottom: 12 })

      Text(this.model.text('样式预览 · 示例内容'))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .width('100%')
      this.segmentedOptions(
        [this.model.text('紧凑'), this.model.text('标准'), this.model.text('展开')],
        this.previewCapacity === 1 ? 0 : (this.previewCapacity === 6 ? 2 : 1),
        (index: number): void => {
          this.previewCapacity = index === 0 ? 1 : (index === 2 ? 6 : 3);
        })

      this.widgetPreview()
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  // 样式预览：用示例归档 + 当前偏好生成绑定数据并渲染（对应 Android 预览）。
  @Builder
  widgetPreview() {
    Column() {
      this.widgetPreviewRow(
        this.previewString('todayTitle'), this.previewString('todayCountText'),
        this.previewString('dateContext'), this.previewString('statusText'),
        this.previewString('course1Name'), this.previewString('course1Details'),
        this.previewBoolean('course1Highlighted'),
        this.previewString('course2Name'), this.previewString('course2Details'),
        this.previewBoolean('course2Highlighted'),
        this.previewString('course3Name'), this.previewString('course3Details'),
        this.previewBoolean('course3Highlighted'),
        this.previewString('course4Name'), this.previewString('course4Details'),
        this.previewBoolean('course4Highlighted'),
        this.previewString('course5Name'), this.previewString('course5Details'),
        this.previewBoolean('course5Highlighted'),
        this.previewString('course6Name'), this.previewString('course6Details'),
        this.previewBoolean('course6Highlighted'))
    }
    .padding(14)
    .margin({ top: 8 })
    .width('100%')
    .height(this.previewCapacity === 1 ? 130 :
      (this.previewCapacity === 6 ? 300 : 205))
    .borderRadius(16)
    .backgroundColor(AppTheme.surface())
    .border({ width: 1, color: AppTheme.border() })
    .alignItems(HorizontalAlign.Start)
    .clip(true)
  }

  private previewData(): Record<string, Object> {
    const prefs: WidgetCoursePreferences = new WidgetCoursePreferences(
      this.model.widgetShowsLocation, this.model.widgetShowsTeacher,
      Math.min(this.model.widgetCourseLimit, this.previewCapacity), this.model.resolvedLanguage());
    return TodayCourseWidgetData.binding(
      TodayCourseWidgetData.previewArchive(), prefs, undefined,
      TodayCourseWidgetData.nowMinute());
  }

  private previewString(key: string): string {
    return String(this.previewData()[key] ?? '');
  }

  private previewBoolean(key: string): boolean {
    return this.previewData()[key] === true;
  }

  @Builder
  widgetPreviewRow(title: string, count: string, context: string, status: string,
    n1: string, d1: string, h1: boolean, n2: string, d2: string, h2: boolean,
    n3: string, d3: string, h3: boolean, n4: string, d4: string, h4: boolean,
    n5: string, d5: string, h5: boolean, n6: string, d6: string, h6: boolean) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      Blank()
      Text(count)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.secondaryText())
    }
    .width('100%')
    .height(26)
    .alignItems(VerticalAlign.Center)
    Text(context.length > 0 && status.length > 0 ? context + ' · ' + status : context)
      .fontSize(11)
      .fontColor(AppTheme.secondaryText())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .margin({ top: 2 })
    Blank().height(6)
    Column({ space: 0 }) {
      if (n1.length > 0) {
        this.widgetPreviewRowItem(n1, d1, h1)
      }
      if (n2.length > 0) {
        this.widgetPreviewRowItem(n2, d2, h2)
      }
      if (n3.length > 0) {
        this.widgetPreviewRowItem(n3, d3, h3)
      }
      if (n4.length > 0) {
        this.widgetPreviewRowItem(n4, d4, h4)
      }
      if (n5.length > 0) {
        this.widgetPreviewRowItem(n5, d5, h5)
      }
      if (n6.length > 0) {
        this.widgetPreviewRowItem(n6, d6, h6)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  widgetPreviewRowItem(name: string, details: string, highlighted: boolean) {
    Row() {
      Column()
        .width(3)
        .height(26)
        .borderRadius(1.5)
        .backgroundColor(highlighted ? AppTheme.primaryFill() : AppTheme.accent())
      Column({ space: 1 }) {
        Text(name)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(details)
          .fontSize(10)
          .fontColor(AppTheme.secondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
    }
    .width('100%')
    .height(34)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  dailyInfoSurface() {
    Column() {
      this.sectionTitle('日期详情与生活信息')
      this.featureToggle('校区天气', this.model.weatherEnabled, (value: boolean): void => {
        this.model.setWeatherEnabled(value);
      })
      this.featureToggle('黄历与宜忌', this.model.almanacEnabled, (value: boolean): void => {
        this.model.setAlmanacEnabled(value);
      })
      Divider()
        .color(AppTheme.border())
        .margin({ top: 8, bottom: 8 })
      this.deadlineLegend('课程作业 DDL', AppTheme.assignment())
      this.featureToggle('学科竞赛 DDL', this.model.competitionDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setCompetitionDeadlinesEnabled(value);
        }, AppTheme.competitionDeadline(), true)
      this.featureToggle('学术会议/期刊专题 DDL', this.model.conferenceDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setConferenceDeadlinesEnabled(value);
        }, AppTheme.conferenceDeadline(), true)
      this.featureToggle('校内竞赛通知', this.model.schoolContestNoticesEnabled,
        (value: boolean): void => {
          this.model.setSchoolContestNoticesEnabled(value);
        }, AppTheme.schoolNotice(), true)
      this.featureToggle('夏令营/预推免 DDL', this.model.summerCampDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setSummerCampDeadlinesEnabled(value);
        }, AppTheme.summerCampDeadline(), true)
      this.featureToggle('黑客松 DDL', this.model.hackathonDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setHackathonDeadlinesEnabled(value);
        }, AppTheme.hackathonDeadline(), true)

      Divider()
        .color(AppTheme.border())
        .margin({ top: 8, bottom: 8 })
      this.field('自定义日程 HTTPS 地址', this.customDeadlineURLDraft, InputType.Normal,
        (value: string): void => {
          this.customDeadlineURLDraft = value;
        })
      Blank().height(7)
      this.linkButton('保存自定义日程地址', (): void => {
        this.model.setCustomDeadlinesURL(this.customDeadlineURLDraft).then((saved: boolean): void => {
          if (saved) {
            this.customDeadlineURLDraft = this.model.customDeadlinesURL;
            this.model.statusMessage = '自定义日程地址已保存';
          }
        }).catch(() => {
          this.model.statusMessage = '无法保存自定义日程地址';
        });
      })
      this.featureToggle('显示自定义日程', this.model.customDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setCustomDeadlinesEnabled(value).catch(() => {
            this.model.statusMessage = '无法保存自定义日程开关';
          });
        }, AppTheme.customDeadline(), true)
      this.linkButton('收藏管理', (): void => {
        this.setFavoriteManagerVisible(true);
      })

      Text(this.model.text('天气、黄历和 DDL 来自第三方公开服务；校内竞赛通知由脚本从学校内部网站公开通知页提取整理，各卡片底部会标明具体来源。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
        .padding({ top: 7 })
    }
    .padding(16)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deadlineLegend(label: string, markerColor: ResourceColor) {
    Row({ space: 8 }) {
      Text(this.model.text(label))
        .fontSize(15)
        .fontColor(AppTheme.text())
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(markerColor)
    }
    .width('100%')
    .constraintSize({ minHeight: 36 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  featureToggle(label: string, isOn: boolean, onChangeValue: (value: boolean) => void,
    markerColor: ResourceColor = Color.Transparent, showsMarker: boolean = false) {
    Row({ space: 8 }) {
      Row({ space: 6 }) {
        Text(this.model.text(label))
          .fontSize(15)
          .fontColor(AppTheme.text())
        if (showsMarker) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(markerColor)
        }
      }
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(AppTheme.primaryFill())
        .width(48)
        .height(28)
        .enabled(!this.model.isSampleMode())
        .onChange((value: boolean) => {
          onChangeValue(value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 36 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  notificationSurface() {
    Column() {
      this.sectionTitle('课程提醒')
      Row({ space: 8 }) {
        Text(this.model.text('每天 07:30 发送当日课程摘要'))
          .fontSize(15)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.dailyCourseNotificationsEnabled })
          .id('settings_daily_course_notification_toggle')
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

      Text(this.model.text('仅在当天有课时通知；课表更新或账号变更后会自动重排。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: 4 })
      if (this.model.dailyCourseNotificationStatusMessage.length > 0) {
        Text(this.model.text(this.model.dailyCourseNotificationStatusMessage))
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
      Text(this.model.text('个人课表、空教室缓存、节假日缓存、自定义日程设置、收藏、账号与偏好均只保存在本机。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
        .padding({ bottom: this.isCompact() ? 8 : 12 })
      Button(this.model.text('清除本地数据'))
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
            title: this.model.text('清除全部本地数据？'),
            message: this.model.text('将删除保存的账号、密码、个人课表、空教室缓存、自定义日程设置、收藏和其它设置。此操作无法撤销。'),
            primaryButton: {
              value: this.model.text('取消'),
              action: () => {
              }
            },
            secondaryButton: {
              value: this.model.text('确认清除'),
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
    .id('settings_local_data_surface')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  favoriteManagerView() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([AppTheme.primary()])
        }
        .type(ButtonType.Normal)
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .accessibilityText(this.model.text('返回设置'))
        .onClick(() => {
          this.setFavoriteManagerVisible(false);
        })
        Text(this.model.text('收藏管理'))
          .fontSize(this.isCompact() ? 24 : 28)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.model.favoriteDeadlines.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.star'))
            .fontSize(34)
            .fontColor([AppTheme.secondaryText()])
          Text(this.model.text('暂无收藏日程'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.text())
          Text(this.model.text('在日程详情右侧点击星标后，即使关闭来源或上游删除条目，收藏仍会保存在本机。'))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
            .lineHeight(17)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .padding(22)
        .width('100%')
        .borderRadius(8)
        .backgroundColor(AppTheme.surface())
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.model.favoriteDeadlines, (item: PublicDeadlineItem) => {
              this.favoriteDeadlineRow(item)
            }, (item: PublicDeadlineItem) => this.model.favoriteDeadlineKey(item))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .alignItems(HorizontalAlign.Start)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width) - 40;
    })
  }

  @Builder
  favoriteDeadlineRow(item: PublicDeadlineItem) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .maxLines(2)
          .width('100%')
        Text(this.favoriteDeadlineSubtitle(item))
          .fontSize(11)
          .fontColor(AppTheme.secondaryText())
          .maxLines(2)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button() {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(19)
          .fontColor([AppTheme.assignment()])
      }
      .type(ButtonType.Normal)
      .width(38)
      .height(38)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.model.text('取消收藏'))
      .onClick(() => {
        this.model.removeFavoriteDeadline(item).catch(() => {
          this.model.statusMessage = '无法删除收藏';
        });
      })
    }
    .padding(13)
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(VerticalAlign.Center)
  }

  private favoriteDeadlineSubtitle(item: PublicDeadlineItem): string {
    const source: string = item.source === PublicDeadlineSource.schoolNotice ?
      this.model.text('校内竞赛通知') :
      (item.source === PublicDeadlineSource.custom ? this.model.text('自定义日程') :
        this.model.text(PublicDeadlineKindInfo.title(item.kind)));
    const time: string = item.deadline.length >= 16 ?
      item.deadline.substring(0, 16).replace('T', ' ') : item.deadline;
    return time + ' · ' + source;
  }

  @Builder
  aboutSurface() {
    Column() {
      this.sectionTitle('关于本应用')
      Text('Where To Study  ' + AppMeta.version + '\n' + this.model.text(
        '北邮课表与空教室查询的独立非官方客户端，不由北京邮电大学运营。'))
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(18)
        .width('100%')
        .padding({ bottom: this.isCompact() ? 8 : 12 })

      Button(this.model.text(AppMeta.appFilingLabel))
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
        .id('settings.app_filing')
        .accessibilityText(this.model.text(AppMeta.appFilingLabel))
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onClick(() => {
          this.openAppFilingPage();
        })
      Blank().height(7)
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
    .id('settings_about_surface')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  linkButton(label: string, action: () => void, enabled: boolean = true) {
    Button(this.model.text(label))
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
      .enabled(enabled)
      .opacity(enabled ? 1 : 0.62)
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
      .onClick(() => {
        action();
      })
  }
}
