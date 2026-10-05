// 与 Android MainActivity 对应的根布局：
// 宽度 >= 700vp 时使用侧栏（对应 NavigationSplitView 的 regular 布局），
// 否则使用底部 Tabs（对应 compact 布局）；示例模式顶部显示提示条。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { FrameCallback, FrameNode, window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { AppModel } from '../model/AppModel';
import { AppLaunchConfiguration } from '../model/LaunchSupport';
import { AppSection, AppSectionInfo } from '../common/AppSection';
import { AppTheme } from '../common/AppTheme';
import { PlannerView } from './PlannerView';
import { CalendarSectionView } from './CalendarSectionView';
import { SettingsView } from './SettingsView';
import { SettingsSession } from './SettingsSession';
import { PrivacyPolicyView } from './PrivacyPolicyView';
import { QueryView } from './QueryView';
import { QuerySession } from './QuerySession';
import { AppLanguage, AppLanguageInfo } from '../common/AppLocalization';

// 布局策略统一在 common/DeviceState.ets 中（含折叠屏半折叠降级规则），
// 这里保留导出以兼容旧引用。
import { AdaptiveLayoutPolicy, DeviceState, PhoneNavigationLayout } from '../common/DeviceState';
export { AdaptiveLayoutPolicy };

// UIContext 的一次性帧回调没有取消 API；RootView 的 epoch 在离页/后台/新点击后
// 使旧回调无权读写新页面。每次只排下一帧，不持有整页截图或循环定时器。
class LanguageLayoutFrameCallback extends FrameCallback {
  private readonly work: () => void;

  constructor(work: () => void) {
    super();
    this.work = work;
  }

  onFrame(frameTimeInNano: number): void {
    this.work();
  }

  onIdle(timeLeftInNano: number): void {}
}

