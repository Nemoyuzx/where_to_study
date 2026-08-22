// 以原生 Android SettingsPage.kt 为手机端视觉与交互基准的设置页。
import { AppModel } from '../model/AppModel';
import { AppMeta } from '../common/AppMeta';
import { AppTheme } from '../common/AppTheme';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { AppContext } from '../store/AppContext';
import { SemesterLogic, SemesterSuggestion } from '../common/SemesterLogic';
import { PrivacyPolicyView } from './PrivacyPolicyView';
import {
  TodayCourseWidgetData, WidgetCoursePreferences, WidgetArchive, CoursePhase
} from '../widget/TodayCourseWidgetData';

@ComponentV2
export struct SettingsView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local contentWidth: number = 350;
  @Local showingPrivacyPolicy: boolean = false;
  // 样式预览容量（紧凑 1 / 标准 3 / 展开 6，对应 Android 预览 Spinner）。
  @Local previewCapacity: number = 3;
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
            this.semesterSurface()
            this.notificationSurface()
            this.dailyInfoSurface()
            this.widgetSurface()
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
    onChangeValue: (value: string) => void, enabled: boolean = true) {
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
      .enabled(!this.model.isSampleMode() && enabled)
      .opacity(this.model.isSampleMode() || !enabled ? 0.62 : 1)
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
        Text('自动检测当前学期')
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

      Text(this.model.automaticTermDetection ?
        '获取/刷新课表后会自动应用教务返回的学期与开学日期。' :
        '关闭自动检测后，将使用手动填写的学期信息。')
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
        .padding({ left: 2, right: 2, top: 8 })

      Blank().height(this.isCompact() ? 10 : 12)
      Button('保存学期设置')
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
        Text('显示课程地点')
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
        Text('显示任课教师')
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

      Text('显示课程数量')
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ top: this.isCompact() ? 10 : 14, bottom: 5 })
      Select([{ value: '1 门' }, { value: '2 门' }, { value: '3 门' }, { value: '4 门' },
        { value: '5 门' }, { value: '6 门' }])
        .selected(this.model.widgetCourseLimit - 1)
        .value(this.model.widgetCourseLimit.toString() + ' 门')
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
          this.model.setWidgetCourseLimit(index + 1);
        })

      Divider()
        .strokeWidth(1)
        .color(AppTheme.border())
        .margin({ top: 14, bottom: 12 })

      Text('样式预览 · 示例内容')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .width('100%')
      Select([{ value: '紧凑' }, { value: '标准' }, { value: '展开' }])
        .selected(this.previewCapacity === 1 ? 0 : (this.previewCapacity === 6 ? 2 : 1))
        .value(this.previewCapacity === 1 ? '紧凑' : (this.previewCapacity === 6 ? '展开' : '标准'))
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
        .margin({ top: 7 })
        .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
        .onSelect((index: number) => {
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
      Math.min(this.model.widgetCourseLimit, this.previewCapacity));
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
      this.featureToggle('学科竞赛 DDL', this.model.competitionDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setCompetitionDeadlinesEnabled(value);
        })
      this.featureToggle('夏令营 DDL', this.model.summerCampDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setSummerCampDeadlinesEnabled(value);
        })
      this.featureToggle('黑客松 DDL', this.model.hackathonDeadlinesEnabled,
        (value: boolean): void => {
          this.model.setHackathonDeadlinesEnabled(value);
        })

      Text('天气、黄历和 DDL 来自第三方公开服务；学科竞赛同时包含北邮校内通知，各卡片底部会标明具体来源。')
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
  featureToggle(label: string, isOn: boolean, onChangeValue: (value: boolean) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(15)
        .fontColor(AppTheme.text())
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
