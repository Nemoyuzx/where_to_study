// 与 Android MainActivity 对应的根布局：
// 宽度 >= 700vp 时使用侧栏（对应 NavigationSplitView 的 regular 布局），
// 否则使用底部 Tabs（对应 compact 布局）；示例模式顶部显示提示条。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppModel } from '../model/AppModel';
import { AppSection, AppSectionInfo } from '../common/AppSection';
import { AppTheme } from '../common/AppTheme';
import { PlannerView } from './PlannerView';
import { CalendarSectionView } from './CalendarSectionView';
import { SettingsView } from './SettingsView';

// 布局策略统一在 common/DeviceState.ets 中（含折叠屏半折叠降级规则），
// 这里保留导出以兼容旧引用。
import { AdaptiveLayoutPolicy, DeviceState } from '../common/DeviceState';
export { AdaptiveLayoutPolicy };

@ComponentV2
export struct RootView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local currentSection: AppSection = AppSection.planner;
  // 初始值按屏幕宽度预估，避免宽屏启动首帧闪 Tabs（BUG-022 修复）。
  @Local containerWidth: number = DeviceState.screenWidthVp();
  private deadlineRefreshTimer: number = -1;

  private sidebarWidth(): number {
    return this.containerWidth < 1000 ? 210 : 230;
  }

  aboutToAppear(): void {
    // 与 iOS 端 AppModel.init + RootView.onAppear 对应：引导加载后按需刷新当天教室。
    this.model.launch();
    this.model.refreshClassroomsIfNeeded();
    if (this.deadlineRefreshTimer < 0) {
      this.deadlineRefreshTimer = setInterval(() => {
        this.model.prewarmPublicDeadlines();
      }, 5 * 60 * 1000 + 1000);
    }
  }

  aboutToDisappear(): void {
    if (this.deadlineRefreshTimer >= 0) {
      clearInterval(this.deadlineRefreshTimer);
      this.deadlineRefreshTimer = -1;
    }
  }

  onPageShow(): void {
    // 对应 iOS scenePhase == .active 时的刷新。
    this.model.refreshClassroomsIfNeeded();
    this.model.refreshDailyCourseNotificationAuthorization();
    this.model.refreshSystemLanguage();
    this.model.prewarmPublicDeadlines();
  }

  private handleDesktopSectionKey(event: KeyEvent): boolean {
    if (!AdaptiveLayoutPolicy.useSidebar(this.containerWidth) ||
      event.type !== KeyType.Down || event.metaKey === 0) {
      return false;
    }
    const index: number = event.keyCode === 2001 ? 0 :
      (event.keyCode === 2002 ? 1 : (event.keyCode === 2003 ? 2 : -1));
    const section: AppSection | undefined = this.sectionAt(index);
    if (section === undefined) {
      return false;
    }
    this.selectSection(section);
    return true;
  }

  build() {
    Column() {
      if (this.model.isSampleMode()) {
        this.sampleModeBanner()
      }
      if (AdaptiveLayoutPolicy.useSidebar(this.containerWidth)) {
        this.sidebarLayout()
      } else {
        this.tabLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .focusable(AdaptiveLayoutPolicy.useSidebar(this.containerWidth))
    .focusOnTouch(AdaptiveLayoutPolicy.useSidebar(this.containerWidth))
    .onKeyEvent((event: KeyEvent): boolean => this.handleDesktopSectionKey(event))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.containerWidth = Number(newArea.width);
    })
  }

  @Builder
  sampleModeBanner() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.eye'))
        .fontSize(14)
        .fontColor([AppTheme.text()])
      Text(this.model.text('示例数据 · 不连接北邮教务服务'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.text())
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.accent())
  }

  @Builder
  sidebarLayout() {
    Row() {
      this.sidebar()
      Divider()
        .vertical(true)
        .color(AppTheme.border())
      Column() {
        // 注意：@ComponentV2 中 @Builder 方法的参数变化不会触发重渲染，
        // 因此这里在 build() 的直接子树中内联 currentSection 分支，
        // 保证侧栏切换一级页面时内容区随之更新。
        if (this.currentSection === AppSection.planner) {
          PlannerView()
        } else if (this.currentSection === AppSection.calendar) {
          CalendarSectionView({ containerWidth: this.containerWidth - this.sidebarWidth() })
        } else {
          SettingsView()
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sidebar() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('BUPT')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
        Text('Where To Study')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 24, right: 24 })

      Divider()
        .color(AppTheme.border())

      ForEach(AppSectionInfo.all, (section: AppSection) => {
        Row({ space: 8 }) {
          SymbolGlyph(AppSectionInfo.symbol(section))
            .fontSize(18)
            .fontColor([AppTheme.text()])
          Text(this.model.text(AppSectionInfo.title(section)))
            .fontSize(16)
            .fontWeight(this.currentSection === section ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(AppTheme.text())
        }
        .width('100%')
        .height(36)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .backgroundColor(this.currentSection === section ? AppTheme.selection() : Color.Transparent)
        .onClick(() => {
          this.selectSection(section);
        })
      }, (section: AppSection) => AppSectionInfo.accessibilityId(section))
    }
    .width(this.sidebarWidth())
    .height('100%')
    .padding({ top: 16 })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tabLayout() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.currentSection === AppSection.planner) {
          PlannerView()
        } else if (this.currentSection === AppSection.calendar) {
          CalendarSectionView({ containerWidth: this.containerWidth })
        } else {
          SettingsView()
        }
      }
      .width('100%')
      .height('100%')

      Row({ space: 4 }) {
        ForEach(AppSectionInfo.all, (section: AppSection) => {
          this.phoneNavigationItem(section)
        }, (section: AppSection) => AppSectionInfo.accessibilityId(section))
      }
      .width('calc(100% - 88vp)')
      .height(60)
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .margin({ bottom: 10 })
      .borderRadius(30)
      .backgroundColor(AppTheme.surfaceVariant())
      .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
      .id('phone_navigation')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  phoneNavigationItem(section: AppSection) {
    Column({ space: 2 }) {
      SymbolGlyph(AppSectionInfo.symbol(section))
        .fontSize(22)
        .fontColor([this.currentSection === section ? AppTheme.primary() : AppTheme.secondaryText()])
      Text(this.model.text(AppSectionInfo.title(section)))
        .fontSize(11)
        .fontWeight(this.currentSection === section ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentSection === section ? AppTheme.primary() : AppTheme.secondaryText())
    }
    .layoutWeight(1)
    .height(50)
    .justifyContent(FlexAlign.Center)
    .borderRadius(26)
    .backgroundColor(this.currentSection === section ? AppTheme.background() : Color.Transparent)
    .id(AppSectionInfo.accessibilityId(section))
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.selectSection(section);
    })
  }

  @Builder
  sectionView(section: AppSection) {
    if (section === AppSection.planner) {
      PlannerView()
    } else if (section === AppSection.calendar) {
      CalendarSectionView({ containerWidth: this.containerWidth })
    } else {
      SettingsView()
    }
  }

  selectSection(section: AppSection): void {
    hilog.info(0x0000, 'RootView', 'selectSection -> %{public}s', section);
    this.currentSection = section;
    this.model.selectedSection = section;
  }

  private sectionIndexOf(section: AppSection): number {
    for (let i = 0; i < AppSectionInfo.all.length; i++) {
      if (AppSectionInfo.all[i] === section) {
        return i;
      }
    }
    return 0;
  }

  private sectionAt(index: number): AppSection | undefined {
    if (index < 0 || index >= AppSectionInfo.all.length) {
      return undefined;
    }
    return AppSectionInfo.all[index];
  }
}
