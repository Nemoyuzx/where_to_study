// 设备形态状态：折叠屏折叠状态追踪 + 布局策略（对应 iOS 端
// AdaptiveLayoutPolicy / horizontalSizeClass 的设备适配语义）。
// 折叠屏适配规则：
// - 连续布局：窗口宽度变化驱动布局切换（onAreaChange 自动重算）；
// - 半折叠（FOLD_STATUS_HALF_FOLDED）时屏幕被铰链分成两半，
//   强制使用单列紧凑布局（侧栏/双列/宽日历全部退化为紧凑形态），
//   避免铰链遮挡内容；完全展开/双屏展开按宽度使用宽布局。
import { deviceInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export enum DeviceFoldState {
  unknown = 0,
  expanded = 1,
  folded = 2,
  halfFolded = 3,
  doubleExpanded = 4
}

export class DeviceState {
  private static instanceValue: DeviceState | null = null;

  static instance(): DeviceState {
    if (DeviceState.instanceValue === null) {
      DeviceState.instanceValue = new DeviceState();
    }
    return DeviceState.instanceValue;
  }

  private foldStatus: number = DeviceFoldState.unknown;
  private listening: boolean = false;

  // EntryAbility.onCreate 调用：读取初始折叠状态并注册监听。
  sync(): void {
    try {
      this.foldStatus = display.getFoldStatus();
    } catch (e) {
      this.foldStatus = DeviceFoldState.unknown;
    }
    if (!this.listening) {
      this.listening = true;
      try {
        display.on('foldStatusChange', (status: display.FoldStatus) => {
          this.foldStatus = status;
          hilog.info(0x0000, 'DeviceState', 'foldStatusChange -> %{public}d', status);
        });
      } catch (e) {
        this.listening = false;
      }
    }
  }

  // 屏幕宽度（vp）；用于布局初始值预估（BUG-022 修复）。
  static screenWidthVp(): number {
    try {
      const defaultDisplay: display.Display = display.getDefaultDisplaySync();
      return defaultDisplay.width / defaultDisplay.densityPixels;
    } catch (e) {
      return 390;
    }
  }

  // EntryAbility.onDestroy 调用：注销折叠监听（BUG-017 修复）。
  detach(): void {
    if (!this.listening) {
      return;
    }
    this.listening = false;
    try {
      display.off('foldStatusChange');
    } catch (e) {
      // 注销失败仅影响监听清理。
    }
  }

  foldState(): DeviceFoldState {
    if (this.foldStatus === DeviceFoldState.expanded ||
      this.foldStatus === DeviceFoldState.doubleExpanded) {
      return DeviceFoldState.expanded;
    }
    if (this.foldStatus === DeviceFoldState.folded) {
      return DeviceFoldState.folded;
    }
    if (this.foldStatus === DeviceFoldState.halfFolded) {
      return DeviceFoldState.halfFolded;
    }
    return DeviceFoldState.unknown;
  }

  isHalfFolded(): boolean {
    return this.foldState() === DeviceFoldState.halfFolded;
  }

  // 半折叠时铰链横贯屏幕中部，强制紧凑布局。
  allowsExpandedLayout(): boolean {
    return !this.isHalfFolded();
  }

  // 2in1/PC 设备类型判定：电脑端日历按 Windows Tauri 布局，
  // 平板/手机按 Android 折叠屏布局（用户指定的平台映射）。
  static isPc2in1(): boolean {
    try {
      return deviceInfo.deviceType === '2in1';
    } catch (e) {
      return false;
    }
  }
}

// 与 iOS 端 AdaptiveLayoutPolicy 对齐的布局阈值与判定。
// useSidebarFor/useTwoColumnFor/useExpandedCalendarFor 为纯函数，
// 可在主机侧单元测试中直接验证折叠/宽度组合。
export class AdaptiveLayoutPolicy {
  static readonly minimumSidebarWidth: number = 700;
  static readonly minimumExpandedCalendarWidth: number = 760;
  static readonly minimumTwoColumnWidth: number = 760;

  static useSidebarFor(width: number, foldState: DeviceFoldState): boolean {
    return foldState !== DeviceFoldState.halfFolded &&
      width >= AdaptiveLayoutPolicy.minimumSidebarWidth;
  }

  static useExpandedCalendarFor(width: number, foldState: DeviceFoldState): boolean {
    return foldState !== DeviceFoldState.halfFolded &&
      width >= AdaptiveLayoutPolicy.minimumExpandedCalendarWidth;
  }

  static useTwoColumnFor(width: number, foldState: DeviceFoldState): boolean {
    return foldState !== DeviceFoldState.halfFolded &&
      width >= AdaptiveLayoutPolicy.minimumTwoColumnWidth;
  }

  static useSidebar(width: number): boolean {
    return AdaptiveLayoutPolicy.useSidebarFor(
      width, DeviceState.instance().foldState());
  }

  static useExpandedCalendar(width: number): boolean {
    return AdaptiveLayoutPolicy.useExpandedCalendarFor(
      width, DeviceState.instance().foldState());
  }

  static useTwoColumn(width: number): boolean {
    return AdaptiveLayoutPolicy.useTwoColumnFor(
      width, DeviceState.instance().foldState());
  }
}

// 手机悬浮一级导航的系统底部避让策略。
// HarmonyOS 审核要求可交互底部控件至少抬高 28vp；实际设备若上报了
// 更高的导航指示条或系统避让区，则以设备值为准。
export class PhoneNavigationLayout {
  static readonly navigationHeightVp: number = 60;
  static readonly minimumBottomClearanceVp: number = 28;
  static readonly minimumContentBottomInsetVp: number = 100;

  private static normalizedInset(value: number): number {
    return value >= 0 && value < 1000 ? value : 0;
  }

  static bottomMarginFor(
    navigationIndicatorInsetVp: number,
    systemInsetVp: number = 0
  ): number {
    return Math.max(
      PhoneNavigationLayout.minimumBottomClearanceVp,
      PhoneNavigationLayout.normalizedInset(navigationIndicatorInsetVp),
      PhoneNavigationLayout.normalizedInset(systemInsetVp)
    );
  }
}
