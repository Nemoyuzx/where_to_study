// 使用独立 alias 验证真实 HarmonyOS ASSET 往返，不触碰正式教务凭据。
import { describe, it, expect } from '@ohos/hypium';
import {
  AssetCredentialStore, Credentials
} from '../../../main/ets/store/CredentialStore';

export default function credentialStoreDeviceTest() {
  describe('CredentialStoreDeviceTest', () => {
    it('asset_credentials_save_update_load_and_clear', 0, async () => {
      const store: AssetCredentialStore =
        new AssetCredentialStore('bupt-jwgl-ohos-device-test');
      await store.clear();
      try {
        await store.save(new Credentials('2026000000', 'first-password'));
        const first: Credentials | null = await store.load();
        expect(first !== null).assertTrue();
        expect(first?.account ?? '').assertEqual('2026000000');
        expect(first?.password ?? '').assertEqual('first-password');

        await store.save(new Credentials('2026000000', 'updated-password'));
        const updated: Credentials | null = await store.load();
        expect(updated !== null).assertTrue();
        expect(updated?.account ?? '').assertEqual('2026000000');
        expect(updated?.password ?? '').assertEqual('updated-password');
      } finally {
        await store.clear();
      }
      expect(await store.load()).assertNull();
    });
  });
}
