import { describe, it, expect } from '@ohos/hypium';
import { SettingsSession } from '../main/ets/view/SettingsSession';
import { SettingsPresentationSeedPolicy } from '../main/ets/model/LaunchSupport';

export default function settingsSessionTest() {
  describe('SettingsSessionTest', () => {
    it('keeps_unsaved_drafts_when_settings_layout_is_recreated', 0, () => {
      const session: SettingsSession = new SettingsSession();
      session.syncCustomDeadlineURL('https://example.org/old.json');
      session.editCustomDeadlineURL('https://example.org/new.json');
      session.preClassLeadDrafts = ['5', '15'];
      session.editingPreClassReminders = true;
      session.showingPrivacyPolicy = true;

      session.syncCustomDeadlineURL('https://example.org/old.json');
      expect(session.customDeadlineURLDraft).assertEqual('https://example.org/new.json');
      expect(session.preClassLeadDrafts.join(',')).assertEqual('5,15');
      expect(session.editingPreClassReminders).assertTrue();
      expect(session.showingPrivacyPolicy).assertTrue();
    });

    it('old_save_completion_cannot_replace_a_newer_url_draft', 0, () => {
      const session: SettingsSession = new SettingsSession();
      session.editCustomDeadlineURL('https://example.org/first.json');
      session.editCustomDeadlineURL('https://example.org/second.json');
      session.savedCustomDeadlineURL('https://example.org/first.json', 'https://example.org/first.json');
      expect(session.customDeadlineURLDraft).assertEqual('https://example.org/second.json');
      session.savedCustomDeadlineURL('https://example.org/second.json', 'https://example.org/second.json');
      expect(session.customDeadlineURLDraft).assertEqual('https://example.org/second.json');
      session.syncCustomDeadlineURL('https://example.org/current.json');
      expect(session.customDeadlineURLDraft).assertEqual('https://example.org/current.json');
    });

    it('clear_resets_only_temporary_ui_state', 0, () => {
      const session: SettingsSession = new SettingsSession();
      session.editCustomDeadlineURL('https://example.org/feed.json');
      session.editingPreClassReminders = true;
      session.preClassLeadDrafts = ['5', '20'];
      session.previewDimension = 4;
      session.clearDrafts();
      expect(session.customDeadlineURLDraft).assertEqual('');
      expect(session.editingPreClassReminders).assertFalse();
      expect(session.preClassLeadDrafts.join(',')).assertEqual('10');
      expect(session.previewDimension).assertEqual(3);
    });

    it('presentation_seed_requires_debug_review_flag_and_is_one_shot_in_memory', 0, () => {
      expect(SettingsPresentationSeedPolicy.allows(false, true, true)).assertFalse();
      expect(SettingsPresentationSeedPolicy.allows(true, false, true)).assertFalse();
      expect(SettingsPresentationSeedPolicy.allows(true, true, false)).assertFalse();
      expect(SettingsPresentationSeedPolicy.allows(true, true, true)).assertTrue();
      expect(SettingsPresentationSeedPolicy.allows(true, true, true, true)).assertFalse();
      expect(SettingsPresentationSeedPolicy.allows(true, false, true, true)).assertFalse();

      const session: SettingsSession = new SettingsSession();
      expect(session.seedOnlyScene).assertFalse();
      expect(session.seedReviewPresentationDraftsOnce()).assertTrue();
      expect(session.seedOnlyScene).assertTrue();
      expect(session.customDeadlineURLDraft).assertEqual('https://example.org/review-only-feed.json');
      expect(session.preClassLeadDrafts.join(',')).assertEqual('17');
      expect(session.editingPreClassReminders).assertTrue();
      session.editCustomDeadlineURL('https://example.org/changed-in-session.json');
      session.preClassLeadDrafts = ['23'];
      expect(session.seedReviewPresentationDraftsOnce()).assertFalse();
      expect(session.customDeadlineURLDraft).assertEqual('https://example.org/changed-in-session.json');
      expect(session.preClassLeadDrafts.join(',')).assertEqual('23');
    });
  });
}
