// All storage/network dependencies are synthetic; no AppContext, ASSET, or
// browser access. Gates model ordering without sleeps or elapsed-time guesses.
import { describe, it, expect } from '@ohos/hypium';
import { AppModel } from '../main/ets/model/AppModel';
import { ScheduleSnapshot } from '../main/ets/common/Models';
import { ScheduleStoring } from '../main/ets/store/ScheduleStore';
import { Credentials, CredentialStoring } from '../main/ets/store/CredentialStore';
import { CourseDTOCache, CourseDTOCacheStore } from '../main/ets/store/CourseDTOCacheStore';
import { RecordingFavoritePreferences, testModel } from './FavoriteDeadlineLimit.test';

class LaunchGate {
  private finish: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.finish = resolve; });
  release(): void { this.finish(); }
}

class LaunchPreferences extends RecordingFavoritePreferences {
  termGate: LaunchGate | null = null;
  termStarted: LaunchGate = new LaunchGate();
  failKey: string = '';
  failQM: boolean = false;
  async getOptionalBool(key: string): Promise<boolean | null> {
    if (this.failQM) { throw new Error('synthetic consent read failed'); }
    return true;
  }
  async getString(key: string): Promise<string | null> {
    if (key === this.failKey) { throw new Error('synthetic preference read failed'); }
    if (key === 'termID') {
      this.termStarted.release();
      if (this.termGate !== null) { await this.termGate.promise; }
      return '2026-2027-1';
    }
    if (key === 'termStartDate') { return '2026-08-31'; }
    return super.getString(key);
  }
}

class LaunchSchedules implements ScheduleStoring {
  loads: number = 0;
  gate: LaunchGate | null = null;
  started: LaunchGate = new LaunchGate();
  readonly cached: ScheduleSnapshot = new ScheduleSnapshot('2026-2027-1', '2026-08-31', '2026-10-05T00:00:00Z', []);
  async load(): Promise<ScheduleSnapshot | null> {
    this.loads++; this.started.release();
    if (this.gate !== null) { await this.gate.promise; }
    return this.cached;
  }
  async save(schedule: ScheduleSnapshot): Promise<void> {}
  async clear(): Promise<void> {}
}

class LaunchCredentials implements CredentialStoring {
  loads: number = 0;
  fail: boolean = false;
  async load(): Promise<Credentials | null> {
    this.loads++;
    if (this.fail) { throw new Error('synthetic secure store failure'); }
    return null;
  }
  async save(credentials: Credentials): Promise<void> {}
  async clear(): Promise<void> {}
}

class DraftCredentials implements CredentialStoring {
  value: Credentials | null = new Credentials('synthetic-account-a', 'synthetic-original', 'synthetic-cloud-original');
  loads: number = 0;
  saves: number = 0;
  clears: number = 0;
  firstGate: LaunchGate | null = null;
  secondGate: LaunchGate | null = null;
  saveGate: LaunchGate | null = null;
  readonly firstStarted: LaunchGate = new LaunchGate();
  readonly secondStarted: LaunchGate = new LaunchGate();
  readonly saveStarted: LaunchGate = new LaunchGate();
  private queue: Promise<void> = Promise.resolve();
  async load(): Promise<Credentials | null> {
    let result: Credentials | null = null;
    const work: Promise<void> = this.queue.then(async (): Promise<void> => {
      this.loads++;
      const captured: Credentials | null = this.value;
      const gate: LaunchGate | null = this.loads === 1 ? this.firstGate : this.loads === 2 ? this.secondGate : null;
      if (this.loads === 1) { this.firstStarted.release(); }
      if (this.loads === 2) { this.secondStarted.release(); }
      if (gate !== null) { await gate.promise; }
      result = captured;
    });
    this.queue = work.catch((): void => {});
    await work; return result;
  }
  async save(value: Credentials): Promise<void> {
    const work: Promise<void> = this.queue.then(async (): Promise<void> => {
      this.saveStarted.release();
      if (this.saveGate !== null) { await this.saveGate.promise; }
      this.saves++; this.value = value;
    });
    this.queue = work.catch((): void => {}); await work;
  }
  async clear(): Promise<void> {
    const work: Promise<void> = this.queue.then((): void => { this.clears++; this.value = null; });
    this.queue = work.catch((): void => {}); await work;
  }
}

