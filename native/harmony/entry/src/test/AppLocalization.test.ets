import { describe, it, expect } from '@ohos/hypium';
import {
  AppLanguage, AppLanguageInfo, AppLocalization
} from '../main/ets/common/AppLocalization';
import { AppMeta } from '../main/ets/common/AppMeta';

export default function appLocalizationTest() {
  describe('AppLocalizationTest', () => {
    it('system_language_resolves_to_supported_language', 0, () => {
      expect(AppLanguageInfo.resolved(AppLanguage.system, 'zh-Hans-CN'))
        .assertEqual(AppLanguage.simplifiedChinese);
      expect(AppLanguageInfo.resolved(AppLanguage.system, 'en-US'))
        .assertEqual(AppLanguage.english);
      expect(AppLanguageInfo.resolved(AppLanguage.simplifiedChinese, 'en-US'))
        .assertEqual(AppLanguage.simplifiedChinese);
    });

    it('static_ui_translates_but_api_content_stays_verbatim', 0, () => {
      expect(AppLocalization.text('教学日历', AppLanguage.english, 'zh-Hans'))
        .assertEqual('Calendar');
      expect(AppLocalization.text('ICPC Asia Regional 2026', AppLanguage.english, 'en-US'))
        .assertEqual('ICPC Asia Regional 2026');
      expect(AppLocalization.text('教学日历', AppLanguage.simplifiedChinese, 'en-US'))
        .assertEqual('教学日历');
      expect(AppLocalization.text('班车数据格式不正确。', AppLanguage.english, 'en-US'))
        .assertEqual('The shuttle data format is invalid.');
      expect(AppLocalization.text('班车服务返回 HTTP 503。', AppLanguage.english, 'en-US'))
        .assertEqual('The shuttle service returned HTTP 503.');
      expect(AppLocalization.text('系统安全存储不可用，账号密码未能保存，请稍后重试。',
        AppLanguage.english, 'en-US'))
        .assertEqual('Secure storage is unavailable. Your account and password were not saved. Try again later.');
      expect(AppLocalization.text(AppMeta.appFilingLabel, AppLanguage.english, 'en-US'))
        .assertEqual('App filing: 琼ICP备2026012322号-2A');
      expect(AppLocalization.text(AppMeta.appFilingLabel, AppLanguage.simplifiedChinese, 'en-US'))
        .assertEqual('APP 备案：琼ICP备2026012322号-2A');
      expect(AppMeta.appFilingURL).assertEqual('https://beian.miit.gov.cn/');
      expect(AppLocalization.text('系统安全存储操作失败（24000002）。',
        AppLanguage.english, 'en-US'))
        .assertEqual('Secure storage failed (24000002).');
      expect(AppLocalization.text(
        '安全连接校验失败（网络错误 2300060），请关闭网络代理、完成校园网认证或切换网络后重试。',
        AppLanguage.english, 'en-US'))
        .assertEqual('Secure connection validation failed (network error 2300060). Disable the network proxy, ' +
          'complete campus-network sign-in, or switch networks.');
      expect(AppLocalization.text(
        '域名解析失败（网络错误 2300006），请检查 DNS、代理或校园网认证后重试。',
        AppLanguage.english, 'en-US'))
        .assertEqual('DNS resolution failed (network error 2300006). Check DNS, proxy, or ' +
          'campus-network sign-in and try again.');
    });

    it('dynamic_static_labels_use_english_patterns', 0, () => {
      expect(AppLocalization.text('1 门课', AppLanguage.english, 'en-US'))
        .assertEqual('1 course');
      expect(AppLocalization.text('3 门课', AppLanguage.english, 'en-US'))
        .assertEqual('3 courses');
      expect(AppLocalization.text('第 4 节', AppLanguage.english, 'en-US'))
        .assertEqual('Period 4');
      expect(AppLocalization.text('无课', AppLanguage.english, 'en-US'))
        .assertEqual('No courses');
      expect(AppLocalization.text('视图', AppLanguage.english, 'en-US'))
        .assertEqual('View');
    });
  });
}
