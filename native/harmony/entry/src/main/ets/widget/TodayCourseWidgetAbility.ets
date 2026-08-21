// 今日课程服务卡片（FormExtensionAbility），对应 iOS 端 WidgetKit
// WhereToStudyWidget。卡片与主应用同沙箱，直接读取归档文件生成绑定数据。
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetSync } from './WidgetSync';
import { TodayCourseWidgetData, WidgetArchive, WidgetCoursePreferences } from './TodayCourseWidgetData';

export default class TodayCourseWidgetAbility extends FormExtensionAbility {
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
    // 同步读取归档生成初始绑定（等价于 iOS TimelineProvider 的 entry）。
    const archive: WidgetArchive | null = WidgetSync.loadArchiveSync(
      TodayCourseWidgetData.archiveFilePath(this.context.filesDir));
    const dimension: Object | undefined = want.parameters?.['ohos.extra.param.key.form_dimension'];
    const preferences: WidgetCoursePreferences =
      archive?.preferences ?? new WidgetCoursePreferences();
    return formBindingData.createFormBindingData(
      TodayCourseWidgetData.binding(archive, preferences,
        undefined, TodayCourseWidgetData.nowMinute()));
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
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
        archive?.preferences ?? new WidgetCoursePreferences();
      const data: formBindingData.FormBindingData =
        formBindingData.createFormBindingData(
          TodayCourseWidgetData.binding(archive, preferences,
            undefined, TodayCourseWidgetData.nowMinute()));
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