@ComponentV2
export struct RootView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local currentSection: AppSection = AppSection.planner;
  // 初始值按屏幕宽度预估，避免宽屏启动首帧闪 Tabs（BUG-022 修复）。
  @Local containerWidth: number = DeviceState.screenWidthVp();
  @Local settingsFavoriteManagerVisible: boolean = false;
  @Local settingsSession: SettingsSession = new SettingsSession();
  @Local querySession: QuerySession = new QuerySession();
  @Local phoneNavigationBottomMargin: number = PhoneNavigationLayout.minimumBottomClearanceVp;
  @Local languageOverlayVisible: boolean = false;
  @Local languageOverlayOpacity: number = 0;
  private deadlineRefreshTimer: number = -1;
  private navigationWindow: window.Window | null = null;
  private navigationAvoidAreaListener: ((options: window.AvoidAreaOptions) => void) | null = null;
  private languageWindowEventListener: ((event: window.WindowEventType) => void) | null = null;
  private navigationAvoidanceActive: boolean = false;
  private languageTransitionEpoch: number = 0;
  private languageTransitionTarget: AppLanguage | null = null;
  private languageTransitionTimer: number = -1;
  private languageOverlayFading: boolean = false;
  private languageStableFrames: number = 0;
  private languageLastCardX: number = Number.NaN;
  private languageLastCardY: number = Number.NaN;
  private languageLastCardWidth: number = Number.NaN;
  private languageLastCardHeight: number = Number.NaN;
  private languageLastOptionX: number = Number.NaN;
  private languageLastOptionY: number = Number.NaN;
  private languageLastOptionWidth: number = Number.NaN;
  private languageLastOptionHeight: number = Number.NaN;

  private sidebarWidth(): number {
    return this.containerWidth < 1000 ? 210 : 230;
  }

  aboutToAppear(): void {
    if (AppLaunchConfiguration.consumeSettingsPresentationSeedForTesting()) {
      this.settingsSession.seedReviewPresentationDraftsOnce();
    }
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
    this.cancelLanguageTransition(true);
    this.navigationAvoidanceActive = false;
    this.querySession.dispose();
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
      const languageListener = (event: window.WindowEventType): void => {
        if (event === window.WindowEventType.WINDOW_INACTIVE ||
          event === window.WindowEventType.WINDOW_HIDDEN) {
          this.cancelLanguageTransition(true);
        }
      };
      this.languageWindowEventListener = languageListener;
      mainWindow.on('windowEvent', languageListener);
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
    if (this.navigationWindow !== null && this.languageWindowEventListener !== null) {
      try {
        this.navigationWindow.off('windowEvent', this.languageWindowEventListener);
      } catch (e) {
        // 窗口销毁期间注销失败由窗口自身释放；旧 epoch 已失效。
      }
    }
    this.navigationWindow = null;
    this.navigationAvoidAreaListener = null;
    this.languageWindowEventListener = null;
  }

  private reduceLanguageMotion(): boolean {
    // 只读系统公开动画比例，不写系统设置、也不请求 MANAGE_SETTINGS 权限。
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) { return false; }
      const animatorScale: string = settings.getValueSync(context, settings.display.ANIMATOR_DURATION_SCALE, '1');
      const transitionScale: string = settings.getValueSync(context, settings.display.TRANSITION_ANIMATION_SCALE, '1');
      return (animatorScale.length > 0 && Number(animatorScale) === 0) ||
        (transitionScale.length > 0 && Number(transitionScale) === 0);
    } catch (e) {
      return false;
    }
  }

  private clearLanguageTransitionTimer(): void {
    if (this.languageTransitionTimer >= 0) {
      clearTimeout(this.languageTransitionTimer);
      this.languageTransitionTimer = -1;
    }
  }

  private postLanguageFrame(epoch: number, work: () => void): void {
    try {
      this.getUIContext().postFrameCallback(new LanguageLayoutFrameCallback((): void => {
        if (epoch === this.languageTransitionEpoch) { work(); }
      }));
    } catch (e) {
      // 渲染上下文销毁时由 deadline 清理遮罩；不能保留重试轮询。
    }
  }

  private cancelLanguageTransition(commitIntent: boolean): void {
    const target: AppLanguage | null = this.languageTransitionTarget;
    this.languageTransitionEpoch++;
    this.clearLanguageTransitionTimer();
    this.languageTransitionTarget = null;
    this.settingsSession.clearLanguageChange();
    this.languageOverlayOpacity = 0;
    this.languageOverlayVisible = false;
    this.languageOverlayFading = false;
    this.languageStableFrames = 0;
    if (commitIntent && target !== null &&
      (this.model.languageSetting() !== target ||
        AppLanguageInfo.systemLanguage() !== this.model.systemLanguageID)) {
      // 离页/后台不能吞掉已接受的最终选择；不启动动画或重新持有 SettingsView。
      void this.model.setLanguageSetting(target);
    }
  }

  private beginLanguageTransition(target: AppLanguage): void {
    if (this.currentSection !== AppSection.settings) { return; }
    if (this.languageTransitionTarget === target) { return; }
    if (target === this.model.languageSetting() &&
      AppLanguageInfo.systemLanguage() === this.model.systemLanguageID) {
      if (this.languageTransitionTarget !== null) { this.cancelLanguageTransition(false); }
      return;
    }
    if (this.reduceLanguageMotion()) {
      this.cancelLanguageTransition(false);
      const revision: number = ++this.languageTransitionEpoch;
      this.settingsSession.requestLanguageChange(target, revision);
      return;
    }
    const epoch: number = ++this.languageTransitionEpoch;
    this.languageTransitionTarget = target;
    this.languageOverlayFading = false;
    this.languageStableFrames = 0;
    this.languageLastCardX = Number.NaN;
    this.languageLastCardY = Number.NaN;
    this.languageLastCardWidth = Number.NaN;
    this.languageLastCardHeight = Number.NaN;
    this.languageLastOptionX = Number.NaN;
    this.languageLastOptionY = Number.NaN;
    this.languageLastOptionWidth = Number.NaN;
    this.languageLastOptionHeight = Number.NaN;
    this.clearLanguageTransitionTimer();
    if (!this.languageOverlayVisible) {
      this.languageOverlayOpacity = 0;
      this.languageOverlayVisible = true;
    }
    // 失去窗口/帧回调时也必须有界结束；deadline 不启动任何网络请求。
    this.languageTransitionTimer = setTimeout((): void => {
      if (epoch !== this.languageTransitionEpoch) { return; }
      this.languageTransitionTimer = -1;
      this.requestLanguageUnderOverlay(epoch);
      // Missing layout cannot be reported as ready; retire the overlay and
      // commit the accepted choice without a successful-layout reveal.
      this.cancelLanguageTransition(true);
    }, 1600);
    // 先给独立模糊层一个实际布局帧，再覆盖内容；不能让文字变化跟随整页动画。
    this.postLanguageFrame(epoch, (): void => {
      this.getUIContext().animateTo({ duration: 110, curve: Curve.EaseOut,
        onFinish: (): void => {
          if (epoch !== this.languageTransitionEpoch) { return; }
          this.requestLanguageUnderOverlay(epoch);
          this.sampleLanguageLayout(epoch);
        }
      }, (): void => {
        this.languageOverlayOpacity = 1;
      });
    });
  }

  private requestLanguageUnderOverlay(epoch: number): void {
    const target: AppLanguage | null = this.languageTransitionTarget;
    if (target === null || epoch !== this.languageTransitionEpoch ||
      this.settingsSession.languageChangeRevision === epoch) { return; }
    this.settingsSession.requestLanguageChange(target, epoch);
  }

  private languageOptionIndex(target: AppLanguage): number {
    return AppLanguageInfo.all.indexOf(target);
  }

  private sampleLanguageLayout(epoch: number): void {
    const target: AppLanguage | null = this.languageTransitionTarget;
    if (epoch !== this.languageTransitionEpoch || target === null || this.languageOverlayFading) { return; }
    if (this.currentSection !== AppSection.settings) {
      this.cancelLanguageTransition(true);
      return;
    }
    const index: number = this.languageOptionIndex(target);
    let sampled: boolean = false;
    if (index >= 0 && this.settingsSession.languageChangeAppliedRevision === epoch &&
      this.model.languageSetting() === target) {
      try {
        const card: FrameNode | null = this.getUIContext().getAttachedFrameNodeById('settings_language_surface');
        const option: FrameNode | null = this.getUIContext().getAttachedFrameNodeById(
          'settings.language.' + index.toString());
        const activeThumb: FrameNode | null = this.getUIContext().getAttachedFrameNodeById(
          'settings.language.thumb.' + index.toString() + '.active');
        if (card !== null && option !== null && activeThumb !== null) {
          const cardPosition = card.getPositionToWindow();
          const cardBounds = card.getMeasuredSize();
          const cardY: number = cardPosition.y;
          const optionPosition = option.getPositionToWindow();
          const optionBounds = option.getMeasuredSize();
          const optionWidth: number = optionBounds.width;
          const geometry: number[] = [cardPosition.x, cardPosition.y, cardBounds.width, cardBounds.height,
            optionPosition.x, optionPosition.y, optionBounds.width, optionBounds.height];
          if (geometry.every((value: number): boolean => Number.isFinite(value)) &&
            cardBounds.width > 0 && cardBounds.height > 0 && optionBounds.width > 0 && optionBounds.height > 0) {
            sampled = true;
            const stable: boolean = Math.abs(cardPosition.x - this.languageLastCardX) <= 1 &&
              Math.abs(cardY - this.languageLastCardY) <= 1 &&
              Math.abs(cardBounds.width - this.languageLastCardWidth) <= 1 &&
              Math.abs(cardBounds.height - this.languageLastCardHeight) <= 1 &&
              Math.abs(optionPosition.x - this.languageLastOptionX) <= 1 &&
              Math.abs(optionPosition.y - this.languageLastOptionY) <= 1 &&
              Math.abs(optionWidth - this.languageLastOptionWidth) <= 1 &&
              Math.abs(optionBounds.height - this.languageLastOptionHeight) <= 1;
            this.languageStableFrames = stable ? this.languageStableFrames + 1 : 0;
            this.languageLastCardX = cardPosition.x;
            this.languageLastCardY = cardY;
            this.languageLastCardWidth = cardBounds.width;
            this.languageLastCardHeight = cardBounds.height;
            this.languageLastOptionX = optionPosition.x;
            this.languageLastOptionY = optionPosition.y;
            this.languageLastOptionWidth = optionWidth;
            this.languageLastOptionHeight = optionBounds.height;
            // 目标选中节点已挂载且三个连续帧中几何稳定，才揭开新语言。
            if (this.languageStableFrames >= 2) {
              this.fadeLanguageOverlay(epoch);
              return;
            }
          }
        }
      } catch (e) {
        // 旋转/离页时 FrameNode 可能在本帧失效，下一帧重读或 deadline 兜底。
      }
    }
    if (!sampled) {
      this.languageStableFrames = 0;
      this.languageLastCardX = Number.NaN;
      this.languageLastCardY = Number.NaN;
      this.languageLastCardWidth = Number.NaN;
      this.languageLastCardHeight = Number.NaN;
      this.languageLastOptionX = Number.NaN;
      this.languageLastOptionY = Number.NaN;
      this.languageLastOptionWidth = Number.NaN;
      this.languageLastOptionHeight = Number.NaN;
    }
    this.postLanguageFrame(epoch, (): void => this.sampleLanguageLayout(epoch));
  }

  private fadeLanguageOverlay(epoch: number): void {
    if (epoch !== this.languageTransitionEpoch || this.languageTransitionTarget === null ||
      this.languageOverlayFading) { return; }
    this.languageOverlayFading = true;
    this.clearLanguageTransitionTimer();
    this.languageTransitionTimer = setTimeout((): void => {
      if (epoch === this.languageTransitionEpoch) { this.cancelLanguageTransition(true); }
    }, 340);
    this.getUIContext().animateTo({ duration: 190, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (epoch === this.languageTransitionEpoch) { this.cancelLanguageTransition(true); }
      }
    }, (): void => {
      this.languageOverlayOpacity = 0;
    });
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
          session: this.settingsSession,
          favoriteManagerOnly: true,
          onFavoriteManagerVisibilityChanged: (visible: boolean): void => {
            this.settingsFavoriteManagerVisible = visible;
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(100)
      }

      // 隐私页由根布局持有，切换平板侧栏/手机底栏不会销毁它；
      // 下层 SettingsView 仍保持挂载，返回时滚动位置与编辑状态不变。
      if (this.settingsSession.showingPrivacyPolicy) {
        PrivacyPolicyView({
          onClose: (): void => {
            this.setSettingsPrivacyPolicyVisible(false);
          }
        })
          .width('100%')
          .height('100%')
          .zIndex(110)
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }

      if (this.languageOverlayVisible) {
        // 材质由 RenderService 在独立全窗口层处理；只动画 opacity，不能截屏或
        // 给整页内容施加逐帧 blur。最上层在目标布局稳定前拦截重复触摸。
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundBlurStyle(BlurStyle.Regular)
          .opacity(this.languageOverlayOpacity)
          .hitTestBehavior(HitTestMode.Block)
          .id('language_transition_overlay')
          .zIndex(120)
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
        .fontColor([AppTheme.onAccent()])
      Text(this.model.text('示例数据 · 不连接北邮教务服务'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.onAccent())
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
          QueryView({ session: this.querySession,
            onOpenSettings: () => this.selectSection(AppSection.settings) })
        } else {
          SettingsView({
            session: this.settingsSession,
            onFavoriteManagerVisibilityChanged: (visible: boolean): void => {
              this.settingsFavoriteManagerVisible = visible;
            },
            onLanguageChangeRequested: (target: AppLanguage): void => this.beginLanguageTransition(target)
          })
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    // 仅宽屏侧栏布局承接桌面快捷键；手机根节点保持普通容器，避免屏蔽输入控件焦点。
    .id('root_sidebar_layout')
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
    .backgroundColor(AppTheme.inputSurface())
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
          QueryView({ session: this.querySession,
            onOpenSettings: () => this.selectSection(AppSection.settings) })
        } else {
          SettingsView({
            session: this.settingsSession,
            onFavoriteManagerVisibilityChanged: (visible: boolean): void => {
              this.settingsFavoriteManagerVisible = visible;
            },
            onLanguageChangeRequested: (target: AppLanguage): void => this.beginLanguageTransition(target)
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
    Stack() {
      // 背景独立动画，翻译引起的文字宽度/换行不参与整列布局过渡。
      Column() {}
        .width('100%')
        .height(50)
        .borderRadius(26)
        .backgroundColor(this.currentSection === section ? AppTheme.background() : Color.Transparent)
        .animation({ duration: 160, curve: Curve.EaseOut })
      Column({ space: 2 }) {
        SymbolGlyph(AppSectionInfo.symbol(section))
          .fontSize(22)
          .fontColor([this.currentSection === section ? AppTheme.primary() : AppTheme.secondaryText()])
          .animation({ duration: 160, curve: Curve.EaseOut })
        Text(this.model.text(AppSectionInfo.title(section)))
          .fontSize(11)
          .fontWeight(this.currentSection === section ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.currentSection === section ? AppTheme.primary() : AppTheme.secondaryText())
      }
      .width('100%')
      .height(50)
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(50)
    .id(AppSectionInfo.accessibilityId(section))
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
      QueryView({ session: this.querySession,
        onOpenSettings: () => this.selectSection(AppSection.settings) })
    } else {
      SettingsView({ session: this.settingsSession,
        onLanguageChangeRequested: (target: AppLanguage): void => this.beginLanguageTransition(target) })
    }
  }

  selectSection(section: AppSection): void {
    hilog.info(0x0000, 'RootView', 'selectSection -> %{public}s', section);
    if (section !== AppSection.settings && this.languageTransitionTarget !== null) {
      this.cancelLanguageTransition(true);
    }
    this.currentSection = section;
    if (section !== AppSection.settings) {
      this.settingsFavoriteManagerVisible = false;
      this.settingsSession.showingPrivacyPolicy = false;
    }
    this.model.selectedSection = section;
  }

  private setSettingsPrivacyPolicyVisible(visible: boolean): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.settingsSession.showingPrivacyPolicy = visible;
    });
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
