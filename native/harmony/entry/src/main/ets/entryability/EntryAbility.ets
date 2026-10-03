import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from '../store/AppContext';
import { AppLaunchConfiguration } from '../model/LaunchSupport';
import { DeviceState } from '../common/DeviceState';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindowStage: window.WindowStage | null = null;
  private settingsTestOriginalOrientation: window.Orientation | null = null;
  private settingsTestOrientationRevision: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContext.init(this.context);
    // 与 iOS 端进程参数对应的 UI 测试/演示模式标记。
    AppLaunchConfiguration.applyFromWant(want);
    // 折叠屏适配：读取初始折叠状态并监听折叠变化。
    DeviceState.instance().sync();
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 单例 Ability 在设备测试中会收到新的启动 Want，而不是再次 onCreate。
    // 只有显式测试/演示参数才切换依赖并重载根页；普通二次启动保持用户现场。
    if (!AppLaunchConfiguration.hasExplicitRuntimeMode(want)) {
      return;
    }
    AppLaunchConfiguration.applyFromWant(want);
    if (this.mainWindowStage !== null) {
      this.loadRootContentWithSettingsTestOrientation(this.mainWindowStage);
    }
  }

  onDestroy(): void {
    // 注销折叠状态监听，避免监听累积（BUG-017 修复）。
    DeviceState.instance().detach();
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.mainWindowStage = windowStage;
    // 2in1/PC 适配：限制窗口最小尺寸，避免布局被缩到无法使用。
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      // 输入法弹出时缩小内容视口，使设置页 Scroll 与固定底栏都保持可达。
      mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      mainWindow.setWindowLimits({
        maxWidth: 0,
        maxHeight: 0,
        minWidth: 400,
        minHeight: 640
      }).then(() => {
        hilog.info(DOMAIN, 'WhereToStudy', 'window limits applied');
      }).catch(() => {
        // 非 PC 设备可能不支持窗口限制，忽略。
      });
    } catch (e) {
      // 同上，忽略不支持限制的设备。
    }
    // 主窗口加载应用首页。状态从 windowStage.loadContent 传入的页面自行创建，
    // 与 iOS 端 @StateObject AppModel 的注入方式对应：页面树在 Index 根组件中
    // 创建唯一的 AppModel 并通过 @Provider/@Consumer 向下共享。
    this.loadRootContentWithSettingsTestOrientation(windowStage);
  }

  private loadRootContentWithSettingsTestOrientation(windowStage: window.WindowStage): void {
    const seededTest: boolean = AppLaunchConfiguration.hasPendingSettingsPresentationSeedForTesting();
    if (!seededTest && this.settingsTestOriginalOrientation === null) {
      // 普通/Release 路径保持原来的同步 loadContent，不调用任何 orientation API。
      this.loadRootContent(windowStage);
      return;
    }
    const revision: number = ++this.settingsTestOrientationRevision;
    let mainWindow: window.Window;
    try {
      mainWindow = windowStage.getMainWindowSync();
    } catch (e) {
      this.loadRootContent(windowStage);
      return;
    }
    if (seededTest && this.settingsTestOriginalOrientation === null) {
      try {
        this.settingsTestOriginalOrientation = mainWindow.getPreferredOrientation();
      } catch (e) {
        // 不知道原值便不修改窗口方向；设备测试会如实报告没有跨过布局边界。
        this.loadRootContent(windowStage);
        return;
      }
    }
    const requested: window.Orientation = seededTest ? window.Orientation.AUTO_ROTATION :
      this.settingsTestOriginalOrientation as window.Orientation;
    mainWindow.setPreferredOrientation(requested).then((): void => {
      if (revision !== this.settingsTestOrientationRevision || this.mainWindowStage !== windowStage) { return; }
      if (!seededTest) { this.settingsTestOriginalOrientation = null; }
      this.loadRootContent(windowStage);
    }, (e: BusinessError): void => {
      hilog.warn(DOMAIN, 'WhereToStudy', 'Test-only preferred orientation unavailable: %{public}s', String(e));
      if (revision === this.settingsTestOrientationRevision && this.mainWindowStage === windowStage) {
        this.loadRootContent(windowStage);
      }
    });
  }

  private loadRootContent(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'WhereToStudy', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'WhereToStudy', 'Succeeded in loading content');
    });
  }

  onWindowStageDestroy(): void {
    this.settingsTestOrientationRevision++;
    this.settingsTestOriginalOrientation = null;
    this.mainWindowStage = null;
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onBackground');
  }
}
