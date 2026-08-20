import { asset } from '@kit.AssetStoreKit';
import { describe, it, expect } from '@ohos/hypium';
import { Credentials, credentialUpdateAttributes } from '../main/ets/store/CredentialStore';

export default function credentialStoreTest() {
  describe('CredentialStoreTest', () => {
    it('update_attributes_only_contain_secret', 0, () => {
      const attributes: asset.AssetMap = credentialUpdateAttributes(
        new Credentials('2026000000', 'password')
      );

      expect(attributes.has(asset.Tag.SECRET)).assertTrue();
      expect(attributes.has(asset.Tag.ACCESSIBILITY)).assertFalse();
      expect(attributes.size).assertEqual(1);
    });
  });
}
