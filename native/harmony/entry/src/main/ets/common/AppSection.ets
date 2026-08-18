// 与 iOS 端 AppSection 对应的三个一级页面。
export enum AppSection {
  planner = 'planner',
  calendar = 'calendar',
  settings = 'settings'
}

export class AppSectionInfo {
  static readonly all: AppSection[] = [
    AppSection.planner,
    AppSection.calendar,
    AppSection.settings
  ];

  static title(section: AppSection): string {
    if (section === AppSection.planner) {
      return '空教室';
    }
    if (section === AppSection.calendar) {
      return '教学日历';
    }
    return '设置';
  }

  // SF Symbols house / calendar / gearshape 的鸿蒙符号库对应名称。
  static symbol(section: AppSection): Resource {
    if (section === AppSection.planner) {
      return $r('sys.symbol.house');
    }
    if (section === AppSection.calendar) {
      return $r('sys.symbol.calendar');
    }
    return $r('sys.symbol.gearshape');
  }

  static accessibilityId(section: AppSection): string {
    return 'navigation.' + section;
  }
}
