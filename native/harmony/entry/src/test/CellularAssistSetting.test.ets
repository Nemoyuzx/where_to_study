// 合成偏好验证 AppModel 开关，不创建 NetworkKit 请求或真实蜂窝连接。
import { describe, it, expect } from '@ohos/hypium';
import { AppModel } from '../main/ets/model/AppModel';
import { CellularAssist } from '../main/ets/net/CellularAssist';
import { RecordingFavoritePreferences, testModel } from './FavoriteDeadlineLimit.test';

class CellularGate {
  private releaseGate: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.releaseGate = resolve; });
  release(): void { this.releaseGate(); }
}

class CellularPreferences extends RecordingFavoritePreferences {
  saved: boolean | null = null;
  attempts: boolean[] = [];
  removals: number = 0;
  failAttempt: number = 0;
  blockNextWrite: CellularGate | null = null;
  readonly writeStarted: CellularGate = new CellularGate();

  async getBool(key: string, fallback: boolean): Promise<boolean> {
    if (key === CellularAssist.preferenceKey) { return this.saved ?? fallback; }
    return super.getBool(key, fallback);
  }

  async setBool(key: string, value: boolean): Promise<void> {
    if (key !== CellularAssist.preferenceKey) { return super.setBool(key, value); }
    this.attempts.push(value);
    const attempt: number = this.attempts.length;
    const gate: CellularGate | null = this.blockNextWrite;
    this.blockNextWrite = null;
    if (gate !== null) { this.writeStarted.release(); await gate.promise; }
    if (attempt === this.failAttempt) { throw new Error('synthetic preference failure'); }
    this.saved = value;
  }

  async remove(key: string): Promise<void> {
    if (key === CellularAssist.preferenceKey) { this.removals++; this.saved = null; }
    await super.remove(key);
  }
}

async function settleMicrotasks(): Promise<void> {
  for (let index: number = 0; index < 160; index++) { await Promise.resolve(); }
}

export default function cellularAssistSettingTest() {
  describe('CellularAssistSettingTest', () => {
    it('defaults_off_and_rapid_on_off_writes_are_serial_with_latest_state', 0, async () => {
      CellularAssist.enabled = false;
      const preferences: CellularPreferences = new CellularPreferences('cellular-setting-rapid');
      const model: AppModel = testModel(preferences);
      expect(model.cellularAssistEnabled).assertFalse();
      expect(CellularAssist.enabled).assertFalse();
      const gate: CellularGate = new CellularGate();
      preferences.blockNextWrite = gate;
      const first: Promise<boolean> = model.setCellularAssistEnabled(true);
      const last: Promise<boolean> = model.setCellularAssistEnabled(false);
      await preferences.writeStarted.promise;
      expect(preferences.attempts.length).assertEqual(1);
      expect(model.cellularAssistEnabled).assertFalse();
      expect(CellularAssist.enabled).assertFalse();
      gate.release();
      expect(await first).assertTrue();
      expect(await last).assertTrue();
      expect(preferences.attempts.join(',')).assertEqual('true,false');
      expect(preferences.saved).assertFalse();
      expect(model.cellularAssistEnabled).assertFalse();
      expect(CellularAssist.enabled).assertFalse();
    });

    it('failed_disable_stays_off_even_if_last_persisted_value_was_on', 0, async () => {
      CellularAssist.enabled = false;
      const preferences: CellularPreferences = new CellularPreferences('cellular-setting-failure');
      const model: AppModel = testModel(preferences);
      expect(await model.setCellularAssistEnabled(true)).assertTrue();
      preferences.failAttempt = 2;
      expect(await model.setCellularAssistEnabled(false)).assertFalse();
      expect(preferences.saved).assertTrue();
      expect(model.cellularAssistEnabled).assertFalse();
      expect(CellularAssist.enabled).assertFalse();
      expect(model.statusMessage).assertEqual(
        '移动网络辅助已在本次会话中关闭，但设置未保存；下次启动请检查开关。');
      model.enterReviewDemo();
      model.exitReviewDemo();
      await settleMicrotasks();
      expect(model.cellularAssistEnabled).assertFalse();
      expect(CellularAssist.enabled).assertFalse();
      preferences.failAttempt = 0;
      expect(await model.setCellularAssistEnabled(true)).assertTrue();
      expect(model.cellularAssistEnabled).assertTrue();
      expect(CellularAssist.enabled).assertTrue();
      CellularAssist.enabled = false;
    });

    it('clear_invalidates_pending_write_and_removes_pref_before_old_callback_can_reenable', 0, async () => {
      CellularAssist.enabled = false;
      const preferences: CellularPreferences = new CellularPreferences('cellular-setting-clear');
      const model: AppModel = testModel(preferences);
      const gate: CellularGate = new CellularGate();
      preferences.blockNextWrite = gate;
      const pending: Promise<boolean> = model.setCellularAssistEnabled(true);
      await preferences.writeStarted.promise;
      const clearing: Promise<void> = model.clearLocalData();
      expect(CellularAssist.enabled).assertFalse();
      gate.release();
      expect(await pending).assertFalse();
      // 无 AppContext 的系统卡片清理可能在偏好删除后失败；只验证本开关边界。
      await clearing.catch(() => {});
      expect(preferences.removals).assertEqual(1);
      expect(preferences.saved).assertNull();
      expect(model.cellularAssistEnabled).assertFalse();
      expect(CellularAssist.enabled).assertFalse();
    });
  });
}
