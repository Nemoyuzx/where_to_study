// 应用元信息常量。version 需与 AppScope/app.json5 的 versionName 保持同步。
export class AppMeta {
  static readonly displayName: string = 'Where To Study';
  static readonly version: string = '0.2.4';
  // 对应 iOS 端 HolidayUserAgent 的 WhereToStudyNative/<version> 格式。
  static readonly holidayUserAgent: string = 'WhereToStudyNative/' + AppMeta.version;
}
