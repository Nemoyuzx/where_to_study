import { describe, it, expect } from '@ohos/hypium';
import { http } from '@kit.NetworkKit';
import { CellularAssist } from '../main/ets/net/CellularAssist';

export default function cellularAssistTest() {
  describe('CellularAssistTest', () => {
    it('default_off_wifi_only_and_one_retry', 0, () => {
      expect(CellularAssist.enabled).assertFalse();
      expect(CellularAssist.canRetry(http.RequestMethod.GET, false, true, 2300007, false)).assertFalse();
      expect(CellularAssist.canRetry(http.RequestMethod.GET, true, false, 2300007, false)).assertFalse();
      expect(CellularAssist.canRetry(http.RequestMethod.GET, true, true, 2300007, true)).assertFalse();
      expect(CellularAssist.canRetry(http.RequestMethod.GET, true, true, 2300007, false)).assertTrue();
    });
    it('no_credential_post_http_tls_or_parse_retry', 0, () => {
      expect(CellularAssist.canRetry(http.RequestMethod.POST, true, true, 2300028, false)).assertFalse();
      expect(CellularAssist.canRetry(http.RequestMethod.HEAD, true, true, 2300028, false)).assertTrue();
      expect(CellularAssist.canRetry(http.RequestMethod.HEAD, true, true, 2300028, true)).assertFalse();
      for (const code of [401, 403, 423, 500, 2300060, 2300058, 2300998, 0]) {
        expect(CellularAssist.canRetry(http.RequestMethod.GET, true, true, code, false)).assertFalse();
      }
    });
  });
}
