// 全局 UIAbility 上下文入口：EntryAbility.onCreate 时注入，
// 供 store 层定位应用沙箱文件目录（对应 iOS Application Support 目录）。
import { common } from '@kit.AbilityKit';

export class AppContext {
  private static abilityContext: common.UIAbilityContext | null = null;

  static init(context: common.UIAbilityContext): void {
    AppContext.abilityContext = context;
  }

  static get(): common.UIAbilityContext {
    if (AppContext.abilityContext === null) {
      throw new Error('应用上下文尚未初始化。');
    }
    return AppContext.abilityContext;
  }

  // 对应 iOS 端 WhereToStudyNative 应用支持目录。
  static filesRoot(): string {
    return AppContext.get().filesDir + '/WhereToStudyNative';
  }

  static scheduleFilePath(): string {
    return AppContext.filesRoot() + '/schedule.json';
  }

  static classroomsFilePath(): string {
    return AppContext.filesRoot() + '/classrooms.json';
  }

  static holidaysDirectoryPath(): string {
    return AppContext.filesRoot() + '/holidays';
  }

  static holidayFilePath(year: number): string {
    return AppContext.holidaysDirectoryPath() + '/holidays_' + year.toString() + '.json';
  }
}
