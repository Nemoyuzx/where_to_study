// 运行模式：live（真实数据）或 sample(review)（内置示例/演示数据）。
// 独立成文件以避免 AppModel 与 LaunchSupport 之间的循环依赖。
export class AppRuntimeMode {
  readonly isSample: boolean;
  readonly isReviewDemo: boolean;

  private constructor(isSample: boolean, isReviewDemo: boolean) {
    this.isSample = isSample;
    this.isReviewDemo = isReviewDemo;
  }

  static live(): AppRuntimeMode {
    return new AppRuntimeMode(false, false);
  }

  static sample(review: boolean): AppRuntimeMode {
    return new AppRuntimeMode(true, review);
  }
}
