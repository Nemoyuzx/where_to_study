// PC/2in1 审核要求：默认窗口和最大化窗口中的文本不得小于 10fp。
// 与窗口宽度解耦，确保 PC 缩到紧凑布局后仍遵循同一规则；
// 手机、折叠屏和平板保留现有字号，不改变字体缩放或系统无障碍设置。
export class CalendarTypography {
  static readonly minimumPcFontSize: number = 10;

  static fontSize(requested: number, isPc: boolean): number {
    return isPc ? Math.max(requested, CalendarTypography.minimumPcFontSize) : requested;
  }
}
