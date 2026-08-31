// 与 Apple / Android 端 AppSection 对应的四个一级页面。
export enum AppSection {
  planner = 'planner',
  calendar = 'calendar',
  query = 'query',
  settings = 'settings'
}

export class AppSectionInfo {
  static readonly all: AppSection[] = [
    AppSection.planner,
    AppSection.calendar,
    AppSection.query,
    AppSection.settings
  ];

  static title(section: AppSection): string {
    if (section === AppSection.planner) {
      return '空教室';
    }
    if (section === AppSection.calendar) {
      return '教学日历';
    }
    if (section === AppSection.query) {
      return '查询';
    }
    return '设置';
  }

  // 与其他图形客户端一致的 house / calendar / search / gear 语义。
  static symbol(section: AppSection): Resource {
    if (section === AppSection.planner) {
      return $r('sys.symbol.house');
    }
    if (section === AppSection.calendar) {
      return $r('sys.symbol.calendar');
    }
    if (section === AppSection.query) {
      return $r('sys.symbol.magnifyingglass');
    }
    return $r('sys.symbol.gearshape');
  }

  static accessibilityId(section: AppSection): string {
    return 'navigation.' + section;
  }

  static showsPhoneNavigation(section: AppSection, favoriteManagerVisible: boolean): boolean {
    return !(section === AppSection.settings && favoriteManagerVisible);
  }
}