class DraftCourseDTOStore extends CourseDTOCacheStore {
  async load(scope: string): Promise<CourseDTOCache | null> { return null; }
  async save(cache: CourseDTOCache, current: () => boolean): Promise<boolean> { return current(); }
  async clear(): Promise<void> {}
}

function draftModel(preferences: LaunchPreferences, credentials: DraftCredentials): AppModel {
  return testModel(preferences, undefined, new LaunchSchedules(), credentials, new DraftCourseDTOStore());
}

export default function launchHydrationTest() {
  describe('LaunchHydrationTest', () => {
    it('local_ready_waits_for_restored_term_and_cached_schedule_and_launch_is_single_flight', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('launch-order-tests');
      const schedules: LaunchSchedules = new LaunchSchedules();
      const credentials: LaunchCredentials = new LaunchCredentials();
      const termGate: LaunchGate = new LaunchGate(); preferences.termGate = termGate;
      const cacheGate: LaunchGate = new LaunchGate(); schedules.gate = cacheGate;
      const model: AppModel = testModel(preferences, undefined, schedules, credentials);
      const first: Promise<void> = model.launch(); const second: Promise<void> = model.launch();
      await preferences.termStarted.promise;
      expect(model.qmplusEnabled).assertTrue();
      expect(model.localHydrationReady).assertFalse(); expect(schedules.loads).assertEqual(0);
      termGate.release(); await schedules.started.promise;
      expect(model.termID).assertEqual('2026-2027-1'); expect(model.localHydrationReady).assertFalse();
      expect(credentials.loads).assertEqual(1);
      cacheGate.release(); await first; await second;
      expect(schedules.loads).assertEqual(1);
      expect(model.schedule === schedules.cached).assertTrue(); expect(model.localHydrationReady).assertTrue();
    });
    it('one_failed_general_preference_does_not_skip_later_settings_or_cached_schedule', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('launch-partial-prefs');
      preferences.failKey = 'campusID';
      const schedules: LaunchSchedules = new LaunchSchedules();
      const model: AppModel = testModel(preferences, undefined, schedules);
      await model.launch();
      expect(model.termID).assertEqual('2026-2027-1');
      expect(model.schedule === schedules.cached).assertTrue();
      expect(model.localHydrationReady).assertTrue(); expect(model.statusMessage).assertEqual('数据暂时无法读取。');
    });
    it('failed_QM_consent_and_secure_store_reads_are_visible_and_never_enable_QM', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('launch-security-failures'); preferences.failQM = true;
      const schedules: LaunchSchedules = new LaunchSchedules();
      const credentials: LaunchCredentials = new LaunchCredentials();
      const model: AppModel = testModel(preferences, undefined, schedules, credentials);
      await model.launch();
      expect(model.qmplusEnabled).assertFalse(); expect(model.hasSavedPassword).assertFalse();
      expect(model.schedule === schedules.cached).assertTrue(); expect(model.statusMessage).assertEqual('数据暂时无法读取。');
      credentials.fail = true;
      const secureFailure: AppModel = testModel(preferences, undefined, schedules, credentials);
      await secureFailure.launch();
      expect(secureFailure.qmplusEnabled).assertFalse(); expect(secureFailure.hasSavedPassword).assertFalse();
      expect(secureFailure.schedule === schedules.cached).assertTrue();
      expect(secureFailure.statusMessage).assertEqual('synthetic secure store failure');
    });
    it('a_late_cache_read_after_runtime_replacement_cannot_publish_or_mark_ready', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('launch-late-cache');
      const schedules: LaunchSchedules = new LaunchSchedules();
      const gate: LaunchGate = new LaunchGate(); schedules.gate = gate;
      const model: AppModel = testModel(preferences, undefined, schedules);
      const loading: Promise<void> = model.launch(); await schedules.started.promise;
      model.enterReviewDemo(); const sample: ScheduleSnapshot | null = model.schedule;
      gate.release(); await loading;
      expect(model.schedule === sample).assertTrue(); expect(model.localHydrationReady).assertFalse();
    });
    it('edits_before_launch_credentials_begin_are_not_overwritten_by_restore', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('launch-before-asset-edit');
      const credentials: DraftCredentials = new DraftCredentials();
      const termGate: LaunchGate = new LaunchGate(); preferences.termGate = termGate;
      const model: AppModel = draftModel(preferences, credentials);
      const loading: Promise<void> = model.launch(); await preferences.termStarted.promise;
      model.editAccount('synthetic-account-b'); model.editPassword('synthetic-draft-b');
      model.editCloudPassword('synthetic-cloud-b');
      termGate.release(); await loading;
      expect(model.account).assertEqual('synthetic-account-b');
      expect(model.password).assertEqual('synthetic-draft-b'); expect(model.cloudPassword).assertEqual('synthetic-cloud-b');
      // Other data owners may read the synthetic record; the UI restore must
      // not overwrite edits or turn them into an unsolicited secure-store save.
      expect(credentials.saves).assertEqual(0); expect(credentials.value?.account).assertEqual('synthetic-account-a');
    });
    it('startup_asset_read_then_same_account_edit_and_save_keeps_the_submitted_secrets', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('launch-draft-save');
      const credentials: DraftCredentials = new DraftCredentials();
      const first: LaunchGate = new LaunchGate(); const second: LaunchGate = new LaunchGate();
      credentials.firstGate = first; credentials.secondGate = second;
      const model: AppModel = draftModel(preferences, credentials);
      const loading: Promise<void> = model.launch(); await credentials.firstStarted.promise;
      model.editAccount('synthetic-account-a'); model.editPassword('synthetic-submitted');
      model.editCloudPassword('synthetic-cloud-submitted');
      const saving: Promise<boolean> = model.saveSettings();
      first.release(); await credentials.secondStarted.promise; await loading;
      expect(model.password).assertEqual('synthetic-submitted');
      expect(model.cloudPassword).assertEqual('synthetic-cloud-submitted');
      second.release(); expect(await saving).assertTrue();
      expect(credentials.value?.account).assertEqual('synthetic-account-a');
      expect(credentials.value?.password).assertEqual('synthetic-submitted');
      expect(credentials.value?.cloudPassword).assertEqual('synthetic-cloud-submitted');
      expect(credentials.saves).assertEqual(1); expect(model.password).assertEqual('');
      expect(model.cloudPassword).assertEqual(''); expect(model.isSavingAccountSettings).assertFalse();
    });
    it('save_owns_submitted_input_and_preserves_newer_account_and_password_drafts', 0, async () => {
      const preferences: LaunchPreferences = new LaunchPreferences('save-fixed-input');
      const credentials: DraftCredentials = new DraftCredentials();
      const gate: LaunchGate = new LaunchGate(); credentials.firstGate = gate;
      const model: AppModel = draftModel(preferences, credentials);
      model.editAccount('synthetic-account-a'); model.editPassword('synthetic-submitted-a');
      model.editCloudPassword('synthetic-cloud-submitted-a');
      const saving: Promise<boolean> = model.saveSettings(); await credentials.firstStarted.promise;
      model.editAccount('synthetic-account-b'); model.editPassword('synthetic-new-draft-b');
      model.editCloudPassword('synthetic-new-cloud-b');
      gate.release(); expect(await saving).assertTrue();
      expect(credentials.value?.account).assertEqual('synthetic-account-a');
      expect(credentials.value?.password).assertEqual('synthetic-submitted-a');
      expect(credentials.value?.cloudPassword).assertEqual('synthetic-cloud-submitted-a');
      expect(model.account).assertEqual('synthetic-account-b'); expect(model.password).assertEqual('synthetic-new-draft-b');
      expect(model.cloudPassword).assertEqual('synthetic-new-cloud-b'); expect(model.canPreserveSavedPassword()).assertFalse();
      expect(model.isRefreshingSchedule).assertFalse();
    });
    it('concurrent_save_does_not_enqueue_a_second_credential_transaction', 0, async () => {
      const credentials: DraftCredentials = new DraftCredentials();
      const gate: LaunchGate = new LaunchGate(); credentials.firstGate = gate;
      const model: AppModel = draftModel(new LaunchPreferences('save-single-flight'), credentials);
      model.editAccount('synthetic-account-a'); model.editPassword('synthetic-submitted-a');
      const saving: Promise<boolean> = model.saveSettings(); await credentials.firstStarted.promise;
      expect(await model.saveSettings()).assertFalse(); expect(credentials.loads).assertEqual(1);
      gate.release(); expect(await saving).assertTrue(); expect(credentials.saves).assertEqual(1);
    });
    it('entering_demo_retires_a_queued_save_without_republishing_real_identity', 0, async () => {
      const credentials: DraftCredentials = new DraftCredentials();
      const gate: LaunchGate = new LaunchGate(); credentials.firstGate = gate;
      const model: AppModel = draftModel(new LaunchPreferences('save-demo-retired'), credentials);
      model.editAccount('synthetic-account-a'); model.editPassword('synthetic-submitted-a');
      const saving: Promise<boolean> = model.saveSettings(); await credentials.firstStarted.promise;
      model.enterReviewDemo(); const message: string = model.statusMessage;
      gate.release(); expect(await saving).assertFalse();
      expect(model.isSampleMode()).assertTrue(); expect(model.account).assertEqual('');
      expect(model.password).assertEqual(''); expect(model.statusMessage).assertEqual(message);
      expect(credentials.saves).assertEqual(0); expect(model.hasSavedPassword).assertFalse();
    });
    it('clear_retires_a_queued_save_before_any_secret_can_be_written', 0, async () => {
      const credentials: DraftCredentials = new DraftCredentials();
      const gate: LaunchGate = new LaunchGate(); credentials.firstGate = gate;
      const model: AppModel = draftModel(new LaunchPreferences('save-clear-retired'), credentials);
      model.editAccount('synthetic-account-a'); model.editPassword('synthetic-submitted-a');
      const saving: Promise<boolean> = model.saveSettings(); await credentials.firstStarted.promise;
      const clearing: Promise<void> = model.clearLocalData();
      gate.release(); expect(await saving).assertFalse(); await clearing.catch((): void => {});
      expect(credentials.saves).assertEqual(0); expect(credentials.value).assertNull();
      expect(model.account).assertEqual(''); expect(model.password).assertEqual('');
    });
    it('clear_drains_a_started_secure_write_before_deleting_it_and_rejects_late_publication', 0, async () => {
      const credentials: DraftCredentials = new DraftCredentials();
      const gate: LaunchGate = new LaunchGate(); credentials.saveGate = gate;
      const model: AppModel = draftModel(new LaunchPreferences('save-clear-drain'), credentials);
      model.editAccount('synthetic-account-a'); model.editPassword('synthetic-submitted-a');
      const saving: Promise<boolean> = model.saveSettings(); await credentials.saveStarted.promise;
      const clearing: Promise<void> = model.clearLocalData(); expect(credentials.clears).assertEqual(0);
      gate.release(); expect(await saving).assertFalse(); await clearing.catch((): void => {});
      expect(credentials.saves).assertEqual(1); expect(credentials.clears).assertEqual(1);
      expect(credentials.value).assertNull(); expect(model.account).assertEqual('');
      expect(model.hasSavedPassword).assertFalse(); expect(model.isSavingAccountSettings).assertFalse();
    });
  });
}
