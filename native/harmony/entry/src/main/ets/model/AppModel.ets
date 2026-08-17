// 与 iOS 端 AppModel 对应的应用状态机（移植进行中）。
// 本文件当前仅提供 RootView 依赖的最小状态；后续轮次会把
// CredentialSettingsLogic、课表/空教室/节假日加载与缓存、
// 每日课程提醒、日历导入等完整移植进来。

import { AppSection } from '../common/AppSection';

@ObservedV2
export class AppModel {
  @Trace selectedSection: AppSection = AppSection.planner;
  @Trace isSampleMode: boolean = false;
  @Trace statusMessage: string = '';

  // 与 iOS 端 RootView.onAppear 对应的启动动作。
  launch(): void {
    this.refreshClassroomsIfNeeded();
  }

  refreshClassroomsIfNeeded(): void {
    // TODO(round: AppModel 移植)：当天空教室缓存缺失且已有凭据时刷新。
  }

  refreshDailyCourseNotificationAuthorization(): void {
    // TODO(round: 平台集成)：进入前台时重新核对通知授权状态。
  }
}
