// 设备形态状态：折叠屏折叠状态追踪 + 布局策略（对应 iOS 端
// AdaptiveLayoutPolicy / horizontalSizeClass 的设备适配语义）。
// 折叠屏适配规则：
// - 连续布局：窗口宽度变化驱动布局切换（onAreaChange 自动重算）；
// - 半折叠（FOLD_STATUS_HALF_FOLDED）时屏幕被铰链分成两半，
//   强制使用单列紧凑布局（侧栏/双列/宽日历全部退化为紧凑形态），
//   避免铰链遮挡内容；完全展开/双屏展开按宽度使用宽布局。
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
