// 天气卡片只保存当前页面会话状态；每次新建页面都从折叠态开始。
export class WeatherCardPolicy {
  static readonly startsExpanded: boolean = false;

  static toggled(current: boolean): boolean {
    return !current;
  }
}
