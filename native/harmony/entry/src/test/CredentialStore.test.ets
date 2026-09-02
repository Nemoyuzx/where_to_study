import { asset } from '@kit.AssetStoreKit';
import { describe, it, expect } from '@ohos/hypium';
import {
  Credentials, credentialQueryAttributes, credentialUpdateAttributes
} from '../main/ets/store/CredentialStore';

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

    it('query_attributes_request_the_secret_explicitly', 0, () => {
      const attributes: asset.AssetMap = credentialQueryAttributes('bupt-jwgl-test');

      expect(attributes.has(asset.Tag.ALIAS)).assertTrue();
      expect(attributes.get(asset.Tag.RETURN_TYPE) as number)
        .assertEqual(asset.ReturnType.ALL);
      expect(attributes.has(asset.Tag.SECRET)).assertFalse();
      expect(attributes.size).assertEqual(2);
    });
  });
}
