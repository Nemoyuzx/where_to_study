// 全合成存储：不初始化 AppContext、不读取任何真实登录资料、不启动 ArkWeb。
import { describe, it, expect } from '@ohos/hypium';
import { QMPlusSavedLogin, QMPlusSavedLoginStoring } from '../main/ets/store/QMPlusSavedLoginStore';
import { QMPlusAuthAttemptLedger, QMPlusAuthNavigationPolicy,
  QMPlusAuthTransitionState } from '../main/ets/view/QMPlusConnectionView';
import { QMPlusAuthorizationJournal, QMPlusLoginAuthorization, QMPlusSession } from '../main/ets/view/QMPlusSession';
import { QMPlusSnapshot, QMPlusURLPolicy } from '../main/ets/net/QMPlusSnapshot';
import { QMPlusWebProfileStoring } from '../main/ets/store/QMPlusWebProfileStore';
import { CourseDTOCacheStore } from '../main/ets/store/CourseDTOCacheStore';

class Gate {
  private finish: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.finish = resolve; });
  release(): void { this.finish(); }
}

class FakeLoginStore implements QMPlusSavedLoginStoring {
  login: QMPlusSavedLogin | null = null;
  loadCount: number = 0;
  saveCount: number = 0;
  clearCount: number = 0;
  failClear: boolean = false;
  saveGate: Gate | null = null;
  loadGate: Gate | null = null;
  readonly saveStarted: Gate = new Gate();
  loadStarted: Gate = new Gate();

  async load(): Promise<QMPlusSavedLogin | null> {
    this.loadCount++;
    const captured: QMPlusSavedLogin | null = this.login;
    const gate: Gate | null = this.loadGate;
    this.loadGate = null;
    if (gate !== null) { this.loadStarted.release(); await gate.promise; }
    return captured;
  }
  async save(login: QMPlusSavedLogin): Promise<void> {
    this.saveCount++;
    this.saveStarted.release();
    if (this.saveGate !== null) { await this.saveGate.promise; }
    this.login = login;
  }
  async clear(): Promise<void> {
    this.clearCount++;
    if (this.failClear) { throw new Error('synthetic asset removal failed'); }
    this.login = null;
  }
}

class FakeAuthorizationJournal implements QMPlusAuthorizationJournal {
  value: string | null = null;
  failRemove: boolean = false;
  failSet: boolean = false;
  async getString(key: string): Promise<string | null> { return this.value; }
  async setString(key: string, value: string): Promise<void> {
    if (this.failSet) { throw new Error('synthetic preference write failed'); }
    this.value = value;
  }
  async remove(key: string): Promise<void> {
    if (this.failRemove) { throw new Error('synthetic preference removal failed'); }
    this.value = null;
  }
}

class RetainedWebProfile implements QMPlusWebProfileStoring {
  ready: boolean = true;
  reserves: number = 0;
  clears: number = 0;
  lifecycleFlushes: number = 0;
  reserveWebMount(): boolean { this.reserves++; return this.ready; }
  noteWebLoaded(): void {}
  isReady(): boolean { return this.ready; }
  requiresRestart(): boolean { return !this.ready; }
  markClearPending(): boolean { this.ready = false; return true; }
  hasDurableClearPending(): boolean { return !this.ready; }
  async prepare(): Promise<boolean> { return this.ready; }
  async clear(): Promise<boolean> { this.clears++; this.ready = true; return true; }
  async flush(): Promise<boolean> { return this.ready; }
  flushOnLifecycle(): boolean {
    if (!this.ready) { return false; }
    this.lifecycleFlushes++; return true;
  }
}

class CacheWebProfile extends RetainedWebProfile {
  scope: string = 'a'.repeat(32);
  businessScope(): string { return this.scope; }
}

class FakeQMCache extends CourseDTOCacheStore {
  loads: number = 0;
  failNextLoad: boolean = false;
  gate: Gate | null = null;
  started: Gate = new Gate();
  value: QMPlusSnapshot = new QMPlusSnapshot('2026-10-05T00:00:00Z', false, [], [], []);
  constructor() { super('qmplus'); }
  async loadQM(scope: string): Promise<QMPlusSnapshot | null> {
    this.loads++;
    const gate: Gate | null = this.gate;
    this.gate = null;
    this.started.release();
    if (gate !== null) { await gate.promise; }
    if (this.failNextLoad) { this.failNextLoad = false; throw new Error('synthetic cache read failed'); }
    return this.value;
  }
  async clear(): Promise<void> {}
}

function session(store: FakeLoginStore, journal: FakeAuthorizationJournal): QMPlusSession {
  let sequence: number = 0;
  // Host-side Hypium on Darwin cannot call device CryptoFramework RNG. Every
  // synthetic run injects a distinct, valid 128-bit-shaped record ID; production
  // keeps newQMPlusRecordID() as the default and must fail closed on RNG errors.
  return new QMPlusSession((): void => {}, store, journal, (): string => {
    sequence++;
    return sequence.toString(16).padStart(32, '0');
  });
}

async function authorization(current: QMPlusSession): Promise<QMPlusLoginAuthorization> {
  const ticket: QMPlusLoginAuthorization | null = await current.captureLoginAuthorization(current.loginOwner());
  if (ticket === null) { throw new Error('Synthetic authorization was not captured.'); }
  return ticket;
}

