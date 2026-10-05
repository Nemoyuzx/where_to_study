// 全合成存储：不初始化 AppContext、不读取任何真实登录资料、不启动 ArkWeb。
import { describe, it, expect } from '@ohos/hypium';
import { QMPlusSavedLogin, QMPlusSavedLoginStoring } from '../main/ets/store/QMPlusSavedLoginStore';
import { QMPlusAuthAttemptLedger, QMPlusAuthNavigationPolicy } from '../main/ets/view/QMPlusConnectionView';
import { QMPlusAuthorizationJournal, QMPlusLoginAuthorization, QMPlusSession } from '../main/ets/view/QMPlusSession';

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
    it('official_error_reconnect_retires_old_owner_and_uses_dashboard_without_deleting_saved_state', 0, async () => {
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
      expect(current.loginPresented).assertTrue();
      expect(current.isCurrent(generation)).assertFalse();
      current.openLogin('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1');
      expect(stops).assertEqual(1);
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
      expect(stops).assertEqual(0);
      expect(restarts).assertEqual(0);
      expect(current.isLoginOwnerCurrent(owner)).assertTrue();
      expect(current.loginPresented).assertTrue();
      current.noteOfficialPageLoading(owner, false);
      current.openLogin();
      expect(stops).assertEqual(1);
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
    it('authorized_quiet_owner_reveals_same_connection_on_second_connect_and_cancels_on_background', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertFalse();
      current.cancelQuietLoginOnBackground();
      expect(current.loginVisible).assertFalse();
      current.openLogin();
      const generation: number = current.beginSync();
      current.openLogin();
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

    it('sync_failure_reveals_same_owner_and_retains_a_manual_retry', 0, async () => {
      const current: QMPlusSession = session(new FakeLoginStore(), new FakeAuthorizationJournal());
      expect(await current.saveSavedLogin('student@example.org', 'synthetic-pass')).assertTrue();
      expect(await current.setAutoFillEnabled(true)).assertTrue();
      current.openLogin();
      current.failSync(current.beginSync(), 'QMplus 同步已超时，请稍后重试。');
      expect(current.loginVisible).assertTrue();
      expect(current.loginPresented).assertTrue();
      expect(current.error.length > 0).assertTrue();
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
      ledger.beginDocument();
      expect(ledger.claimUsername('document_2')).assertFalse();
      expect(ledger.recordUsernameSubmission('document_1', 'USERNAME_SUBMITTED')).assertFalse();
      expect(ledger.claimPassword('document_1', true)).assertFalse();
      expect(ledger.claimPassword('document_2', true)).assertFalse();
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
      expect(current.loginPresented).assertTrue();
      expect(retireCalls).assertEqual(0);
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
