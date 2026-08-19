// 今日课程服务卡片（FormExtensionAbility），对应 iOS 端 WidgetKit
// WhereToStudyWidget。卡片与主应用同沙箱，直接读取归档文件生成绑定数据。
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetSync } from './WidgetSync';
import { TodayCourseWidgetData, WidgetArchive } from './TodayCourseWidgetData';

export default class TodayCourseWidgetAbility extends FormExtensionAbility {
  // 卡片尺寸 → 课程行数（2*2 两行，其余三行；未知按三行），BUG-040 修复。
  private static courseLimitForDimension(dimension: Object | undefined): number {
    const value: number = typeof dimension === 'number' ? dimension as number : Number(dimension);
    if (!Number.isNaN(value) && value === 1) {
      return 2;
    }
    return 3;
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    // 同步读取归档生成初始绑定（等价于 iOS TimelineProvider 的 entry）。
    const archive: WidgetArchive | null = WidgetSync.loadArchiveSync(
      TodayCourseWidgetData.archiveFilePath(this.context.filesDir));
    const dimension: Object | undefined = want.parameters?.['ohos.extra.param.key.form_dimension'];
    return formBindingData.createFormBindingData(
      TodayCourseWidgetData.binding(archive,
        TodayCourseWidgetAbility.courseLimitForDimension(dimension)));
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.refreshFormAsync(formId, true, wantParams);
  }

  private refreshFormAsync(formId: string, hasFormId: boolean,
    wantParams?: Record<string, Object>): void {
    const filesDir: string = this.context.filesDir;
    const dimension: Object | undefined = wantParams?.['ohos.extra.param.key.form_dimension'];
    const courseLimit: number = TodayCourseWidgetAbility.courseLimitForDimension(dimension);
    const work: Promise<void> = (async (): Promise<void> => {
      const archive: WidgetArchive | null = await WidgetSync.loadArchive(
        TodayCourseWidgetData.archiveFilePath(filesDir));
      const data: formBindingData.FormBindingData =
        formBindingData.createFormBindingData(TodayCourseWidgetData.binding(archive, courseLimit));
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