export default function qmPlusSavedLoginTest() {
  describe('QMPlusSavedLoginTest', () => {
    it('simultaneous_status_restores_share_one_asset_read_and_retired_reads_cannot_reauthorize', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      store.login = new QMPlusSavedLogin('a'.repeat(32), 'student@example.org', 'synthetic-pass');
      journal.value = store.login.recordID;
      const gate: Gate = new Gate(); store.loadGate = gate;
      const current: QMPlusSession = session(store, journal);
      const first: Promise<void> = current.restoreSavedLoginStatus();
      const second: Promise<void> = current.restoreSavedLoginStatus();
      await store.loadStarted.promise;
      expect(store.loadCount).assertEqual(1);
      await current.deleteSavedLogin();
      gate.release(); await first; await second;
      expect(current.savedLoginAvailable).assertFalse();
      expect(current.autoFillEnabled).assertFalse();
      current.dispose();
    });
    it('cache_restore_is_single_flight_and_term_rejection_or_failure_can_retry', 0, async () => {
      const cache: FakeQMCache = new FakeQMCache();
      const profile: CacheWebProfile = new CacheWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, new FakeLoginStore(),
        new FakeAuthorizationJournal(), (): string => 'b'.repeat(32), profile, cache);
      current.termID = '2025-2026-2';
      const gate: Gate = new Gate(); cache.gate = gate;
      const first: Promise<void> = current.restoreBusinessCache();
      const second: Promise<void> = current.restoreBusinessCache();
      await cache.started.promise;
      expect(cache.loads).assertEqual(1);
      current.termID = '2026-2027-1';
      gate.release(); await first; await second;
      expect(current.snapshot === cache.value).assertTrue();
      expect(cache.loads).assertEqual(2);
      current.snapshot = null;
      cache.failNextLoad = true;
      let failed: boolean = false;
      await current.restoreBusinessCache().catch(() => { failed = true; });
      expect(failed).assertTrue();
      await current.restoreBusinessCache();
      expect(current.snapshot === cache.value).assertTrue();
      expect(cache.loads).assertEqual(4);
      current.dispose();
    });
    it('scope_change_and_disposal_retire_old_cache_callbacks', 0, async () => {
      const cache: FakeQMCache = new FakeQMCache();
      const profile: CacheWebProfile = new CacheWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, new FakeLoginStore(),
        new FakeAuthorizationJournal(), (): string => 'b'.repeat(32), profile, cache);
      const gate: Gate = new Gate(); cache.gate = gate;
      const old: Promise<void> = current.restoreBusinessCache();
      await cache.started.promise;
      profile.scope = 'c'.repeat(32);
      current.dispose(); gate.release(); await old;
      expect(current.snapshot).assertNull();
    });
    it('disabled_warm_start_does_no_asset_work_and_concurrent_warm_calls_cannot_reopen_after_off', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const cache: FakeQMCache = new FakeQMCache();
      const profile: CacheWebProfile = new CacheWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, store,
        new FakeAuthorizationJournal(), (): string => 'b'.repeat(32), profile, cache);
      current.termID = '2026-2027-1';
      current.setFeatureEnabled(false); await current.startWarmRefresh();
      expect(store.loadCount).assertEqual(0); expect(cache.loads).assertEqual(0);
      current.setFeatureEnabled(true);
      const gate: Gate = new Gate(); store.loadGate = gate;
      const first: Promise<void> = current.startWarmRefresh();
      const second: Promise<void> = current.startWarmRefresh();
      await store.loadStarted.promise;
      expect(store.loadCount).assertEqual(1);
      current.setFeatureEnabled(false);
      gate.release(); await first; await second;
      expect(current.loginVisible).assertFalse(); expect(profile.reserves).assertEqual(0);
      current.setFeatureEnabled(true); await current.startWarmRefresh();
      expect(profile.reserves).assertEqual(1); expect(store.loadCount).assertEqual(1);
      current.dispose();
    });
    it('a_new_term_retires_the_old_warm_owner_and_can_start_again_without_requerying_saved_status', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const cache: FakeQMCache = new FakeQMCache();
      const profile: CacheWebProfile = new CacheWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, store,
        new FakeAuthorizationJournal(), (): string => 'b'.repeat(32), profile, cache);
      current.updateTermID('2025-2026-2'); await current.startWarmRefresh();
      const old = current.loginOwner();
      expect(current.loginVisible).assertTrue(); expect(profile.reserves).assertEqual(1);
      current.updateTermID('2026-2027-1');
      expect(current.isLoginOwnerCurrent(old)).assertFalse();
      await current.startWarmRefresh();
      expect(profile.reserves).assertEqual(2); expect(store.loadCount).assertEqual(1);
      expect(current.termID).assertEqual('2026-2027-1');
      current.dispose();
    });
    it('the_first_chooser_wait_is_bounded_and_a_later_exact_match_keeps_its_single_claim', 0, () => {
      const ready: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ready.begin(); ready.beginDocument('document_1');
      for (let attempt: number = 0; attempt < 3; attempt++) {
        expect(ready.canWaitForInitialAccountChoice(attempt)).assertTrue();
        expect(ready.claimAccount('document_1', false)).assertFalse();
        expect(ready.passwordAttempted()).assertFalse();
      }
      expect(ready.claimAccount('document_1', true)).assertTrue();
      expect(ready.canWaitForInitialAccountChoice(3)).assertFalse();
      expect(ready.recordAccountSelection('document_1', 'ACCOUNT_SELECTED')).assertTrue();
      expect(ready.claimAccount('document_1', true)).assertFalse();
      const unmatched: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      unmatched.begin(); unmatched.beginDocument('document_2');
      for (let attempt: number = 0; attempt < 8; attempt++) {
        expect(unmatched.canWaitForInitialAccountChoice(attempt)).assertTrue();
        expect(unmatched.claimAccount('document_2', false)).assertFalse();
      }
      expect(unmatched.canWaitForInitialAccountChoice(8)).assertFalse();
      expect(unmatched.claimPassword('document_2', true)).assertFalse();
      unmatched.stop();
      expect(unmatched.canWaitForInitialAccountChoice(0)).assertFalse();
    });
    it('page_not_ready_retains_session_profile_and_last_good_snapshot_for_a_normal_retry', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const profile: RetainedWebProfile = new RetainedWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, store,
        new FakeAuthorizationJournal(), (): string => 'a'.repeat(32), profile);
      const cached: QMPlusSnapshot = new QMPlusSnapshot('2026-10-05T00:00:00Z', false, [], [], []);
      current.snapshot = cached;
      current.openLogin();
      expect(await current.prepareOfficialWeb(current.loginOwner())).assertTrue();
      current.completeSync(current.beginSync(), '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-05T00:00:00Z","ok":false,"partial":false,"courses":[],"activities":[],"warnings":[],"error_code":"QM_PAGE_NOT_READY"}');
      expect(current.errorCode).assertEqual('QM_PAGE_NOT_READY');
      expect(current.manualContinuationRequired).assertFalse();
      expect(current.loginVisible).assertFalse();
      expect(current.snapshot === cached).assertTrue();
      expect(profile.clears).assertEqual(0);
      expect(store.clearCount).assertEqual(0);
      expect(profile.lifecycleFlushes).assertEqual(1);
      current.openLogin();
      expect(await current.prepareOfficialWeb(current.loginOwner())).assertTrue();
      expect(profile.clears).assertEqual(0);
      current.closeLogin();
    });
    it('background_close_and_reopen_flush_and_reuse_the_same_profile_without_clearing', 0, async () => {
      const profile: RetainedWebProfile = new RetainedWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, new FakeLoginStore(),
        new FakeAuthorizationJournal(), (): string => 'a'.repeat(32), profile);
      current.openLogin();
      const owner = current.loginOwner();
      expect(await current.prepareOfficialWeb(owner)).assertTrue();
      current.setLoginForeground(false);
      expect(profile.lifecycleFlushes).assertEqual(1);
      current.setLoginForeground(true);
      current.closeLogin();
      expect(profile.lifecycleFlushes).assertEqual(2);
      expect(profile.clears).assertEqual(0);
      current.openLogin();
      expect(await current.prepareOfficialWeb(current.loginOwner())).assertTrue();
      expect(profile.reserves).assertEqual(2);
      expect(profile.clears).assertEqual(0);
      expect(current.isLoginOwnerCurrent(owner)).assertFalse();
      profile.markClearPending();
      current.persistOfficialWebSession();
      expect(profile.lifecycleFlushes).assertEqual(2);
      current.dispose();
    });

    it('identical_saved_credentials_with_autofill_off_preserve_profile_record_and_authorization_choice', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const saved: QMPlusSavedLogin = new QMPlusSavedLogin('a'.repeat(32), 'student@example.org', 'synthetic-pass');
      store.login = saved;
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const profile: RetainedWebProfile = new RetainedWebProfile();
      const current: QMPlusSession = new QMPlusSession((): void => {}, store, journal, (): string => 'b'.repeat(32), profile);
      await current.restoreSavedLoginStatus();
      expect(current.autoFillEnabled).assertFalse();
      current.openLogin();
      const owner = current.loginOwner();
      expect(await current.prepareOfficialWeb(owner)).assertTrue();
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(store.login === saved).assertTrue();
      expect(store.saveCount).assertEqual(0);
      expect(profile.clears).assertEqual(0);
      expect(current.autoFillEnabled).assertFalse();
      expect(journal.value).assertNull();
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      current.dispose();
    });
    it('passive_microsoft_transport_paths_never_become_injectable', 0, () => {
      for (const host of ['login.microsoftonline.com', 'device.login.microsoftonline.com']) {
        const url: string = 'https://' + host + '/common/intermediate';
        expect(QMPlusAuthNavigationPolicy.isMicrosoftTransitPage(url)).assertTrue();
        expect(QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url)).assertFalse();
        expect(QMPlusAuthNavigationPolicy.isVerificationPage(url)).assertFalse();
        for (const other of [url.replace('https:', 'http:'), url.replace('.com/', '.com.evil.invalid/'),
          url.replace('https://', 'https://user@'), url.replace('https://', 'https://evil.'),
          url.replace('.com/', '.com:444/')]) {
          expect(QMPlusAuthNavigationPolicy.isMicrosoftTransitPage(other)).assertFalse();
        }
      }
    });
    it('device_auth_reprocess_is_readonly_verification_not_a_credential_or_kmsi_path', 0, () => {
      const url: string = 'https://login.microsoftonline.com/common/DeviceAuthTls/reprocess';
      expect(QMPlusAuthNavigationPolicy.isVerificationPage(url)).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isVerificationPage(url.toLowerCase())).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url)).assertFalse();
      for (const other of [url + '/', url + '/extra', url + '#fragment', url.replace('https:', 'http:'),
        url.replace('login.microsoftonline.com', 'user@login.microsoftonline.com'),
        url.replace('login.microsoftonline.com', 'login.microsoftonline.com.evil.invalid'),
        url.replace('DeviceAuthTls', '%44eviceAuthTls'), url.replace('reprocess', 'login')]) {
        expect(QMPlusAuthNavigationPolicy.isVerificationPage(other)).assertFalse();
      }
    });
    it('a_foreground_warm_owner_reveals_only_verification_then_returns_to_quiet_work', 0, () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      current.openLogin(QMPlusURLPolicy.home, true);
      const owner = current.loginOwner();
      current.setLoginForeground(false);
      current.presentVerification();
      expect(current.loginPresented).assertFalse();
      current.setLoginForeground(true);
      current.presentVerification();
      expect(current.loginPresented).assertTrue();
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      current.resumeAutomaticLogin();
      expect(current.loginPresented).assertFalse();
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      current.closeLogin();
    });

    it('unknown_page_deferral_preserves_the_document_for_explicit_manual_continuation_and_later_teardown', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const owner = current.loginOwner();
      let stops: number = 0;
      current.bindLoginWeb(owner, (): void => { stops++; });
      current.deferManualLogin();
      expect(current.loginPresented).assertFalse();
      expect(current.manualContinuationRequired).assertTrue();
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      expect(stops).assertEqual(1);
      current.openLogin();
      expect(current.loginPresented).assertTrue();
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      current.presentVerification();
      current.resumeAutomaticLogin();
      expect(current.loginPresented).assertTrue();
      current.closeLogin();
      expect(stops).assertEqual(2);
    });

    it('silent_owner_manual_requirement_preserves_last_good_and_retires_without_presenting_a_window', 0, () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      const cached: QMPlusSnapshot = new QMPlusSnapshot('2026-10-05T00:00:00Z', false, [], [], []);
      current.snapshot = cached;
      current.openLogin(QMPlusURLPolicy.home, true);
      const owner = current.loginOwner();
      let stops: number = 0;
      current.bindLoginWeb(owner, (): void => { stops++; });
      const generation: number = current.beginSync();
      current.presentLogin();
      expect(current.loginVisible).assertFalse();
      expect(current.loginPresented).assertFalse();
      expect(current.snapshot === cached).assertTrue();
      expect(current.errorCode).assertEqual('QM_LOGIN_REQUIRED');
      expect(current.isCurrent(generation)).assertFalse();
      expect(stops).assertEqual(1);
      expect(store.clearCount).assertEqual(0);
      current.openLogin();
      expect(current.targetURL).assertEqual(QMPlusURLPolicy.home);
      expect(current.isLoginOwnerCurrent(owner)).assertFalse();
      current.closeLogin();
    });

    it('explicit_connect_upgrades_an_ongoing_quiet_owner_without_revealing_or_replacing_its_document', 0, () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      current.openLogin(QMPlusURLPolicy.home, true);
      const owner = current.loginOwner();
      let stops: number = 0;
      current.bindLoginWeb(owner, (): void => { stops++; });
      current.openLogin();
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      expect(current.loginPresented).assertFalse();
      expect(stops).assertEqual(0);
      current.presentLogin();
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertTrue();
      current.closeLogin();
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(QMPlusURLPolicy.home, QMPlusURLPolicy.home, true, true, false)).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isQMGuestEntry('https://qmplus.qmul.ac.uk/my/?wants=other')).assertFalse();
    });

    it('official_error_waits_for_manual_continue_before_explicit_restart_without_deleting_saved_state', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      const saved: QMPlusSavedLogin | null = store.login;
      let stops: number = 0;
      let restarts: number = 0;
      current.bindLoginWeb(ticket.owner, (): void => { stops++; }, (): void => { restarts++; });
      const generation: number = current.beginSync();
      current.noteOfficialPageError(ticket.owner);
      expect(current.errorCode).assertEqual('QM_ERROR_PAGE');
      expect(current.loginPresented).assertFalse();
      expect(current.manualContinuationRequired).assertTrue();
      expect(current.isCurrent(generation)).assertFalse();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
      expect(stops).assertEqual(1);
      expect(restarts).assertEqual(0);
      expect(current.loginPresented).assertTrue();
      expect(current.isLoginOwnerCurrent(ticket.owner)).assertTrue();
      current.openLogin();
      expect(stops).assertEqual(2);
      expect(restarts).assertEqual(1);
      expect(current.targetURL).assertEqual('https://qmplus.qmul.ac.uk/my/');
      expect(current.isAuthorizationCurrent(ticket)).assertFalse();
      expect(current.errorCode).assertEqual('');
      expect(current.explicitDetailRequest).assertFalse();
      expect(store.login === saved).assertTrue();
      expect(store.clearCount).assertEqual(0);
      current.noteOfficialPageError(ticket.owner);
      expect(current.errorCode).assertEqual('');
      current.dispose();
    });

    it('opening_while_the_official_callback_is_loading_does_not_reload_or_retire_owner', 0, () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      current.openLogin();
      const owner = current.loginOwner();
      let stops: number = 0;
      let restarts: number = 0;
      current.bindLoginWeb(owner, (): void => { stops++; }, (): void => { restarts++; });
      current.noteOfficialPageError(owner);
      current.noteOfficialPageLoading(owner, true);
      current.openLogin();
      expect(stops).assertEqual(1); // Error already suspended automation before this loading callback.
      expect(restarts).assertEqual(0);
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      expect(current.loginPresented).assertTrue();
      current.noteOfficialPageLoading(owner, false);
      current.openLogin();
      expect(stops).assertEqual(2);
      expect(restarts).assertEqual(1);
      current.dispose();
    });

    it('guest_entry_policy_is_exact_and_sso_is_not_restarted_after_credentials', 0, () => {
      expect(QMPlusAuthNavigationPolicy.isQMLoginLanding('https://qmplus.qmul.ac.uk/')).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isQMLoginLanding('https://qmplus.qmul.ac.uk/?redirect=0')).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isQMLoginLanding('https://qmplus.qmul.ac.uk/login/index.php')).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isQMLoginLanding('https://qmplus.qmul.ac.uk/login/index.php?next=x')).assertFalse();
      expect(QMPlusAuthNavigationPolicy.isQMLoginLanding('https://qmplus.qmul.ac.uk/?redirect=0&next=x')).assertFalse();
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.credentialsAttempted()).assertFalse();
      expect(ledger.claimUsername('document_1')).assertTrue();
      ledger.beginDocument();
      expect(ledger.credentialsAttempted()).assertTrue();
    });
    it('explicit_official_activity_opens_visibly_and_is_not_closed_as_a_background_connection', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/assign/view.php?id=1');
      expect(current.explicitDetailRequest).assertTrue();
      expect(current.loginPresented).assertTrue();
      const generation: number = current.beginSync();
      current.completeSync(generation, '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-04T00:00:00.000Z","ok":true,"partial":false,"courses":[],"activities":[],"warnings":[]}');
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertTrue();
      expect(current.targetURL).assertEqual('https://qmplus.qmul.ac.uk/mod/assign/view.php?id=1');
      current.dispose();
    });
    it('authorized_quiet_owner_stays_quiet_until_verified_challenge_and_cancels_on_background', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertFalse();
      current.cancelQuietLoginOnBackground();
      expect(current.loginVisible).assertFalse();
      current.setLoginForeground(true);
      current.openLogin();
      const generation: number = current.beginSync();
      current.openLogin();
      expect(current.loginPresented).assertFalse();
      current.presentVerification();
      expect(current.loginPresented).assertTrue();
      expect(current.isCurrent(generation)).assertTrue();
      current.cancelQuietLoginOnBackground();
      expect(current.loginVisible).assertTrue(); // Never interrupts a visible MFA window.
      current.dispose();
    });

    it('without_explicit_autofill_authorization_the_official_window_is_visible', 0, () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      current.openLogin();
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertTrue();
      current.dispose();
    });

    it('visible_official_owner_survives_background_but_old_secret_and_capture_tickets_do_not_revive', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/assign/view.php?id=1');
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      const hold: Gate = new Gate();
      store.loadGate = hold;
      const password: Promise<string | null> = current.authorizedPasswordFor('student@example.org', ticket);
      await store.loadStarted.promise;
      current.cancelQuietLoginOnBackground();
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertTrue();
      expect(current.isLoginOwnerCurrent(ticket.owner)).assertTrue();
      expect(current.isAuthorizationCurrent(ticket)).assertFalse();
      expect(await current.captureLoginAuthorization(ticket.owner)).assertNull();
      current.setLoginForeground(true);
      hold.release();
      expect(await password).assertNull();
      expect(current.isAuthorizationCurrent(ticket)).assertFalse();
      const fresh: QMPlusLoginAuthorization = await authorization(current);
      expect(fresh.foregroundRevision === ticket.foregroundRevision).assertFalse();
      expect(await current.authorizedPasswordFor('student@example.org', fresh)).assertEqual('synthetic-pass');

      const captureHold: Gate = new Gate();
      store.loadStarted = new Gate();
      store.loadGate = captureHold;
      const capture: Promise<QMPlusLoginAuthorization | null> = current.captureLoginAuthorization(current.loginOwner());
      await store.loadStarted.promise;
      current.cancelQuietLoginOnBackground();
      current.setLoginForeground(true);
      captureHold.release();
      expect(await capture).assertNull();
      current.dispose();
    });

    it('foreground_reauthorization_preserves_the_same_document_ack_and_once_only_submission_claims', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
      const old: QMPlusLoginAuthorization = await authorization(current);
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.claimUsername('document_1')).assertTrue();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
      current.cancelQuietLoginOnBackground();
      current.setLoginForeground(true);
      expect(current.isAuthorizationCurrent(old)).assertFalse();
      expect(current.isAuthorizationCurrent(await authorization(current))).assertTrue();
      expect(ledger.isActive()).assertTrue();
      expect(ledger.usernameSubmitted('document_1')).assertTrue();
      expect(ledger.claimUsername('document_1')).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertTrue();
      current.cancelQuietLoginOnBackground();
      current.setLoginForeground(true);
      expect(ledger.passwordAttempted()).assertTrue();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      current.dispose();
    });

    it('same_document_resume_routes_username_ack_form_and_absent_to_bounded_wait_then_one_matched_password', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
      const old: QMPlusLoginAuthorization = await authorization(current);
      let now: number = 1000;
      const clock: () => number = (): number => now;
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger(clock);
      ledger.begin(); ledger.beginDocument('document_1');
      const firstRun: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', clock);
      expect(ledger.claimUsername('document_1')).assertTrue();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
      firstRun.restoreUsernameBudget();
      current.cancelQuietLoginOnBackground(); now = 1350; current.setLoginForeground(true);
      expect(current.isAuthorizationCurrent(old)).assertFalse();
      const fresh: QMPlusLoginAuthorization = await authorization(current);
      expect(current.isAuthorizationCurrent(fresh)).assertTrue();
      // This is the settling state used by production runAuth, reconstructed
      // with the same ledger/nonce after foreground authorization is renewed.
      const resumed: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', clock);
      const reads: number = store.loadCount;
      expect(resumed.canWait('FORM_UNTRUSTED', ledger.usernameSubmitted('document_1'))).assertTrue();
      now = 1850;
      expect(resumed.canWait('KNOWN_FORM_ABSENT', ledger.usernameSubmitted('document_1'))).assertTrue();
      expect(store.loadCount).assertEqual(reads); expect(ledger.passwordAttempted()).assertFalse();
      expect(ledger.claimPassword('document_1', false)).assertFalse();
      expect(store.loadCount).assertEqual(reads);
      expect(await current.authorizedPasswordFor('student@example.org', fresh)).assertEqual('synthetic-pass');
      expect(ledger.claimPassword('document_1', true)).assertTrue();
      expect(ledger.claimUsername('document_1')).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      current.dispose();
    });

    it('same_document_mfa_is_presented_immediately_and_never_waits_or_reads_password', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
      let now: number = 1000;
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger((): number => now);
      ledger.begin(); ledger.beginDocument('document_1'); ledger.claimUsername('document_1');
      ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED');
      current.cancelQuietLoginOnBackground(); now = 1400; current.setLoginForeground(true);
      const resumed: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', (): number => now);
      const reads: number = store.loadCount;
      for (const reason of ['MFA_REQUIRED', 'CAPTCHA_REQUIRED']) {
        expect(resumed.canWait(reason, true)).assertFalse();
        current.presentVerification();
        expect(current.loginPresented).assertTrue(); expect(current.loginVisible).assertTrue();
      }
      expect(store.loadCount).assertEqual(reads); expect(ledger.passwordAttempted()).assertFalse();
      current.dispose();
    });

    it('resuming_or_replaying_username_ack_never_renews_the_original_settling_deadline', 0, () => {
      let now: number = 1000;
      const clock: () => number = (): number => now;
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger(clock);
      ledger.begin(); ledger.beginDocument('document_1'); ledger.claimUsername('document_1');
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
      expect(ledger.usernameTransitionDeadline('document_1')).assertEqual(3000);
      for (const time of [1500, 2500, 2999]) {
        now = time;
        expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
        const resumed: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', clock);
        expect(resumed.canWait('FORM_UNTRUSTED', true)).assertTrue();
        expect(ledger.usernameTransitionDeadline('document_1')).assertEqual(3000);
      }
      now = 3000;
      const expired: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', clock);
      for (const reason of ['FORM_UNTRUSTED', 'KNOWN_FORM_ABSENT', 'ALREADY_ATTEMPTED']) {
        expect(expired.canWait(reason, true)).assertFalse();
      }
      expect(ledger.claimUsername('document_1')).assertFalse(); expect(ledger.passwordAttempted()).assertFalse();
    });

    it('username_settling_rejects_risk_reasons_new_documents_stopped_owners_and_wrong_ack', 0, () => {
      let now: number = 1000;
      const clock: () => number = (): number => now;
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger(clock);
      ledger.begin(); ledger.beginDocument('document_1'); ledger.claimUsername('document_1');
      expect(ledger.recordUsernameSubmission('document_1', 'REJECTED')).assertFalse();
      const unacknowledged: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', clock);
      expect(unacknowledged.canWait('FORM_UNTRUSTED', true)).assertFalse();
      ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED');
      const acknowledged: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_1', clock);
      for (const reason of ['INTERFERENCE', 'ACCOUNT_MISMATCH', 'UNSUPPORTED_PAGE', 'UNTRUSTED_CONTEXT', 'STALE_DOCUMENT']) {
        expect(acknowledged.canWait(reason, true)).assertFalse();
      }
      expect(acknowledged.canWait('FORM_UNTRUSTED', false)).assertFalse();
      ledger.beginDocument('document_2');
      expect(acknowledged.canWait('FORM_UNTRUSTED', true)).assertFalse();
      const navigated: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(ledger, 'document_2', clock);
      expect(navigated.canWait('KNOWN_FORM_ABSENT', true)).assertFalse();
      expect(ledger.claimUsername('document_2')).assertFalse();
      ledger.stop(); now = 1500;
      expect(acknowledged.canWait('FORM_UNTRUSTED', true)).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
    });

    it('resumed_transition_cannot_revive_replaced_credentials_or_a_closed_session_owner', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
      const old: QMPlusLoginAuthorization = await authorization(current);
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger((): number => 1000);
      ledger.begin(); ledger.beginDocument('document_1'); ledger.claimUsername('document_1');
      ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED');
      current.cancelQuietLoginOnBackground(); current.setLoginForeground(true);
      const resumed: QMPlusLoginAuthorization = await authorization(current);
      expect(current.isAuthorizationCurrent(old)).assertFalse();
      expect(await current.saveSavedLogin('new@example.org', 'synthetic-new')).assertTrue();
      expect(current.isAuthorizationCurrent(resumed)).assertFalse();
      expect(await current.authorizedPasswordFor('student@example.org', resumed)).assertNull();
      current.closeLogin();
      expect(current.isLoginOwnerCurrent(resumed.owner)).assertFalse();
      expect(await current.captureLoginAuthorization(resumed.owner)).assertNull();
      current.dispose();
    });

    it('saving_a_new_identity_clears_the_previous_web_owner_snapshot_and_delayed_secret_before_publication', 0, async () => {
      QMPlusSession.resetOwnedWebLoadedForTesting();
      try {
        let clearCalls: number = 0;
        let retireCalls: number = 0;
        let sequence: number = 0;
        const store: FakeLoginStore = new FakeLoginStore();
        const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
        const current: QMPlusSession = new QMPlusSession((): void => {
          expect(retireCalls).assertEqual(1);
          clearCalls++;
        }, store, journal,
          (): string => { sequence++; return sequence.toString(16).padStart(32, '0'); });
        expect(await current.saveSavedLogin('old@example.org', 'old-synthetic')).assertTrue();
        expect(await current.setAutoFillEnabled(true)).assertTrue();
        current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
        current.noteWebLoaded();
        const generation: number = current.beginSync();
        const raw: string = '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-04T00:00:00.000Z","ok":true,"partial":false,"courses":[],"activities":[],"warnings":[]}';
        current.completeSync(generation, raw);
        const ticket: QMPlusLoginAuthorization = await authorization(current);
        current.bindLoginWeb(ticket.owner, (): void => { retireCalls++; });
        const hold: Gate = new Gate();
        store.loadGate = hold;
        const oldPassword: Promise<string | null> = current.authorizedPasswordFor('old@example.org', ticket);
        await store.loadStarted.promise;
        expect(await current.saveSavedLogin('new@example.org', 'new-synthetic')).assertTrue();
        hold.release();
        expect(await oldPassword).assertNull();
        expect(clearCalls).assertEqual(1);
        expect(retireCalls).assertEqual(1);
        expect(current.loginVisible).assertFalse();
        expect(current.snapshot).assertNull();
        expect(current.autoFillEnabled).assertFalse();
        expect(journal.value).assertNull();
        expect(store.login?.account).assertEqual('new@example.org');
        expect(current.isLoginOwnerCurrent(ticket.owner)).assertFalse();
        current.completeSync(generation, raw);
        expect(current.snapshot).assertNull();
        current.dispose();
      } finally { QMPlusSession.resetOwnedWebLoadedForTesting(); }
    });

    it('failed_web_clear_blocks_identity_replacement_and_reconnect_after_root_recreation_until_clear_succeeds', 0, async () => {
      QMPlusSession.resetOwnedWebLoadedForTesting();
      try {
        let failClear: boolean = false;
        let clearCalls: number = 0;
        const clearWeb = (): void => {
          clearCalls++;
          if (failClear) { throw new Error('synthetic incognito clear failed'); }
        };
        const store: FakeLoginStore = new FakeLoginStore();
        const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
        const current: QMPlusSession = new QMPlusSession(clearWeb, store, journal, (): string => 'a'.repeat(32));
        expect(await current.saveSavedLogin('old@example.org', 'old-synthetic')).assertTrue();
        expect(await current.setAutoFillEnabled(true)).assertTrue();
        current.openLogin();
        current.noteWebLoaded();
        failClear = true;
        expect(await current.saveSavedLogin('new@example.org', 'new-synthetic')).assertFalse();
        expect(store.login?.account).assertEqual('old@example.org');
        expect(current.autoFillEnabled).assertFalse();
        expect(journal.value).assertNull();
        expect(current.snapshot).assertNull();
        expect(current.loginSettingsBusy).assertFalse();
        current.openLogin();
        expect(current.loginVisible).assertFalse();
        current.dispose();

        const rebuilt: QMPlusSession = new QMPlusSession(clearWeb, store, journal, (): string => 'b'.repeat(32));
        await rebuilt.restoreSavedLoginStatus();
        expect(rebuilt.autoFillEnabled).assertFalse();
        rebuilt.openLogin();
        expect(rebuilt.loginVisible).assertFalse();
        expect(rebuilt.error).assertEqual('QMplus 浏览器会话未能清除，请稍后重试。');
        // Full settings removal cannot erase the process-owned incognito fence.
        journal.value = null;
        expect(rebuilt.logout()).assertFalse();
        rebuilt.openLogin();
        expect(rebuilt.loginVisible).assertFalse();
        failClear = false;
        rebuilt.openLogin();
        expect(rebuilt.loginVisible).assertTrue();
        expect(clearCalls).assertEqual(6);
        rebuilt.dispose();
      } finally { QMPlusSession.resetOwnedWebLoadedForTesting(); }
    });

    it('validated_empty_business_snapshot_closes_quiet_owner_not_merely_the_login_page', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const generation: number = current.beginSync();
      current.completeSync(generation, '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-04T00:00:00.000Z","ok":true,"partial":false,"courses":[],"activities":[],"warnings":[]}');
      expect(current.snapshot !== null).assertTrue();
      expect(current.loginVisible).assertFalse();
      expect(current.loginPresented).assertFalse();
      current.dispose();
    });

    it('sync_failure_defers_the_same_owner_until_explicit_manual_continue', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      current.failSync(current.beginSync(), 'QMplus 同步已超时，请稍后重试。');
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertFalse();
      expect(current.manualContinuationRequired).assertTrue();
      expect(current.error.length > 0).assertTrue();
      current.openLogin();
      expect(current.loginPresented).assertTrue();
      current.dispose();
    });
    it('only_exact_official_main_document_may_start_saml_once_per_presentation', 0, () => {
      const login: string = QMPlusAuthNavigationPolicy.qmLoginPage;
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(login, login, true, true, false)).assertTrue();
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(login, login, true, false, false)).assertFalse();
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(login, login, true, true, true)).assertFalse();
      const guest: string = QMPlusAuthNavigationPolicy.qmGuestLanding;
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(guest, guest, true, true, false)).assertTrue();
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(guest + '&next=other', guest + '&next=other',
        true, true, false)).assertFalse();
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(login + '?next=evil', login + '?next=evil',
        true, true, false)).assertFalse();
      expect(QMPlusAuthNavigationPolicy.shouldStartSAML(login, 'https://other.test/login',
        true, true, false)).assertFalse();
      expect(QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(
        'https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/saml2')).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(
        'https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login')).assertTrue();
      expect(QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(
        'https://login.microsoftonline.com.evil.test/569df091-b013-40e3-86ee-bd9cb9e25814/login')).assertFalse();
      expect(QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(
        'http://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login')).assertFalse();
    });
    it('secret_record_is_separate_bounded_and_rejects_unexpected_fields', 0, () => {
      const login: QMPlusSavedLogin = new QMPlusSavedLogin('a'.repeat(32), ' student@example.org ', 'synthetic-pass');
      expect(login.account).assertEqual('student@example.org');
      expect(QMPlusSavedLogin.fromJsonText(login.toJsonText()).recordID).assertEqual('a'.repeat(32));
      let rejected: number = 0;
      for (const raw of [
        login.toJsonText().replace('"schema_version":1', '"schema_version":2'),
        login.toJsonText().replace('"password":"synthetic-pass"',
          '"password":"synthetic-pass","cookie":"forbidden"')
      ]) {
        try { QMPlusSavedLogin.fromJsonText(raw); } catch (e) { rejected++; }
      }
      try { new QMPlusSavedLogin('b'.repeat(32), 'wrong-account', 'pass'); } catch (e) { rejected++; }
      expect(rejected).assertEqual(3);
    });

    it('random_source_failure_never_writes_a_secret_or_enables_autofill', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const failed: QMPlusSession = new QMPlusSession((): void => {}, store, journal, (): string => {
        throw new Error('synthetic RNG unavailable');
      });
      expect(await failed.saveSavedLogin('student@example.org', 'synthetic-pass')).assertFalse();
      expect(store.saveCount).assertEqual(0);
      expect(failed.autoFillEnabled).assertFalse();
      expect(failed.loginSettingsError).assertEqual('系统无法准备 QMplus 安全存储，请稍后重试。');
    });

    it('default_off_then_matching_asset_and_explicit_nonce_restore_enabled', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const first: QMPlusSession = session(store, journal);
      await first.restoreSavedLoginStatus();
      expect(first.autoFillEnabled).assertFalse();
      expect(first.savedLoginAvailable).assertFalse();
      expect(await first.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(first.savedLoginAvailable).assertTrue();
      expect(first.autoFillEnabled).assertFalse();
      expect(journal.value).assertNull();
      expect(await first.setAutoFillEnabled(true)).assertTrue();
      expect(first.autoFillEnabled).assertTrue();
      expect(journal.value).assertEqual(store.login?.recordID);
      const restarted: QMPlusSession = session(store, journal);
      await restarted.restoreSavedLoginStatus();
      expect(restarted.savedLoginAvailable).assertTrue();
      expect(restarted.autoFillEnabled).assertTrue();
      journal.value = 'f'.repeat(32); // 旧记录ID不应授权另一份资产。
      const mismatch: QMPlusSession = session(store, journal);
      await mismatch.restoreSavedLoginStatus();
      expect(mismatch.autoFillEnabled).assertFalse();
    });

    it('disable_revoke_failure_deletes_asset_and_cannot_reenable_on_restore', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const current: QMPlusSession = session(store, journal);
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      journal.failRemove = true;
      expect(await current.setAutoFillEnabled(false)).assertTrue();
      expect(current.autoFillEnabled).assertFalse();
      expect(store.login).assertNull();
      const restarted: QMPlusSession = session(store, journal);
      await restarted.restoreSavedLoginStatus();
      expect(restarted.autoFillEnabled).assertFalse();
    });

    it('double_revoke_failure_warns_that_restart_cannot_be_guaranteed', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const current: QMPlusSession = session(store, journal);
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      journal.failRemove = true;
      store.failClear = true;
      expect(await current.setAutoFillEnabled(false)).assertFalse();
      expect(current.autoFillEnabled).assertFalse();
      expect(current.loginSettingsError.includes('重启后请检查')).assertTrue();
    });

    it('delete_waits_for_inflight_save_and_old_write_cannot_resurrect_secret', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const hold: Gate = new Gate();
      store.saveGate = hold;
      const current: QMPlusSession = session(store, journal);
      const saving: Promise<boolean> = current.saveSavedLogin('student@example.org', 'synthetic-pass');
      await store.saveStarted.promise;
      const deleting: Promise<boolean> = current.deleteSavedLogin();
      expect(current.autoFillEnabled).assertFalse();
      hold.release();
      expect(await saving).assertFalse();
      expect(await deleting).assertTrue();
      expect(store.login).assertNull();
      expect(current.savedLoginAvailable).assertFalse();
    });

    it('late_restore_cannot_reenable_an_old_record_after_a_new_save', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      store.login = new QMPlusSavedLogin('a'.repeat(32), 'old@example.org', 'old-synthetic');
      journal.value = store.login.recordID;
      const gate: Gate = new Gate();
      store.loadGate = gate;
      const current: QMPlusSession = session(store, journal);
      const oldRestore: Promise<void> = current.restoreSavedLoginStatus();
      await store.loadStarted.promise;
      const replacement: Promise<boolean> = current.saveSavedLogin('new@example.org', 'new-synthetic');
      gate.release();
      await oldRestore;
      expect(await replacement).assertTrue();
      expect(current.autoFillEnabled).assertFalse();
      expect(current.savedLoginAvailable).assertTrue();
      expect(journal.value).assertNull();
      expect(store.login?.account).assertEqual('new@example.org');
    });

    it('web_flow_reads_account_then_password_only_after_matching_local_authorization', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const current: QMPlusSession = session(store, journal);
      current.openLogin();
      expect(await current.captureLoginAuthorization(current.loginOwner())).assertNull();
      expect(store.loadCount).assertEqual(0);
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.captureLoginAuthorization(current.loginOwner())).assertNull();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      expect(await current.authorizedAccountHint(ticket)).assertEqual('student@example.org');
      expect(await current.authorizedPasswordFor('other@example.org', ticket)).assertNull();
      expect(await current.authorizedPasswordFor('STUDENT@example.org', ticket)).assertEqual('synthetic-pass');
      current.closeLogin();
      expect(await current.authorizedPasswordFor('student@example.org', ticket)).assertNull();
    });

    it('late_secret_read_after_close_or_disable_cannot_escape_to_old_web_owner', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const current: QMPlusSession = session(store, journal);
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      const hold: Gate = new Gate();
      store.loadGate = hold;
      const read: Promise<string | null> = current.authorizedPasswordFor('student@example.org', ticket);
      await store.loadStarted.promise;
      current.closeLogin();
      hold.release();
      expect(await read).assertNull();
      current.openLogin();
      const secondTicket: QMPlusLoginAuthorization = await authorization(current);
      const secondHold: Gate = new Gate();
      store.loadStarted = new Gate();
      store.loadGate = secondHold;
      const secondRead: Promise<string | null> = current.authorizedPasswordFor('student@example.org', secondTicket);
      await store.loadStarted.promise;
      const off: Promise<boolean> = current.setAutoFillEnabled(false);
      secondHold.release();
      expect(await secondRead).assertNull();
      expect(await off).assertTrue();
      current.dispose();
    });

    it('same_account_password_replacement_never_supplies_the_new_secret_to_the_old_flow', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'old-synthetic')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      expect(await current.authorizedAccountHint(ticket)).assertEqual('student@example.org');
      expect(await current.saveSavedLogin('student@example.org', 'replacement-synthetic')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      expect(current.isAuthorizationCurrent(ticket)).assertFalse();
      expect(await current.authorizedPasswordFor('student@example.org', ticket)).assertNull();
      current.openLogin();
      const next: QMPlusLoginAuthorization = await authorization(current);
      expect(next.recordID === ticket.recordID).assertFalse();
      expect(await current.authorizedPasswordFor('student@example.org', next)).assertEqual('replacement-synthetic');
      current.dispose();
    });

    it('disable_and_reenable_of_the_same_asset_cannot_revive_a_delayed_secret_callback', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      const hold: Gate = new Gate();
      store.loadGate = hold;
      const read: Promise<string | null> = current.authorizedPasswordFor('student@example.org', ticket);
      await store.loadStarted.promise;
      expect(await current.setAutoFillEnabled(false)).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      hold.release();
      expect(await read).assertNull();
      expect(current.isAuthorizationCurrent(ticket)).assertFalse();
      const next: QMPlusLoginAuthorization = await authorization(current);
      expect(next.recordID).assertEqual(ticket.recordID);
      expect(next.settingsRevision === ticket.settingsRevision).assertFalse();
      expect(await current.authorizedPasswordFor('student@example.org', next)).assertEqual('synthetic-pass');
      current.dispose();
    });

    it('closing_and_reopening_before_a_delayed_capture_retires_the_original_owner', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const current: QMPlusSession = session(store, new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const original = current.loginOwner();
      const hold: Gate = new Gate();
      store.loadGate = hold;
      const capture: Promise<QMPlusLoginAuthorization | null> = current.captureLoginAuthorization(original);
      await store.loadStarted.promise;
      current.closeLogin();
      current.openLogin();
      hold.release();
      expect(await capture).assertNull();
      expect(current.isLoginOwnerCurrent(original)).assertFalse();
      const next: QMPlusLoginAuthorization = await authorization(current);
      expect(current.isAuthorizationCurrent(next)).assertTrue();
      current.dispose();
    });

    it('a_rebuilt_session_cannot_accept_the_previous_sessions_owner_or_authorization', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const old: QMPlusSession = session(store, journal);
      expect(await old.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await old.setAutoFillEnabled(true)).assertTrue();
      old.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(old);
      old.dispose();
      const rebuilt: QMPlusSession = session(store, journal);
      await rebuilt.restoreSavedLoginStatus();
      rebuilt.openLogin();
      expect(rebuilt.isLoginOwnerCurrent(ticket.owner)).assertFalse();
      expect(rebuilt.isAuthorizationCurrent(ticket)).assertFalse();
      expect(await rebuilt.authorizedPasswordFor('student@example.org', ticket)).assertNull();
      expect(rebuilt.isAuthorizationCurrent(await authorization(rebuilt))).assertTrue();
      rebuilt.dispose();
    });

    it('a_changed_asset_or_consent_nonce_is_rejected_even_without_a_local_settings_mutation', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      const current: QMPlusSession = session(store, journal);
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      store.login = new QMPlusSavedLogin('f'.repeat(32), 'student@example.org', 'replacement-synthetic');
      journal.value = store.login.recordID;
      expect(await current.authorizedPasswordFor('student@example.org', ticket)).assertNull();
      expect(current.autoFillEnabled).assertFalse();
      current.dispose();
    });

    it('the_production_ledger_preserves_once_claims_across_documents_and_rejects_late_acks', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      expect(ledger.claimUsername('document_1')).assertTrue();
      expect(ledger.claimUsername('document_1')).assertFalse();
      expect(ledger.recordUsernameSubmission('document_1', 'MANUAL_REQUIRED')).assertFalse();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
      ledger.beginDocument('document_2');
      expect(ledger.claimUsername('document_2')).assertFalse();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertTrue();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
      ledger.beginDocument('document_3');
      expect(ledger.claimContinue('document_3', false)).assertFalse();
      expect(ledger.claimContinue('document_3', true)).assertTrue();
      expect(ledger.claimContinue('document_3', true)).assertFalse();
    });

    it('direct_verified_identity_is_current_document_only_and_does_not_renew_password_claims', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      ledger.beginDocument('document_1');
      expect(ledger.acknowledgeCurrentAccount('document_2', true)).assertFalse();
      expect(ledger.acknowledgeCurrentAccount('document_1', false)).assertFalse();
      expect(ledger.acknowledgeCurrentAccount('document_1', true)).assertTrue();
      expect(ledger.claimPassword('document_1', true)).assertTrue();
      ledger.beginDocument('document_2');
      expect(ledger.acknowledgeCurrentAccount('document_2', true)).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
      expect(ledger.claimContinue('document_2', true)).assertTrue();
      ledger.stop();
      expect(ledger.identityAcknowledged('document_2')).assertFalse();
    });

    it('direct_continue_prevents_backwards_credential_steps_and_saml_restart', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      ledger.beginDocument('document_1');
      expect(ledger.acknowledgeCurrentAccount('document_1', true)).assertTrue();
      expect(ledger.claimContinue('document_1', true)).assertTrue();
      ledger.beginDocument('document_2');
      expect(ledger.claimAccount('document_2', true)).assertFalse();
      expect(ledger.claimUsername('document_2')).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
      expect(ledger.claimContinue('document_2', true)).assertFalse();
      expect(ledger.credentialsAttempted()).assertTrue();
    });

    it('password_is_once_only_and_manual_stop_stays_stopped_after_navigation', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.claimUsername('document_1')).assertTrue();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
      expect(ledger.claimPassword('document_1', false)).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertTrue();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      expect(ledger.claimUsername('document_1')).assertFalse();
      ledger.stop();
      ledger.beginDocument();
      expect(ledger.isActive()).assertFalse();
      expect(ledger.claimUsername('document_2')).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
      ledger.begin(); // Only a new native presentation can grant a fresh attempt.
      expect(ledger.claimUsername('document_2')).assertTrue();
    });

    it('account_selection_has_an_independent_ack_and_same_document_matching_password_proof', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.claimAccount('document_1', false)).assertFalse();
      expect(ledger.claimAccount('document_1', true)).assertTrue();
      expect(ledger.claimAccount('document_1', true)).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      expect(ledger.recordAccountSelection('document_1', 'USERNAME_SUBMITTED')).assertFalse();
      expect(ledger.recordAccountSelection('document_1', 'ACCOUNT_SELECTED')).assertTrue();
      expect(ledger.accountSelected('document_1')).assertTrue();
      expect(ledger.usernameSubmitted('document_1')).assertFalse();
      expect(ledger.claimPassword('document_1', false)).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertTrue();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      expect(ledger.claimUsername('document_1')).assertFalse();
      ledger.beginDocument();
      expect(ledger.recordAccountSelection('document_2', 'ACCOUNT_SELECTED')).assertFalse();
      expect(ledger.accountSelected('document_2')).assertFalse();
      expect(ledger.claimAccount('document_2', true)).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
    });

    it('an_account_ack_arriving_after_navigation_or_manual_stop_cannot_authorize_password', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.claimAccount('document_1', true)).assertTrue();
      ledger.beginDocument();
      expect(ledger.recordAccountSelection('document_1', 'ACCOUNT_SELECTED')).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
      ledger.stop();
      expect(ledger.recordAccountSelection('document_1', 'ACCOUNT_SELECTED')).assertFalse();
      expect(ledger.claimAccount('document_2', true)).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
    });

    it('account_selection_cannot_retry_identity_after_username_or_password_was_attempted', 0, () => {
      const ledger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
      ledger.begin();
      expect(ledger.claimUsername('document_1')).assertTrue();
      expect(ledger.claimAccount('document_1', true)).assertFalse();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertTrue();
      expect(ledger.claimPassword('document_1', true)).assertTrue();
      expect(ledger.claimAccount('document_1', true)).assertFalse();
    });

    it('verified_sync_hides_the_presented_window_without_retiring_web_owner_or_authorization', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      current.presentLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      let retireCalls: number = 0;
      current.bindLoginWeb(ticket.owner, (): void => { retireCalls++; });
      const generation: number = current.beginSync();
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertFalse();
      expect(current.isCurrent(generation)).assertTrue();
      expect(current.isAuthorizationCurrent(ticket)).assertTrue();
      expect(retireCalls).assertEqual(0);
      current.failSync(generation, 'QMplus 同步失败。');
      expect(current.loginPresented).assertFalse();
      expect(current.manualContinuationRequired).assertTrue();
      expect(retireCalls).assertEqual(1);
      current.openLogin();
      expect(current.loginPresented).assertTrue();
      expect(retireCalls).assertEqual(1);
      current.dispose();
    });

    it('feature_off_preserves_saved_record_cookie_and_snapshot_but_rejects_old_owner_after_reenable', 0, async () => {
      const store: FakeLoginStore = new FakeLoginStore();
      const journal: FakeAuthorizationJournal = new FakeAuthorizationJournal();
      let webClears: number = 0;
      const current: QMPlusSession = new QMPlusSession((): void => { webClears++; }, store, journal,
        (): string => 'a'.repeat(32));
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      const saved: QMPlusSavedLogin | null = store.login;
      current.openLogin();
      current.completeSync(current.beginSync(), '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-04T00:00:00.000Z","ok":true,"partial":false,"courses":[],"activities":[],"warnings":[]}');
      const previous = current.snapshot;
      current.openLogin();
      const ticket: QMPlusLoginAuthorization = await authorization(current);
      const generation: number = current.beginSync();
      const clearsBefore: number = webClears;
      current.setFeatureEnabled(false);
      expect(current.isFeatureEnabled).assertFalse();
      expect(current.loginVisible).assertFalse();
      expect(current.syncing).assertFalse();
      expect(current.snapshot === previous).assertTrue();
      expect(store.login === saved).assertTrue();
      expect(store.clearCount).assertEqual(0);
      expect(webClears).assertEqual(clearsBefore);
      expect(current.autoFillEnabled).assertTrue();
      expect(await current.captureLoginAuthorization(ticket.owner)).assertNull();
      current.openLogin();
      expect(current.loginVisible).assertFalse();
      expect(current.beginSync()).assertEqual(-1);
      current.setFeatureEnabled(true);
      expect(current.isAuthorizationCurrent(ticket)).assertFalse();
      current.completeSync(generation, '{broken');
      expect(current.snapshot === previous).assertTrue();
      expect(current.error.length).assertEqual(0);
      current.openLogin();
      expect(current.isAuthorizationCurrent(await authorization(current))).assertTrue();
      current.dispose();
    });
  });
}
