import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContext } from '../store/AppContext';
import { AppLaunchConfiguration } from '../model/LaunchSupport';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContext.init(this.context);
    // 与 iOS 端进程参数对应的 UI 测试/演示模式标记。
    AppLaunchConfiguration.applyFromWant(want);
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗口加载应用首页。状态从 windowStage.loadContent 传入的页面自行创建，
    // 与 iOS 端 @StateObject AppModel 的注入方式对应：页面树在 Index 根组件中
    // 创建唯一的 AppModel 并通过 @Provider/@Consumer 向下共享。
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'WhereToStudy', 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'WhereToStudy', 'Succeeded in loading content');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'WhereToStudy', 'EntryAbility onBackground');
  }
}
