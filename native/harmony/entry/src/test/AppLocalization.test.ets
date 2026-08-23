import { describe, it, expect } from '@ohos/hypium';
import {
  AppLanguage, AppLanguageInfo, AppLocalization
} from '../main/ets/common/AppLocalization';

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
    });

    it('dynamic_static_labels_use_english_patterns', 0, () => {
      expect(AppLocalization.text('3 门课', AppLanguage.english, 'en-US'))
        .assertEqual('3 courses');
      expect(AppLocalization.text('第 4 节', AppLanguage.english, 'en-US'))
        .assertEqual('Period 4');
    });
  });
}
