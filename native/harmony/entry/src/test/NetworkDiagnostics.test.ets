import { describe, it, expect } from '@ohos/hypium';
import { NetworkDiagnostics } from '../main/ets/net/NetworkDiagnostics';

export default function networkDiagnosticsTest() {
  describe('NetworkDiagnosticsTest', () => {
    it('dns_errors_explain_dns_proxy_and_campus_login', 0, () => {
      expect(NetworkDiagnostics.userMessage(2300006))
        .assertEqual('域名解析失败（网络错误 2300006），请检查 DNS、代理或校园网认证后重试。');
    });

    it('tls_errors_explain_interception_instead_of_offline', 0, () => {
      expect(NetworkDiagnostics.userMessage(2300060))
        .assertEqual('安全连接校验失败（网络错误 2300060），请关闭网络代理、完成校园网认证或切换网络后重试。');
    });

    it('timeout_and_unknown_errors_keep_reportable_context', 0, () => {
      expect(NetworkDiagnostics.userMessage(2300028))
        .assertEqual('连接服务器超时（网络错误 2300028），请切换网络或稍后重试。');
      expect(NetworkDiagnostics.userMessage(0))
        .assertEqual('无法连接服务器（未知网络错误），请切换网络或完成校园网认证后重试。');
    });

    it('ipv4_retry_is_limited_to_route_failures', 0, () => {
      expect(NetworkDiagnostics.shouldRetryIPv4(2300006)).assertTrue();
      expect(NetworkDiagnostics.shouldRetryIPv4(2300007)).assertTrue();
      expect(NetworkDiagnostics.shouldRetryIPv4(2300028)).assertTrue();
      expect(NetworkDiagnostics.shouldRetryIPv4(2300060)).assertFalse();
      expect(NetworkDiagnostics.shouldRetryIPv4(401)).assertFalse();
    });
  });
}
