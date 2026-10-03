// 真实 AppModel 语言路径 + 合成偏好；所有设备/网络依赖由 FavoriteDeadlineLimit 的
// 显式合成工厂注入，不初始化 AppContext，也不发送教务请求。
import { describe, it, expect } from '@ohos/hypium';
import { AppLanguage } from '../main/ets/common/AppLocalization';
import { AppModel } from '../main/ets/model/AppModel';
import { FavoriteReminderScheduler, RecordingFavoritePreferences, testModel } from './FavoriteDeadlineLimit.test';

class LanguageGate {
  private releaseGate: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.releaseGate = resolve; });
  release(): void { this.releaseGate(); }
}

class LanguagePreferences extends RecordingFavoritePreferences {
  languageValue: string | null = null;
  languageAttempts: string[] = [];
  languageWrites: string[] = [];
  languageRemovals: number = 0;
  failedAttempts: Set<number> = new Set<number>();
  blockNextWrite: LanguageGate | null = null;
  blockNextRead: LanguageGate | null = null;
  readonly writeStarted: LanguageGate = new LanguageGate();
  readonly readStarted: LanguageGate = new LanguageGate();

  async getString(key: string): Promise<string | null> {
    if (key !== 'appLanguage') { return super.getString(key); }
    const captured: string | null = this.languageValue;
    const gate: LanguageGate | null = this.blockNextRead;
    this.blockNextRead = null;
    if (gate !== null) { this.readStarted.release(); await gate.promise; }
    return captured;
  }

  async setString(key: string, value: string): Promise<void> {
    if (key !== 'appLanguage') { return super.setString(key, value); }
    this.languageAttempts.push(value);
    const attempt: number = this.languageAttempts.length;
    const gate: LanguageGate | null = this.blockNextWrite;
    this.blockNextWrite = null;
    if (gate !== null) { this.writeStarted.release(); await gate.promise; }
    if (this.failedAttempts.has(attempt)) { throw new Error('synthetic language write failed'); }
    this.languageValue = value;
    this.languageWrites.push(value);
  }

  async remove(key: string): Promise<void> {
    if (key === 'appLanguage') {
      this.languageRemovals++;
      this.languageValue = null;
    }
    await super.remove(key);
  }
}

async function settleMicrotasks(): Promise<void> {
  for (let index: number = 0; index < 160; index++) { await Promise.resolve(); }
}

export default function languageSettingTransactionTest() {
  describe('LanguageSettingTransactionTest', () => {
    it('same_value_does_not_write_or_reconcile_reminders', 0, async () => {
      const preferences: LanguagePreferences = new LanguagePreferences('language-same-tests');
      const scheduler: FavoriteReminderScheduler = new FavoriteReminderScheduler();
      const model: AppModel = testModel(preferences, scheduler);
      await model.setLanguageSetting(AppLanguage.system);
      expect(preferences.languageAttempts.length).assertEqual(0);
      expect(scheduler.cancelCount).assertEqual(0);
      expect(model.dailyCourseNotificationStatusMessage).assertEqual('');
    });

    it('rapid_zh_en_zh_writes_are_serial_and_latest_state_wins', 0, async () => {
      const preferences: LanguagePreferences = new LanguagePreferences('language-queue-tests');
      const scheduler: FavoriteReminderScheduler = new FavoriteReminderScheduler();
      const model: AppModel = testModel(preferences, scheduler);
      const gate: LanguageGate = new LanguageGate();
      preferences.blockNextWrite = gate;
      const first: Promise<void> = model.setLanguageSetting(AppLanguage.simplifiedChinese);
      const second: Promise<void> = model.setLanguageSetting(AppLanguage.english);
      const third: Promise<void> = model.setLanguageSetting(AppLanguage.simplifiedChinese);
      await preferences.writeStarted.promise;
      expect(preferences.languageAttempts.join(',')).assertEqual('zh-Hans');
      expect(model.languageSetting()).assertEqual(AppLanguage.simplifiedChinese);
      gate.release();
      await first;
      await second;
      await third;
      expect(preferences.languageAttempts.join(',')).assertEqual('zh-Hans,en,zh-Hans');
      expect(preferences.languageValue).assertEqual(AppLanguage.simplifiedChinese);
      expect(model.languageSetting()).assertEqual(AppLanguage.simplifiedChinese);
      expect(scheduler.cancelCount).assertEqual(1);
    });

    it('failed_first_or_last_write_rolls_back_to_the_last_committed_value', 0, async () => {
      const firstFailure: LanguagePreferences = new LanguagePreferences('language-first-failure');
      firstFailure.failedAttempts.add(1);
      const firstModel: AppModel = testModel(firstFailure);
      await firstModel.setLanguageSetting(AppLanguage.english);
      expect(firstModel.languageSetting()).assertEqual(AppLanguage.system);
      expect(firstFailure.languageValue).assertNull();
      expect(firstModel.statusMessage).assertEqual('无法保存语言设置');
      await firstModel.setLanguageSetting(AppLanguage.simplifiedChinese);
      expect(firstFailure.languageValue).assertEqual(AppLanguage.simplifiedChinese);

      const lastFailure: LanguagePreferences = new LanguagePreferences('language-last-failure');
      lastFailure.failedAttempts.add(2);
      const lastModel: AppModel = testModel(lastFailure);
      const first: Promise<void> = lastModel.setLanguageSetting(AppLanguage.english);
      const last: Promise<void> = lastModel.setLanguageSetting(AppLanguage.simplifiedChinese);
      await first;
      await last;
      expect(lastFailure.languageAttempts.join(',')).assertEqual('en,zh-Hans');
      expect(lastFailure.languageValue).assertEqual(AppLanguage.english);
      expect(lastModel.languageSetting()).assertEqual(AppLanguage.english);
      expect(lastModel.statusMessage).assertEqual('无法保存语言设置');
    });

    it('clear_waits_for_pending_write_and_old_language_read_cannot_repopulate_it', 0, async () => {
      const preferences: LanguagePreferences = new LanguagePreferences('language-clear-tests');
      const model: AppModel = testModel(preferences);
      const writeGate: LanguageGate = new LanguageGate();
      preferences.blockNextWrite = writeGate;
      const pending: Promise<void> = model.setLanguageSetting(AppLanguage.english);
      await preferences.writeStarted.promise;
      const clearing: Promise<void> = model.clearLocalData();
      expect(preferences.languageRemovals).assertEqual(0);
      writeGate.release();
      await pending;
      // 无 AppContext 的系统卡片清理可能在 appLanguage 删除后失败；
      // 本用例只宣称语言写入队列/删除顺序与 UI 状态，不宣称整个清除流程成功。
      await clearing.catch(() => {});
      expect(preferences.languageRemovals).assertEqual(1);
      expect(preferences.languageValue).assertNull();
      expect(model.languageSetting()).assertEqual(AppLanguage.system);

      preferences.languageValue = AppLanguage.english;
      const readGate: LanguageGate = new LanguageGate();
      preferences.blockNextRead = readGate;
      model.enterReviewDemo();
      model.exitReviewDemo();
      await preferences.readStarted.promise;
      const laterClear: Promise<void> = model.clearLocalData();
      readGate.release();
      await laterClear.catch(() => {});
      await settleMicrotasks();
      expect(preferences.languageValue).assertNull();
      expect(model.languageSetting()).assertEqual(AppLanguage.system);
    });
  });
}
