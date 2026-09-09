// 真实沙箱集成：调用主应用使用的归档写入，再调用 FormExtensionAbility 使用的同步读取。
import { describe, it, expect } from '@ohos/hypium';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { JsonFile } from '../../../main/ets/store/JsonFile';
import { WidgetSync } from '../../../main/ets/widget/WidgetSync';
import { TodayCourseWidgetData, WidgetCoursePreferences } from '../../../main/ets/widget/TodayCourseWidgetData';
import { Course, ScheduleSnapshot } from '../../../main/ets/common/Models';
import { ColorThemeSelection } from '../../../main/ets/common/ColorThemes';

export default function widgetSyncDeviceTest() {
  describe('WidgetSyncDeviceTest', () => {
    it('app_writer_and_form_reader_share_paths_without_restoring_legacy_account', 0, async () => {
      const context = AbilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const filesDir: string = context.filesDir + '/widget-sync-integration-test';
      const legacy: string = TodayCourseWidgetData.archiveFilePath(filesDir + '/WhereToStudyNative');
      const legacyTheme: string = WidgetSync.themePath(filesDir + '/WhereToStudyNative');
      try {
        await JsonFile.writeTextAtomic(legacy, '{"courses":"previous-account"}');
        await JsonFile.writeTextAtomic(legacyTheme, '{"preset":"rose"}');
        // 不把历史错误路径当作 fallback。
        expect(WidgetSync.loadArchiveFromFilesSync(filesDir) === null).assertTrue();
        expect(WidgetSync.loadThemeSync(filesDir).preset).assertEqual('default');
        const schedule = new ScheduleSnapshot('current-account', '2026-09-07', '2026-09-09T00:00:00+08:00', [
          new Course('current-course', '当前账号课程', '教师', '教一', '1', [1], [], 3, 0, 1, '1-2节', '08:00-09:35')
        ]);
        await WidgetSync.writeArchive(filesDir, schedule, new WidgetCoursePreferences(false, true, 2));
        await WidgetSync.writeTheme(filesDir, new ColorThemeSelection('ocean'));
        const archive = WidgetSync.loadArchiveFromFilesSync(filesDir);
        expect(archive !== null).assertTrue();
        expect(archive?.courses[0].name).assertEqual('当前账号课程');
        expect(archive?.preferences.showsLocation).assertFalse();
        expect(WidgetSync.loadThemeSync(filesDir).preset).assertEqual('ocean');
        expect(await JsonFile.readText(legacy) === null).assertTrue();
        expect(await JsonFile.readText(legacyTheme) === null).assertTrue();
        await WidgetSync.writeArchive(filesDir, null);
        expect(WidgetSync.loadArchiveFromFilesSync(filesDir) === null).assertTrue();
        expect(await JsonFile.readText(legacy) === null).assertTrue();
      } finally {
        await JsonFile.removeDirectory(filesDir);
      }
    });
  });
}
