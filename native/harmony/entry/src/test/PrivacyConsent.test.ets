import { describe, it, expect } from '@ohos/hypium';
import { PrivacyConsentInfo } from '../main/ets/store/PrivacyConsentStore';

export default function privacyConsentTest() {
  describe('PrivacyConsentTest', () => {
    it('release_and_normal_launch_never_accept_privacy_testing_bypass', 0, () => {
      expect(PrivacyConsentInfo.allowsTestingBypass(false, true, true)).assertFalse();
      expect(PrivacyConsentInfo.allowsTestingBypass(true, false, true)).assertFalse();
      expect(PrivacyConsentInfo.allowsTestingBypass(true, true, false)).assertFalse();
      expect(PrivacyConsentInfo.allowsTestingBypass(true, true, true)).assertTrue();
    });
    it('only_current_or_newer_policy_version_is_accepted', 0, () => {
      expect(PrivacyConsentInfo.preferenceKey).assertEqual('privacyConsentVersion');
      expect(PrivacyConsentInfo.currentVersion).assertEqual(1);
      expect(PrivacyConsentInfo.isAccepted(0)).assertFalse();
      expect(PrivacyConsentInfo.isAccepted(PrivacyConsentInfo.currentVersion)).assertTrue();
      expect(PrivacyConsentInfo.isAccepted(PrivacyConsentInfo.currentVersion + 1)).assertTrue();
    });
  });
}
