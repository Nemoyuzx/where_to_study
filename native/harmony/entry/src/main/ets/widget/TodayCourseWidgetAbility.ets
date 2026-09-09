// 今日课程服务卡片（FormExtensionAbility），对应 iOS 端 WidgetKit
// WhereToStudyWidget。卡片与主应用同沙箱，直接读取归档文件生成绑定数据。
import { formBindingData, FormExtensionAbility, formProvider, formInfo } from '@kit.FormKit';
import { Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { WidgetSync } from './WidgetSync';
import { TodayCourseWidgetData, WidgetArchive, WidgetCoursePreferences } from './TodayCourseWidgetData';
import { AppLanguage, AppLanguageInfo } from '../common/AppLocalization';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class TodayCourseWidgetAbility extends FormExtensionAbility {
  private activeFormIDs: Set<string> = new Set<string>();
  private dimensions: Map<string, number> = new Map<string, number>();
  private themeDarkMode: boolean | null = null;
  private themedBinding(archive: WidgetArchive | null,
    preferences: WidgetCoursePreferences, dimension: number): Record<string, Object> {
    return WidgetSync.themeBinding(TodayCourseWidgetData.bindingAtEpoch(archive, preferences,
      dimension), WidgetSync.loadThemeSync(this.context.filesDir),
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
    this.dimensions.delete(formId);
  }

  private static defaultPreferences(): WidgetCoursePreferences {
    return new WidgetCoursePreferences(true, true, WidgetCoursePreferences.defaultLimit,
      AppLanguageInfo.resolved(AppLanguage.system, AppLanguageInfo.systemLanguage()));
  }
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: Object | undefined = want.parameters?.['ohos.extra.param.key.form_identity'];
    if (typeof formId === 'string') {
      this.activeFormIDs.add(formId as string);
    }
    // 同步读取归档生成初始绑定（等价于 iOS TimelineProvider 的 entry）。
    const archive: WidgetArchive | null = WidgetSync.loadArchiveFromFilesSync(this.context.filesDir);
    const dimension: Object | undefined = want.parameters?.['ohos.extra.param.key.form_dimension'];
    const dimensionValue: number = Number(dimension);
    if (typeof formId === 'string') {
      this.dimensions.set(formId, Number.isFinite(dimensionValue) ? dimensionValue :
        formInfo.FormDimension.Dimension_2_2);
      // onAddForm 返回前实例可能尚未注册；初次更新由配置中的30分钟周期触发。
      // 后续在 onUpdateForm 成功提交数据后设置下一次刷新。
    }
    const preferences: WidgetCoursePreferences =
      archive?.preferences ?? TodayCourseWidgetAbility.defaultPreferences();
    return formBindingData.createFormBindingData(
      this.themedBinding(archive, preferences, dimensionValue));
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
      let dimensionValue: number = Number(dimension);
      if (!Number.isFinite(dimensionValue)) {
        dimensionValue = this.dimensions.get(formId) ?? formInfo.FormDimension.Dimension_2_2;
        try {
          // 服务进程重启后，周期回调不一定再次携带尺寸。
          dimensionValue = (await formProvider.getPublishedRunningFormInfoById(formId)).dimension;
        } catch (e) {
          // 查询不可用时使用缓存或紧凑容量，避免卡片溢出。
        }
      }
      this.dimensions.set(formId, dimensionValue);
      const archive: WidgetArchive | null = await WidgetSync.loadArchive(
        TodayCourseWidgetData.archiveFilePath(filesDir));
      const preferences: WidgetCoursePreferences =
        archive?.preferences ?? TodayCourseWidgetAbility.defaultPreferences();
      const data: formBindingData.FormBindingData =
        formBindingData.createFormBindingData(
          this.themedBinding(archive, preferences, dimensionValue));
      if (hasFormId) {
        try {
          await formProvider.updateForm(formId, data);
          this.scheduleNextRefresh(formId);
        } catch (e) {
          // 更新失败保留上次内容。
        }
      }
    })();
    work.catch(() => {
      // 卡片读取失败保留上次内容。
    });
  }

  private scheduleNextRefresh(formId: string): void {
    // 下次刷新可能压过周期刷新，因此白天也不能预约到30分钟之外。
    try {
      formProvider.setFormNextRefreshTime(formId, TodayCourseWidgetData.nextRefreshMinutes())
        .catch((error: BusinessError) => {
          hilog.warn(0x0000, 'TodayCourseWidget', '下次刷新安排失败: %{public}d', error.code);
        });
    } catch (e) {
      hilog.warn(0x0000, 'TodayCourseWidget', '下次刷新接口不可用，保留周期刷新');
    }
  }
}
