import { asset } from '@kit.AssetStoreKit';
import { describe, it, expect } from '@ohos/hypium';
import {
  Credentials, credentialQueryAttributes, credentialUpdateAttributes
} from '../main/ets/store/CredentialStore';

export default function credentialStoreTest() {
  describe('CredentialStoreTest', () => {
    it('legacy_credentials_use_academic_password_and_cloud_override_round_trips', 0, () => {
      const legacy: Credentials = Credentials.fromJsonText('{"account":"student","password":"academic"}');
      expect(legacy.cloudPassword).assertEqual('');
      expect(legacy.effectiveCloudPassword()).assertEqual('academic');
      const stored: Credentials = Credentials.fromJsonText(
        new Credentials('student', 'academic', 'cloud').toJsonText());
      expect(stored.password).assertEqual('academic');
      expect(stored.effectiveCloudPassword()).assertEqual('cloud');
    });

    it('cloud_password_drafts_preserve_replace_clear_and_isolate_accounts', 0, () => {
      const stored: Credentials = new Credentials('student', 'academic', 'cloud');
      expect(Credentials.withCloudPasswordDraft(' student ', 'new-academic', stored, '', false)
        .effectiveCloudPassword()).assertEqual('cloud');
      expect(Credentials.withCloudPasswordDraft('student', 'academic', stored, 'new-cloud', false)
        .effectiveCloudPassword()).assertEqual('new-cloud');
      expect(Credentials.withCloudPasswordDraft('student', 'academic', stored, '', true)
        .effectiveCloudPassword()).assertEqual('academic');
      expect(Credentials.withCloudPasswordDraft('other', 'other-academic', stored, '', false)
        .effectiveCloudPassword()).assertEqual('other-academic');
    });

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
