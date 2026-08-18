// 今日课程服务卡片（FormExtensionAbility），对应 iOS 端 WidgetKit
// WhereToStudyWidget。卡片与主应用同沙箱，直接读取归档文件生成绑定数据。
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { WidgetSync } from './WidgetSync';
import { TodayCourseWidgetData, WidgetArchive } from './TodayCourseWidgetData';

export default class TodayCourseWidgetAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    // 同步读取归档生成初始绑定（等价于 iOS TimelineProvider 的 entry）。
    const archive: WidgetArchive | null = WidgetSync.loadArchiveSync(
      TodayCourseWidgetData.archiveFilePath(this.context.filesDir));
    return formBindingData.createFormBindingData(TodayCourseWidgetData.binding(archive));
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.refreshFormAsync(formId, true);
  }

  private refreshFormAsync(formId: string, hasFormId: boolean): void {
    const filesDir: string = this.context.filesDir;
    const work: Promise<void> = (async (): Promise<void> => {
      const archive: WidgetArchive | null = await WidgetSync.loadArchive(
        TodayCourseWidgetData.archiveFilePath(filesDir));
      const data: formBindingData.FormBindingData =
        formBindingData.createFormBindingData(TodayCourseWidgetData.binding(archive));
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
