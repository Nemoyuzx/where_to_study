// 设备侧真实文件系统回归：同一缓存目录已存在时，后续原子写入必须幂等。
import { describe, it, expect } from '@ohos/hypium';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { JsonFile } from '../../../main/ets/store/JsonFile';

export default function jsonFileDeviceTest() {
  describe('JsonFileDeviceTest', () => {
    it('async_read_retains_missing_empty_and_byte_limit_semantics', 0, async () => {
      const context = AbilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const directory: string = context.filesDir + '/WhereToStudyNative-read-limit-test';
      const path: string = directory + '/bounded.json';
      try {
        expect(await JsonFile.readText(path, 16)).assertNull();
        await JsonFile.writeTextAtomic(path, '');
        expect(await JsonFile.readText(path, 16)).assertNull();
        await JsonFile.writeTextAtomic(path, '🎓🎓🎓🎓');
        expect(await JsonFile.readText(path, 16)).assertEqual('🎓🎓🎓🎓');
        let rejected: boolean = false;
        await JsonFile.readText(path, 15).catch(() => { rejected = true; });
        expect(rejected).assertTrue();
      } finally { await JsonFile.removeDirectory(directory); }
    });
    it('atomic_write_reuses_existing_cache_directory', 0, async () => {
      const context = AbilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const directory: string = context.filesDir + '/WhereToStudyNative-device-test';
      const path: string = directory + '/schedule.json';
      try {
        await JsonFile.writeTextAtomic(path, '{"revision":1}');
        await JsonFile.writeTextAtomic(path, '{"revision":2}');
        expect(await JsonFile.readText(path)).assertEqual('{"revision":2}');
      } finally {
        await JsonFile.removeDirectory(directory);
      }
    });
  });
}
