// 与 Android MainActivity 对应的根布局：
// 宽度 >= 700vp 时使用侧栏（对应 NavigationSplitView 的 regular 布局），
// 否则使用底部 Tabs（对应 compact 布局）；示例模式顶部显示提示条。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppModel } from '../model/AppModel';
import { AppSection, AppSectionInfo } from '../common/AppSection';
import { AppTheme } from '../common/AppTheme';
import { PlannerView } from './PlannerView';
import { CalendarSectionView } from './CalendarSectionView';
import { SettingsView } from './SettingsView';
import { QueryView } from './QueryView';

// 布局策略统一在 common/DeviceState.ets 中（含折叠屏半折叠降级规则），
// 这里保留导出以兼容旧引用。
import { AdaptiveLayoutPolicy, DeviceState, PhoneNavigationLayout } from '../common/DeviceState';
export { AdaptiveLayoutPolicy };

@ComponentV2
export struct RootView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local currentSection: AppSection = AppSection.planner;
  // 初始值按屏幕宽度预估，避免宽屏启动首帧闪 Tabs（BUG-022 修复）。
  @Local containerWidth: number = DeviceState.screenWidthVp();
  @Local settingsFavoriteManagerVisible: boolean = false;
  @Local phoneNavigationBottomMargin: number = PhoneNavigationLayout.minimumBottomClearanceVp;
  private deadlineRefreshTimer: number = -1;
  private navigationWindow: window.Window | null = null;
  private navigationAvoidAreaListener: ((options: window.AvoidAreaOptions) => void) | null = null;
  private navigationAvoidanceActive: boolean = false;

  private sidebarWidth(): number {
    return this.containerWidth < 1000 ? 210 : 230;
  }

  aboutToAppear(): void {
    this.navigationAvoidanceActive = true;
    this.attachPhoneNavigationAvoidance();
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
    this.navigationAvoidanceActive = false;
    this.detachPhoneNavigationAvoidance();
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
    if (this.navigationWindow !== null) {
      this.refreshPhoneNavigationBottomMargin(this.navigationWindow);
    }
  }

  private attachPhoneNavigationAvoidance(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      return;
    }
    window.getLastWindow(hostContext).then((mainWindow: window.Window): void => {
      if (!this.navigationAvoidanceActive) {
        return;
      }
      this.detachPhoneNavigationAvoidance();
      this.navigationWindow = mainWindow;
      this.refreshPhoneNavigationBottomMargin(mainWindow);
      const listener = (options: window.AvoidAreaOptions): void => {
        if (options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR ||
          options.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.refreshPhoneNavigationBottomMargin(mainWindow);
        }
      };
      this.navigationAvoidAreaListener = listener;
      mainWindow.on('avoidAreaChange', listener);
    }).catch(() => {
      // 获取窗口失败时仍保留 28vp 的审核安全下限。
      this.phoneNavigationBottomMargin = PhoneNavigationLayout.minimumBottomClearanceVp;
    });
  }

  private detachPhoneNavigationAvoidance(): void {
    if (this.navigationWindow !== null && this.navigationAvoidAreaListener !== null) {
      try {
        this.navigationWindow.off('avoidAreaChange', this.navigationAvoidAreaListener);
      } catch (e) {
        // 窗口销毁期间注销失败不会影响后续实例重新注册。
      }
    }
    this.navigationWindow = null;
    this.navigationAvoidAreaListener = null;
  }

  private visibleBottomInsetVp(mainWindow: window.Window, type: window.AvoidAreaType): number {
    try {
      const area: window.AvoidArea = mainWindow.getWindowAvoidArea(type);
      if (!area.visible) {
        return 0;
      }
      return this.getUIContext().px2vp(area.bottomRect.height);
    } catch (e) {
      return 0;
    }
  }

  private refreshPhoneNavigationBottomMargin(mainWindow: window.Window): void {
    const navigationIndicatorInsetVp: number = this.visibleBottomInsetVp(
      mainWindow, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const systemInsetVp: number = this.visibleBottomInsetVp(
      mainWindow, window.AvoidAreaType.TYPE_SYSTEM);
    this.phoneNavigationBottomMargin = PhoneNavigationLayout.bottomMarginFor(
      navigationIndicatorInsetVp, systemInsetVp);
  }

  private handleDesktopSectionKey(event: KeyEvent): boolean {
    if (!AdaptiveLayoutPolicy.useSidebar(this.containerWidth) ||
      event.type !== KeyType.Down || event.metaKey === 0) {
      return false;
    }
    const index: number = event.keyCode === 2001 ? 0 :
      (event.keyCode === 2002 ? 1 :
        (event.keyCode === 2003 ? 2 : (event.keyCode === 2004 ? 3 : -1)));
    const section: AppSection | undefined = this.sectionAt(index);
    if (section === undefined) {
      return false;
    }
    this.selectSection(section);
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
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

      if (this.settingsFavoriteManagerVisible) {
        SettingsView({
          favoriteManagerOnly: true,
          onFavoriteManagerVisibilityChanged: (visible: boolean): void => {
            this.settingsFavoriteManagerVisible = visible;
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
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
        } else if (this.currentSection === AppSection.query) {
          QueryView()
        } else {
          SettingsView({
            onFavoriteManagerVisibilityChanged: (visible: boolean): void => {
              this.settingsFavoriteManagerVisible = visible;
            }
          })
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // 仅宽屏侧栏布局承接桌面快捷键；手机根节点保持普通容器，避免屏蔽输入控件焦点。
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleDesktopSectionKey(event))
  }

  @Builder
  sidebar() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('BUPT')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
        Text('Where To Study')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 40, right: 40 })

      Divider()
        .color(AppTheme.border())

      Column({ space: 8 }) {
        ForEach(AppSectionInfo.all, (section: AppSection) => {
          Row({ space: 8 }) {
            SymbolGlyph(AppSectionInfo.symbol(section))
              // 密集日历符号在 14fp 下易出现锯齿，使用独立 vp 尺寸保留轮廓细节。
              .fontSize(section === AppSection.calendar ? '20vp' : '14vp')
              .fontWeight(section === AppSection.calendar ? FontWeight.Medium : FontWeight.Regular)
              .fontColor([AppTheme.text()])
              .width(20)
              .height(20)
            Text(this.model.text(AppSectionInfo.title(section)))
              .fontSize(13)
              .fontWeight(this.currentSection === section ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(AppTheme.text())
          }
          .width('100%')
          .height(32)
          .padding({ left: 12, right: 12 })
          .borderRadius(6)
          .backgroundColor(this.currentSection === section ? AppTheme.selection() : Color.Transparent)
          .onClick(() => {
            this.selectSection(section);
          })
        }, (section: AppSection) => AppSectionInfo.accessibilityId(section))
      }
      .width('100%')
      .padding({ left: 8, right: 8 })
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
        } else if (this.currentSection === AppSection.query) {
          QueryView()
        } else {
          SettingsView({
            onFavoriteManagerVisibilityChanged: (visible: boolean): void => {
              this.settingsFavoriteManagerVisible = visible;
            }
          })
        }
      }
      .width('100%')
      .height('100%')

      if (AppSectionInfo.showsPhoneNavigation(this.currentSection, false)) {
        Row({ space: 4 }) {
          ForEach(AppSectionInfo.all, (section: AppSection) => {
            this.phoneNavigationItem(section)
          }, (section: AppSection) => AppSectionInfo.accessibilityId(section))
        }
        .width('calc(100% - 88vp)')
        .height(PhoneNavigationLayout.navigationHeightVp)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .margin({ bottom: this.phoneNavigationBottomMargin })
        .borderRadius(30)
        .backgroundColor(AppTheme.surfaceVariant())
        .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
        .id('phone_navigation')
      }
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
    } else if (section === AppSection.query) {
      QueryView()
    } else {
      SettingsView()
    }
  }

  selectSection(section: AppSection): void {
    hilog.info(0x0000, 'RootView', 'selectSection -> %{public}s', section);
    this.currentSection = section;
    if (section !== AppSection.settings) {
      this.settingsFavoriteManagerVisible = false;
    }
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
