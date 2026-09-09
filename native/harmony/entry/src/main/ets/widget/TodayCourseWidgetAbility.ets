// 今日课程服务卡片（FormExtensionAbility），对应 iOS 端 WidgetKit
// WhereToStudyWidget。卡片与主应用同沙箱，直接读取归档文件生成绑定数据。
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { WidgetSync } from './WidgetSync';
import { TodayCourseWidgetData, WidgetArchive, WidgetCoursePreferences } from './TodayCourseWidgetData';
import { AppLanguage, AppLanguageInfo } from '../common/AppLocalization';

export default class TodayCourseWidgetAbility extends FormExtensionAbility {
  private activeFormIDs: Set<string> = new Set<string>();
  private themeDarkMode: boolean | null = null;
  private themedBinding(archive: WidgetArchive | null,
    preferences: WidgetCoursePreferences): Record<string, Object> {
    return WidgetSync.themeBinding(TodayCourseWidgetData.binding(archive, preferences,
      undefined, TodayCourseWidgetData.nowMinute()), WidgetSync.loadThemeSync(this.context.filesDir),
      this.themeDarkMode ?? this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 深浅色变化由系统配置触发；默认主题仍使用原来的自适应资源色。
    this.themeDarkMode = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    for (const id of this.activeFormIDs) {
      this.refreshFormAsync(id, true);
    }
  }

  onRemoveForm(formId: string): void {
    this.activeFormIDs.delete(formId);
  }

  private static defaultPreferences(): WidgetCoursePreferences {
    return new WidgetCoursePreferences(true, true, WidgetCoursePreferences.defaultLimit,
      AppLanguageInfo.resolved(AppLanguage.system, AppLanguageInfo.systemLanguage()));
  }
  // 卡片尺寸 → 行数上限（2*2 两行，其余按偏好上限；未知按偏好上限），BUG-040 修复。
  private static rowLimitForDimension(dimension: Object | undefined,
    preferences: WidgetCoursePreferences): number {
    const value: number = typeof dimension === 'number' ? dimension as number : Number(dimension);
    if (!Number.isNaN(value) && value === 1) {
      return Math.min(2, preferences.courseLimit);
    }
    return preferences.courseLimit;
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: Object | undefined = want.parameters?.['ohos.extra.param.key.form_identity'];
    if (typeof formId === 'string') {
      this.activeFormIDs.add(formId as string);
    }
    // 同步读取归档生成初始绑定（等价于 iOS TimelineProvider 的 entry）。
    const archive: WidgetArchive | null = WidgetSync.loadArchiveSync(
      TodayCourseWidgetData.archiveFilePath(this.context.filesDir));
    const dimension: Object | undefined = want.parameters?.['ohos.extra.param.key.form_dimension'];
    const preferences: WidgetCoursePreferences =
      archive?.preferences ?? TodayCourseWidgetAbility.defaultPreferences();
    return formBindingData.createFormBindingData(
      this.themedBinding(archive, preferences));
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.activeFormIDs.add(formId);
    this.refreshFormAsync(formId, true, wantParams);
  }

  private refreshFormAsync(formId: string, hasFormId: boolean,
    wantParams?: Record<string, Object>): void {
    const filesDir: string = this.context.filesDir;
    const dimension: Object | undefined = wantParams?.['ohos.extra.param.key.form_dimension'];
    const work: Promise<void> = (async (): Promise<void> => {
      const archive: WidgetArchive | null = await WidgetSync.loadArchive(
        TodayCourseWidgetData.archiveFilePath(filesDir));
      const preferences: WidgetCoursePreferences =
        archive?.preferences ?? TodayCourseWidgetAbility.defaultPreferences();
      const data: formBindingData.FormBindingData =
        formBindingData.createFormBindingData(
          this.themedBinding(archive, preferences));
      if (hasFormId) {
        try {
          await formProvider.updateForm(formId, data);
        } catch (e) {
          // 更新失败保留上次内容。
        }
      }
    })();
    work.catch(() => {
      // 卡片读取失败保留上次内容。
    });
  }
}
