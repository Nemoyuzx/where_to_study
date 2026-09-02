// 设备侧真实联网测试：只使用不可能属于当前学生的未来年份虚构账号，
// 验证移动教务生产接口可达并返回明确的凭据拒绝，而不是客户端网络错误。
import { describe, it, expect } from '@ohos/hypium';
import { SJDAPIClient } from '../../../main/ets/net/SjdApi';
import { Credentials } from '../../../main/ets/store/CredentialStore';

export default function sjdNetworkDeviceTest() {
  describe('SjdNetworkDeviceTest', () => {
    it('invalid_fixture_credentials_reach_live_login_service', 0, async () => {
      const client: SJDAPIClient = new SJDAPIClient();
      const fixture: Credentials = new Credentials(
        '2099999999', 'wts-device-test-invalid-credential');
      let rejectionMessage: string = '';

      try {
        await client.login(fixture);
      } catch (e) {
        const error: Error = e as Error;
        rejectionMessage = error.message;
      }

      expect(rejectionMessage.includes('帐号不存在或密码错误')).assertTrue();
      expect(rejectionMessage.includes('无法连接')).assertFalse();
      expect(rejectionMessage.includes('网络请求失败')).assertFalse();
    });

    it('invalid_token_reaches_live_empty_body_curriculum_post', 0, async () => {
      const client: SJDAPIClient = new SJDAPIClient();
      let rejectionMessage: string = '';

      try {
        await client.curriculum('wts-device-test-invalid-token', 'all');
      } catch (e) {
        const error: Error = e as Error;
        rejectionMessage = error.message;
      }

      // 服务端应拒绝测试 token；关键是 NetworkKit 不再因显式空
      // extraData 抛 401 Parameter error。
      expect(rejectionMessage.length > 0).assertTrue();
      expect(rejectionMessage.includes('网络请求配置异常')).assertFalse();
      expect(rejectionMessage.includes('无法连接')).assertFalse();
      expect(rejectionMessage.includes('域名解析失败')).assertFalse();
      expect(rejectionMessage.includes('连接服务器超时')).assertFalse();
    });
  });
}
