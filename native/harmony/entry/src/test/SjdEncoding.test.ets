// 表单编码、URL 安全策略与响应上限（与 iOS ScheduleLogicTests 对齐）。
import { describe, it, expect } from '@ohos/hypium';
import {
  SJDResponseEndpoint, SJDResponseLimits, SJDFormURLEncoder
} from '../main/ets/net/SjdEncoding';
import { UrlPolicy } from '../main/ets/net/UrlPolicy';

export default function sjdEncodingTest() {
  describe('SjdEncodingTest', () => {
    it('form_encoding_matches_swift_reserved_and_unicode_cases', 0, () => {
      const values: Map<string, string> = new Map<string, string>();
      values.set('userNo', '2026+test');
      values.set('pwd', 'A+B C&=中文*._-');
      expect(SJDFormURLEncoder.encode(values))
        .assertEqual('pwd=A%2BB+C%26%3D%E4%B8%AD%E6%96%87*._-&userNo=2026%2Btest');
    });

    it('url_policy_allows_only_secure_same_origin', 0, () => {
      const host: string = 'jwglweixin.bupt.edu.cn';
      expect(UrlPolicy.allows('https://jwglweixin.bupt.edu.cn/bjyddx/login', host)).assertTrue();
      expect(UrlPolicy.allows('https://jwglweixin.bupt.edu.cn:443/bjyddx/student/curriculum', host))
        .assertTrue();
      expect(UrlPolicy.allows('http://jwglweixin.bupt.edu.cn/bjyddx/login', host)).assertFalse();
      expect(UrlPolicy.allows('https://example.com/bjyddx/login', host)).assertFalse();
      expect(UrlPolicy.allows('https://sub.jwglweixin.bupt.edu.cn/bjyddx/login', host)).assertFalse();
      expect(UrlPolicy.allows('https://jwglweixin.bupt.edu.cn:444/bjyddx/login', host)).assertFalse();
      expect(UrlPolicy.allows('https://user@jwglweixin.bupt.edu.cn/bjyddx/login', host)).assertFalse();
    });

    it('response_limits_match_swift_endpoint_caps', 0, () => {
      expect(SJDResponseLimits.maximumBytes(SJDResponseEndpoint.login)).assertEqual(64 * 1024);
      expect(SJDResponseLimits.maximumBytes(SJDResponseEndpoint.curriculum))
        .assertEqual(2 * 1024 * 1024);
      expect(SJDResponseLimits.maximumBytes(SJDResponseEndpoint.classrooms))
        .assertEqual(2 * 1024 * 1024);
    });
  });
}
