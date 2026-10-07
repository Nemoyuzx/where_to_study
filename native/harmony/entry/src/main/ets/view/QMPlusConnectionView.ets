import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { AppModel } from '../model/AppModel';
import { QMPlusSnapshotParser, QMPlusURLPolicy } from '../net/QMPlusSnapshot';
import { AppContext } from '../store/AppContext';
import { newQMPlusRecordID } from '../store/QMPlusSavedLoginStore';
import { QMPlusLoginAuthorization, QMPlusLoginOwner, QMPlusSession } from './QMPlusSession';
import { QMPlusWebProfileStore } from '../store/QMPlusWebProfileStore';

export class QMPlusAuthNavigationPolicy {
  static readonly qmLoginPage: string = 'https://qmplus.qmul.ac.uk/login/index.php';
  static readonly qmSAMLStart: string = 'https://qmplus.qmul.ac.uk/auth/saml2/login.php';
  static readonly qmGuestLanding: string = 'https://qmplus.qmul.ac.uk/?redirect=0';
  static readonly qmHome: string = 'https://qmplus.qmul.ac.uk/';
  static isQMLoginLanding(url: string): boolean {
    return url === QMPlusAuthNavigationPolicy.qmLoginPage || url === QMPlusAuthNavigationPolicy.qmGuestLanding ||
      url === QMPlusAuthNavigationPolicy.qmHome;
  }
  static isQMGuestEntry(url: string): boolean {
    return QMPlusAuthNavigationPolicy.isQMLoginLanding(url) || url === QMPlusURLPolicy.home || url === 'https://qmplus.qmul.ac.uk/my';
  }
  static isOfficialQMPage(url: string): boolean { return /^https:\/\/qmplus\.qmul\.ac\.uk\//.test(url); }
  private static readonly microsoftPage: RegExp =
    /^https:\/\/login\.microsoftonline\.com\/(?:569df091-b013-40e3-86ee-bd9cb9e25814\/(?:saml2|login)|kmsi)(?:\?[^\s#]*)?$/;

  static isKnownMicrosoftPage(url: string): boolean {
    return QMPlusAuthNavigationPolicy.microsoftPage.test(url);
  }

  static isVerificationPage(url: string): boolean {
    return /^https:\/\/login\.microsoftonline\.com\/common\/deviceauthtls\/reprocess(?:\?[^\s#]*)?$/i.test(url);
  }

  static isMicrosoftTransitPage(url: string): boolean {
    return /^https:\/\/(?:device\.)?login\.microsoftonline\.com(?::443)?(?:[/?#][^\s]*)?$/i.test(url) &&
      !QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url) && !QMPlusAuthNavigationPolicy.isVerificationPage(url);
  }

  static shouldStartSAML(url: string, currentURL: string, active: boolean,
    authorized: boolean, alreadyStarted: boolean): boolean {
    return active && authorized && !alreadyStarted &&
      QMPlusAuthNavigationPolicy.isQMGuestEntry(url) && currentURL === url;
  }
}

// One native ledger belongs to one presentation. A navigation retires the
// document callbacks, while every credential claim remains whole-connection once.
export class QMPlusAuthAttemptLedger {
  private active: boolean = false;
  private usernameClaimed: boolean = false;
  private passwordClaimed: boolean = false;
  private accountClaimed: boolean = false;
  private continueClaimed: boolean = false;
  private attemptedCredentials: boolean = false;
  private acknowledgedIdentity: boolean = false;
  private documentNonce: string = '';
  private claimedAccountDocument: string = '';
  private selectedAccountDocument: string = '';
  private claimedUsernameDocument: string = '';
  private submittedUsernameDocument: string = '';
  private submittedUsernameDeadline: number = 0;
  private readonly clock: () => number;

  constructor(clock: () => number = (): number => Date.now()) { this.clock = clock; }

  begin(): void {
    this.active = true;
    this.usernameClaimed = false;
    this.passwordClaimed = false;
    this.accountClaimed = false;
    this.continueClaimed = false;
    this.attemptedCredentials = false;
    this.acknowledgedIdentity = false;
    this.documentNonce = '';
    this.claimedUsernameDocument = '';
    this.submittedUsernameDocument = '';
    this.submittedUsernameDeadline = 0;
    this.claimedAccountDocument = '';
    this.selectedAccountDocument = '';
  }

  isActive(): boolean { return this.active; }
  passwordAttempted(): boolean { return this.passwordClaimed; }
  continueAttempted(): boolean { return this.continueClaimed; }
  accountAttempted(): boolean { return this.accountClaimed; }
  credentialsAttempted(): boolean { return this.attemptedCredentials || this.passwordClaimed || this.continueClaimed; }
  canWaitForInitialAccountChoice(attempt: number): boolean {
    return this.active && !this.credentialsAttempted() && attempt >= 0 && attempt < 8;
  }

  beginDocument(document: string = ''): void {
    this.documentNonce = document;
    this.claimedUsernameDocument = '';
    this.submittedUsernameDocument = '';
    this.submittedUsernameDeadline = 0;
    this.claimedAccountDocument = '';
    this.selectedAccountDocument = '';
  }

  stop(): void { this.active = false; this.beginDocument(); }

  claimAccount(document: string, accountMatch: boolean): boolean {
    if (!this.active || this.accountClaimed || this.usernameClaimed || this.passwordClaimed || this.continueClaimed ||
      !accountMatch || !/^[A-Za-z0-9_-]{8,64}$/.test(document)) { return false; }
    this.accountClaimed = true;
    this.documentNonce = document;
    this.attemptedCredentials = true;
    this.claimedAccountDocument = document;
    return true;
  }

  recordAccountSelection(document: string, code: string): boolean {
    if (!this.active || !this.accountClaimed || this.claimedAccountDocument !== document || code !== 'ACCOUNT_SELECTED') { return false; }
    this.selectedAccountDocument = document;
    this.acknowledgedIdentity = true;
    return true;
  }

  accountSelected(document: string): boolean {
    return this.active && document.length > 0 && this.selectedAccountDocument === document;
  }

  identityAcknowledged(document: string): boolean {
    return this.active && this.documentNonce === document && /^[A-Za-z0-9_-]{8,64}$/.test(document) && this.acknowledgedIdentity;
  }

  acknowledgeCurrentAccount(document: string, accountMatch: boolean): boolean {
    if (!this.active || this.documentNonce !== document || this.passwordClaimed || this.continueClaimed || !accountMatch ||
      !/^[A-Za-z0-9_-]{8,64}$/.test(document)) { return false; }
    this.acknowledgedIdentity = true;
    return true;
  }

  claimUsername(document: string): boolean {
    if (!this.active || this.usernameClaimed || this.passwordClaimed || this.continueClaimed ||
      !/^[A-Za-z0-9_-]{8,64}$/.test(document)) { return false; }
    this.usernameClaimed = true;
    this.documentNonce = document;
    this.attemptedCredentials = true;
    this.claimedUsernameDocument = document;
    return true;
  }

  recordUsernameSubmission(document: string, code: string): boolean {
    if (!this.active || !this.usernameClaimed || this.claimedUsernameDocument !== document ||
      code !== 'USERNAME_SUBMITTED') { return false; }
    // A foreground resume or repeated ACK must not mint another settling
    // window. Keep the first ACK's original, same-document two-second bound.
    if (this.submittedUsernameDocument !== document) {
      this.submittedUsernameDeadline = this.clock() + 2000;
      this.submittedUsernameDocument = document;
    }
    this.acknowledgedIdentity = true;
    return true;
  }

  usernameSubmitted(document: string): boolean {
    return this.active && document.length > 0 && this.submittedUsernameDocument === document;
  }

  usernameTransitionDeadline(document: string): number {
    return this.usernameSubmitted(document) && !this.passwordClaimed && !this.continueClaimed ?
      this.submittedUsernameDeadline : 0;
  }

  claimPassword(document: string, accountMatch: boolean): boolean {
    if (!this.active || this.passwordClaimed || this.continueClaimed || !accountMatch || !this.identityAcknowledged(document)) { return false; }
    this.passwordClaimed = true;
    return true;
  }

  claimContinue(document: string, accountMatch: boolean): boolean {
    if (!this.active || this.continueClaimed || !accountMatch || !this.identityAcknowledged(document)) { return false; }
    this.continueClaimed = true;
    return true;
  }
}

// The production auth loop's settling state. Recreating the loop may restore
// the username ACK's remaining read-only budget, never its submission claims.
export class QMPlusAuthTransitionState {
  private deadline: number;
  private readonly ledger: QMPlusAuthAttemptLedger;
  private readonly document: string;
  private readonly clock: () => number;
  constructor(ledger: QMPlusAuthAttemptLedger, document: string,
    clock: () => number = (): number => Date.now()) {
    this.ledger = ledger; this.document = document; this.clock = clock;
    this.deadline = ledger.usernameTransitionDeadline(document);
  }
  restoreUsernameBudget(): void {
    this.deadline = this.ledger.usernameTransitionDeadline(this.document);
  }
  beginSettling(): void { this.deadline = this.clock() + 2000; }
  isWithinBudget(): boolean { return this.ledger.identityAcknowledged(this.document) && this.clock() < this.deadline; }
  canWait(reason: string, afterStep: boolean): boolean {
    return afterStep && this.isWithinBudget() &&
      ['ALREADY_ATTEMPTED', 'KNOWN_FORM_ABSENT', 'FORM_UNTRUSTED'].includes(reason);
  }
}

class QMPlusAuthInspection {
  readonly stage: string;
  readonly reason: string;
  readonly accountMatch: boolean;

  constructor(stage: string, reason: string, accountMatch: boolean) {
    this.stage = stage;
    this.reason = reason;
    this.accountMatch = accountMatch;
  }

  static parse(raw: string, nonce: string): QMPlusAuthInspection | null {
    if (raw.length === 0 || raw.length > 512) { return null; }
    try {
      const value: Object = JSON.parse(raw) as Object;
      if (value === null || typeof value !== 'object' || Array.isArray(value)) { return null; }
      const item: Record<string, Object> = value as Record<string, Object>;
      if (Object.keys(item).length !== 5 || item['v'] !== 1 || item['document'] !== nonce ||
        typeof item['stage'] !== 'string' || typeof item['reason'] !== 'string' ||
        typeof item['accountMatch'] !== 'boolean' ||
        !['authenticated', 'account', 'username', 'password', 'continue', 'challenge', 'manual', 'unknown', 'loading'].includes(item['stage'] as string) ||
        !['READY', 'AUTHENTICATED', 'LOADING', 'INVALID_NONCE', 'STALE_DOCUMENT',
          'UNTRUSTED_CONTEXT', 'UNSUPPORTED_PAGE', 'ACCOUNT_CHOOSER', 'ACCOUNT_HINT_REQUIRED', 'FORM_UNTRUSTED',
          'INTERFERENCE', 'KNOWN_FORM_ABSENT', 'ACCOUNT_MISMATCH', 'USERNAME_NOT_SUBMITTED',
          'ALREADY_ATTEMPTED', 'MFA_REQUIRED', 'CAPTCHA_REQUIRED', 'CURRENT_ACCOUNT_VERIFIED'].includes(item['reason'] as string)) { return null; }
      if ((item['stage'] === 'challenge') !== ['MFA_REQUIRED', 'CAPTCHA_REQUIRED'].includes(item['reason'] as string)) { return null; }
      return new QMPlusAuthInspection(item['stage'] as string, item['reason'] as string,
        item['accountMatch'] as boolean);
    } catch (e) { return null; }
  }
}

class QMPlusAuthUsernameRequest {
  readonly document: string;
  readonly stage: string = 'username';
  readonly account: string;

  constructor(nonce: string, account: string) {
    this.document = nonce;
    this.account = account;
  }
}

class QMPlusAuthAccountRequest {
  readonly document: string;
  readonly stage: string = 'account';
  readonly account: string;
  constructor(nonce: string, account: string) { this.document = nonce; this.account = account; }
}

class QMPlusAuthPasswordRequest {
  readonly document: string;
  readonly stage: string = 'password';
  readonly account: string;
  readonly password: string;
  readonly identityAcknowledged: boolean;

  constructor(nonce: string, account: string, password: string, identityAcknowledged: boolean) {
    this.document = nonce;
    this.account = account;
    this.password = password;
    this.identityAcknowledged = identityAcknowledged;
  }
}

class QMPlusAuthContinueRequest {
  readonly document: string;
  readonly stage: string = 'continue';
  readonly account: string;
  readonly identityAcknowledged: boolean;
  constructor(nonce: string, account: string, identityAcknowledged: boolean) {
    this.document = nonce; this.account = account; this.identityAcknowledged = identityAcknowledged;
  }
}

// 仅官方 HTTPS 网页在本应用独立的 incognito ArkWeb 中登录。Microsoft SSO/MFA
// 页面可以正常导航；本机明确授权、主文档与官方表单双重验证后仅提交普通
// Next/Sign in/保持登录各一次；唯一精确匹配的已保存账号可选一次。
// 仅验证码/MFA自动呈现，未知页面暂停并保留手动继续；不注册 JS proxy。
@ComponentV2
export struct QMPlusConnectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: QMPlusSession = new QMPlusSession();
  @Local authStatus: string = '';
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private mounted: boolean = false;
  private authPresentationRevision: number = 0;
  private pageRevision: number = 0;
  private authURL: string = '';
  private authNonce: string = '';
  private authHelperInstalled: boolean = false;
  private authForeground: boolean = false;
  private documentReadyURL: string = '';
  private pageScript: string = '';
  private dashboardRestored: boolean = false;
  private authWindow: window.Window | null = null;
  private authWindowListener: ((event: window.WindowEventType) => void) | null = null;
  private readonly authLedger: QMPlusAuthAttemptLedger = new QMPlusAuthAttemptLedger();
  private loginOwner: QMPlusLoginOwner | null = null;
  private authAuthorization: QMPlusLoginAuthorization | null = null;
  private authSAMLStarted: boolean = false;
  private authPlainLoginStarted: boolean = false;
  private authTimer: number = -1;
  private resolveAuthDelay: (() => void) | null = null;
  private autoSyncPending: boolean = true;
  private detailTargetRestored: boolean = false;
  private profileInitializationStarted: boolean = false;
  private delayTimer: number = -1;
  private resolveDelay: (() => void) | null = null;

  aboutToAppear(): void {
    this.mounted = true;
    this.authPresentationRevision++;
    const owner: QMPlusLoginOwner = this.session.loginOwner();
    this.loginOwner = owner;
    this.session.beginOfficialWebMount(owner);
    this.session.bindLoginWeb(owner, (): void => this.retireOfficialWeb(), (): void => this.restartOfficialWeb());
    this.authAuthorization = null;
    this.authLedger.begin();
    this.authSAMLStarted = false;
    this.authPlainLoginStarted = false;
    this.autoSyncPending = !this.session.explicitDetailRequest;
    this.detailTargetRestored = false;
    this.profileInitializationStarted = false;
    this.attachAuthWindow();
  }

  aboutToDisappear(): void {
    const owner: QMPlusLoginOwner | null = this.loginOwner;
    const ownsPresentation: boolean = owner !== null && this.session.isLoginOwnerCurrent(owner);
    if (ownsPresentation) { this.session.persistOfficialWebSession(); }
    if (owner !== null) { this.session.unbindLoginWeb(owner); }
    this.detachAuthWindow();
    this.invalidateAuth();
    this.authLedger.stop();
    this.authAuthorization = null;
    this.loginOwner = null;
    this.mounted = false;
    this.pageRevision++;
    this.cancelWebFlight();
    this.cancelDelay();
    if (ownsPresentation) { this.session.cancelSync(); }
  }

  private safeCurrentURL(): string {
    try { return this.controller.getUrl(); } catch (e) { return ''; }
  }

  private retireOfficialWeb(): void {
    this.authPresentationRevision++;
    this.authLedger.stop();
    this.authAuthorization = null;
    this.cancelAuthDelay();
    this.cancelWebFlight();
    this.cancelDelay();
    // Stop a pending SSO navigation before clearing the app-owned profile;
    // reactive unmounting alone happens later and can race a Set-Cookie reply.
    if (this.safeCurrentURL().length > 0) { this.controller.stop(); }
  }

  private restartOfficialWeb(): void {
    if (!this.mounted || !this.session.isFeatureEnabled || !this.session.loginVisible) { return; }
    this.invalidateAuth(); this.pageRevision++;
    const owner: QMPlusLoginOwner = this.session.loginOwner();
    this.loginOwner = owner;
    this.session.bindLoginWeb(owner, (): void => this.retireOfficialWeb(), (): void => this.restartOfficialWeb());
    this.authLedger.begin(); this.authSAMLStarted = false; this.authPlainLoginStarted = false;
    this.autoSyncPending = true; this.detailTargetRestored = false; this.dashboardRestored = false;
    this.documentReadyURL = '';
    this.profileInitializationStarted = false;
    // Explicit recovery creates a fresh native owner and a dashboard GET,
    // never ArkWeb refresh(), SAML/MFA POST replay, or cookie removal.
    this.controller.loadUrl('about:blank');
  }

  private async preparePersistentProfile(owner: number, page: number): Promise<void> {
    if (this.profileInitializationStarted || !this.ownsLoginPresentation() || this.safeCurrentURL() !== 'about:blank') { return; }
    const ticket: QMPlusLoginOwner | null = this.loginOwner;
    if (ticket === null) { return; }
    this.profileInitializationStarted = true;
    try {
      this.session.noteWebLoaded();
      if (!await this.session.prepareOfficialWeb(ticket)) { return; }
      if (!this.ownsLoginPresentation() || owner !== this.authPresentationRevision || page !== this.pageRevision ||
        !this.authForeground || !this.session.loginForeground || this.safeCurrentURL() !== 'about:blank') { return; }
      // No previous URL or form/POST is restored from persistent state.
      this.controller.loadUrl(this.session.targetURL);
    } finally {
      this.profileInitializationStarted = false;
      if (this.safeCurrentURL() === 'about:blank') { this.session.noteOfficialPageLoading(ticket, false); }
    }
  }

  private async loadPageScript(): Promise<string> {
    if (this.pageScript.length > 0) { return this.pageScript; }
    const bytes: Uint8Array = await AppContext.get().resourceManager.getRawFileContent('qmplus-page.js');
    if (bytes.length === 0 || bytes.length > 16 * 1024) { throw new Error('QM_PAGE_UNAVAILABLE'); }
    this.pageScript = util.TextDecoder.create('utf-8').decodeToString(bytes);
    return this.pageScript;
  }

  private async inspectQMPage(owner: number, page: number, url: string): Promise<string> {
    const source: string = await this.loadPageScript();
    if (!this.sameOwnedPage(owner, page, url)) { return 'unknown'; }
    const kind: string = this.decodeAuthReply(await this.controller.runJavaScript(
      '(function(){if(location.href!==' + JSON.stringify(url) + ')return "unknown";return (' + source + ');})()'));
    return this.sameOwnedPage(owner, page, url) && ['authenticated', 'guest', 'error', 'unknown', 'loading'].includes(kind) ? kind : 'unknown';
  }

  private attachAuthWindow(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || context === null) { this.requireManualAuth(''); return; }
    window.getLastWindow(context).then((ownedWindow: window.Window): void => {
      if (!this.ownsLoginPresentation()) { return; }
      this.authWindow = ownedWindow;
      const listener = (event: window.WindowEventType): void => {
        if (event === window.WindowEventType.WINDOW_INACTIVE || event === window.WindowEventType.WINDOW_HIDDEN) {
          this.updateAuthForeground(false);
        } else if (event === window.WindowEventType.WINDOW_ACTIVE || event === window.WindowEventType.WINDOW_SHOWN) {
          this.updateAuthForeground(ownedWindow.isWindowShowing() && ownedWindow.isFocused());
        }
      };
      this.authWindowListener = listener;
      ownedWindow.on('windowEvent', listener);
      this.updateAuthForeground(ownedWindow.isWindowShowing() && ownedWindow.isFocused());
    }).catch((): void => { this.requireManualAuth(''); });
  }

  private detachAuthWindow(): void {
    if (this.authWindow !== null && this.authWindowListener !== null) {
      try { this.authWindow.off('windowEvent', this.authWindowListener); } catch (e) {}
    }
    this.authWindow = null;
    this.authWindowListener = null;
    this.authForeground = false;
  }

  private updateAuthForeground(foreground: boolean): void {
    if (!this.ownsLoginPresentation()) { return; }
    const wasForeground: boolean = this.authForeground;
    this.authForeground = foreground;
    if (!foreground) {
      this.session.cancelQuietLoginOnBackground();
      this.authPresentationRevision++;
      this.authAuthorization = null;
      this.cancelAuthDelay();
      return;
    }
    this.session.setLoginForeground(true);
    if (wasForeground) { return; }
    const url: string = this.safeCurrentURL();
    if (url !== this.documentReadyURL) { return; }
    if (QMPlusAuthNavigationPolicy.isVerificationPage(url) && this.authNonce.length > 0) {
      if (this.authHelperInstalled && url === this.authURL) {
        void this.runVerificationInspection(this.authPresentationRevision, this.pageRevision, url, this.authNonce, true);
      } else { this.requireManualAuth(''); }
      return;
    }
    if (QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url) && this.authNonce.length > 0) {
      if (this.authLedger.isActive() && this.authHelperInstalled && url === this.authURL) {
        // Same document and same once-only claims; only the local authorization
        // is captured afresh. Never reinstall the immutable helper or begin().
        void this.runAuth(this.authPresentationRevision, this.pageRevision, url, this.authNonce, true);
      } else { this.requireManualAuth(''); }
      return;
    }
    this.pageEnded(url);
  }

  private cancelAuthDelay(): void {
    if (this.authTimer >= 0) {
      clearTimeout(this.authTimer);
      this.authTimer = -1;
    }
    const resolve: (() => void) | null = this.resolveAuthDelay;
    this.resolveAuthDelay = null;
    if (resolve !== null) { resolve(); }
  }

  private invalidateAuth(): void {
    this.authPresentationRevision++;
    this.authNonce = '';
    this.authURL = '';
    this.authHelperInstalled = false;
    this.authLedger.beginDocument();
    if (this.authLedger.isActive()) { this.authStatus = ''; }
    this.cancelAuthDelay();
  }

  private ownsLoginPresentation(): boolean {
    return this.mounted && this.session.isFeatureEnabled && this.loginOwner !== null && this.session.isLoginOwnerCurrent(this.loginOwner);
  }

  private sameOwnedPage(owner: number, page: number, url: string): boolean {
    return this.ownsLoginPresentation() && this.loginOwner !== null && this.session.isOfficialWebReady(this.loginOwner) &&
      this.authForeground && this.session.loginForeground &&
      owner === this.authPresentationRevision &&
      page === this.pageRevision && url === this.safeCurrentURL();
  }

  private async ensureAuthAuthorization(owner: number, page: number, url: string): Promise<boolean> {
    if (!this.sameOwnedPage(owner, page, url) || !this.authLedger.isActive() || this.model.isSampleMode()) { return false; }
    if (this.authAuthorization !== null) {
      if (this.session.isAuthorizationCurrent(this.authAuthorization)) { return true; }
      this.requireManualAuth('');
      return false;
    }
    const loginOwner: QMPlusLoginOwner | null = this.loginOwner;
    if (loginOwner === null) { return false; }
    const authorization: QMPlusLoginAuthorization | null = await this.session.captureLoginAuthorization(loginOwner);
    if (!this.sameOwnedPage(owner, page, url) || !this.authLedger.isActive()) { return false; }
    if (authorization === null || !this.session.isAuthorizationCurrent(authorization)) {
      this.requireManualAuth('');
      return false;
    }
    this.authAuthorization = authorization;
    return true;
  }

  private requireManualAuth(reason: string): void {
    if (!this.ownsLoginPresentation()) { return; }
    this.authLedger.stop();
    this.authAuthorization = null;
    this.invalidateAuth();
    this.authStatus = this.manualAuthStatus(reason);
    this.session.deferManualLogin();
  }

  private async waitForAuthStep(delayMillis: number = 250): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      this.resolveAuthDelay = resolve;
      this.authTimer = setTimeout((): void => {
        this.authTimer = -1;
        this.resolveAuthDelay = null;
        resolve();
      }, delayMillis);
    });
  }

  private sameAuthPage(owner: number, page: number, url: string, nonce: string): boolean {
    if (!this.sameOwnedPage(owner, page, url) || !this.authLedger.isActive() ||
      this.model.isSampleMode() || nonce.length === 0 || nonce !== this.authNonce ||
      url !== this.authURL || !QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url)) { return false; }
    if (this.authAuthorization === null || !this.session.isAuthorizationCurrent(this.authAuthorization)) {
      this.requireManualAuth('');
      return false;
    }
    return true;
  }

  private contextGuard(): string {
    return 'location.origin === "https://qmplus.qmul.ac.uk" && ' +
      '/^\\/(?:my\\/|course\\/|mod\\/assign\\/|mod\\/quiz\\/|calendar\\/)/.test(location.pathname)';
  }

  private cancelWebFlight(): void {
    if (!QMPlusURLPolicy.isBusinessPage(this.safeCurrentURL())) { return; }
    const script: string = '(function(){if(!(' + this.contextGuard() +
      '))return; if(typeof globalThis.WTSQmCancel==="function") globalThis.WTSQmCancel();})()';
    void this.controller.runJavaScript(script).catch((): void => {});
  }

  private cancelDelay(): void {
    if (this.delayTimer >= 0) {
      clearTimeout(this.delayTimer);
      this.delayTimer = -1;
    }
    const resolve: (() => void) | null = this.resolveDelay;
    this.resolveDelay = null;
    if (resolve !== null) { resolve(); }
  }

  private async waitForPoll(): Promise<void> {
    await new Promise<void>((resolve: () => void): void => {
      this.resolveDelay = resolve;
      this.delayTimer = setTimeout((): void => {
        this.delayTimer = -1;
        this.resolveDelay = null;
        resolve();
      }, 250);
    });
  }

  private samePage(owner: number, generation: number): boolean {
    return this.ownsLoginPresentation() && owner === this.pageRevision && this.session.isCurrent(generation) &&
      QMPlusURLPolicy.isBusinessPage(this.safeCurrentURL());
  }

  private decodeJSString(value: string | null): string {
    if (typeof value !== 'string') { return ''; }
    if (value.length > QMPlusSnapshotParser.maximumBytes * 2 + 1024) {
      throw new Error('QMplus 快照超过安全大小上限。');
    }
    if (value.startsWith('"')) {
      try {
        const parsed: Object = JSON.parse(value) as Object;
        if (typeof parsed === 'string') { return parsed as string; }
      } catch (e) {}
    }
    return value;
  }

  private async loadSharedScript(): Promise<string> {
    const bytes: Uint8Array = await AppContext.get().resourceManager.getRawFileContent('qmplus-sync.js');
    if (bytes.length === 0 || bytes.length > 128 * 1024) {
      throw new Error('QMplus 同步脚本未能安全加载。');
    }
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  private authContextGuard(): string {
    return 'location.origin==="https://login.microsoftonline.com"&&window.top===window&&' +
      '/^\\/(?:569df091-b013-40e3-86ee-bd9cb9e25814\\/(?:saml2|login)|kmsi)$/.test(location.pathname)';
  }

  private decodeAuthReply(raw: string | null): string {
    if (typeof raw !== 'string' || raw.length > 2048) { return ''; }
    if (!raw.startsWith('"')) { return raw; }
    try {
      const value: Object = JSON.parse(raw) as Object;
      return typeof value === 'string' && (value as string).length <= 1024 ? value as string : '';
    } catch (e) { return ''; }
  }

  private async loadAuthScript(): Promise<string> {
    const bytes: Uint8Array = await AppContext.get().resourceManager.getRawFileContent('qmplus-auth.js');
    if (bytes.length === 0 || bytes.length > 32 * 1024) { throw new Error('AUTH_SCRIPT_UNAVAILABLE'); }
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  private async inspectAuth(owner: number, page: number, url: string, nonce: string,
    accountHint: string = ''): Promise<QMPlusAuthInspection | null> {
    if (!this.sameAuthPage(owner, page, url, nonce)) { return null; }
    const script: string = '(function(){if(!(' + this.authContextGuard() +
      ')||location.href!==' + JSON.stringify(url) + ')return "{}";if(typeof globalThis.WTSQmAuth!=="object")return "{}";' +
      'return JSON.stringify(globalThis.WTSQmAuth.inspect(' + JSON.stringify(nonce) + ',' +
      JSON.stringify(accountHint) + ',' + JSON.stringify(this.authLedger.identityAcknowledged(nonce)) + '));})()';
    const raw: string = this.decodeAuthReply(await this.controller.runJavaScript(script));
    return this.sameAuthPage(owner, page, url, nonce) ? QMPlusAuthInspection.parse(raw, nonce) : null;
  }

  private async fillAuth(owner: number, page: number, url: string, nonce: string,
    account: string, password: string | null, stage: string = 'username'): Promise<string> {
    if (!this.sameAuthPage(owner, page, url, nonce)) { return 'MANUAL_REQUIRED'; }
    if (/^https:\/\/login\.microsoftonline\.com\/kmsi(?:\?|$)/.test(url) && stage !== 'continue') { return 'MANUAL_REQUIRED'; }
    if ((stage === 'account' || stage === 'continue') && password !== null) { return 'MANUAL_REQUIRED'; }
    // 用户名阶段的 JSON 对象不含 password 字段；密码只在 fresh ASSET 授权与
    // 同document accountMatch后构造一次性脚本，绝不通过 JS proxy 暴露。
    const request: QMPlusAuthUsernameRequest | QMPlusAuthPasswordRequest | QMPlusAuthAccountRequest | QMPlusAuthContinueRequest =
      stage === 'continue' ? new QMPlusAuthContinueRequest(nonce, account, this.authLedger.identityAcknowledged(nonce)) :
        stage === 'account' ? new QMPlusAuthAccountRequest(nonce, account) : password === null ?
          new QMPlusAuthUsernameRequest(nonce, account) :
          new QMPlusAuthPasswordRequest(nonce, account, password, this.authLedger.identityAcknowledged(nonce));
    const script: string = '(function(){if(!(' + this.authContextGuard() +
      ')||location.href!==' + JSON.stringify(url) + ')return "MANUAL_REQUIRED";if(typeof globalThis.WTSQmAuth!=="object")return "MANUAL_REQUIRED";' +
      'return globalThis.WTSQmAuth.fillAndSubmit(' + JSON.stringify(request) + ');})()';
    // ArkWeb 异常可能携带脚本文本；调用方只呈现固定本地文案，不记录异常。
    const code: string = this.decodeAuthReply(await this.controller.runJavaScript(script));
    return this.sameAuthPage(owner, page, url, nonce) &&
      ['ACCOUNT_SELECTED', 'USERNAME_SUBMITTED', 'PASSWORD_SUBMITTED', 'CONTINUE_SUBMITTED', 'MANUAL_REQUIRED', 'REJECTED',
        'STALE_DOCUMENT'].includes(code) ? code : 'MANUAL_REQUIRED';
  }

  private manualAuthStatus(reason: string): string {
    if (reason === 'MFA_REQUIRED' || reason === 'CAPTCHA_REQUIRED') { return '请在官方窗口完成验证码或 MFA，完成后将继续同步。'; }
    if (reason === 'ACCOUNT_CHOOSER') { return '请在官方网页手动选择登录账户。'; }
    if (reason === 'ACCOUNT_MISMATCH') { return '当前官方账号与保存的账号不一致，请手动登录。'; }
    return '自动登录已暂停，可选择“手动继续”查看官方页面。';
  }

  private async runAuth(owner: number, page: number, url: string, nonce: string,
    resumeDocument: boolean = false): Promise<void> {
    try {
      if (!await this.ensureAuthAuthorization(owner, page, url)) { return; }
      const authorization: QMPlusLoginAuthorization | null = this.authAuthorization;
      if (authorization === null) { return; }
      if (!resumeDocument) {
        const source: string = await this.loadAuthScript();
        if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
        const installed: string = this.decodeAuthReply(await this.controller.runJavaScript(
          'if(' + this.authContextGuard() + '&&location.href===' + JSON.stringify(url) + '){\n' +
          source + '\n}else "STALE_DOCUMENT";'));
        if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
        if (installed !== 'AUTH_INSTALLED') {
          this.requireManualAuth('');
          return;
        }
        this.authHelperInstalled = true;
      }
      let account: string | null = resumeDocument ? await this.session.authorizedAccountHint(authorization) : null;
      if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
      if (resumeDocument && account === null) { this.requireManualAuth(''); return; }
      let afterUsername: boolean = this.authLedger.usernameSubmitted(nonce);
      let afterAccount: boolean = this.authLedger.accountSelected(nonce);
      let afterPassword: boolean = this.authLedger.passwordAttempted();
      let passwordSubmittedHere: boolean = false;
      let afterContinue: boolean = false;
      let initialChooserChecks: number = 0;
      const transition: QMPlusAuthTransitionState = new QMPlusAuthTransitionState(this.authLedger, nonce);
      let deadline: number = Date.now() + 4500;
      while (this.sameAuthPage(owner, page, url, nonce) && Date.now() < deadline) {
        const state: QMPlusAuthInspection | null = await this.inspectAuth(owner, page, url, nonce,
          account ?? '');
        if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
        if (state === null) { this.requireManualAuth(''); return; }
        if (state.stage === 'challenge') {
          this.authStatus = this.manualAuthStatus(state.reason);
          this.session.presentVerification();
          await this.waitForAuthStep(750);
          deadline = Date.now() + 4500;
          continue;
        }
        this.session.resumeAutomaticLogin();
        if (this.authLedger.continueAttempted() && ['account', 'username', 'password'].includes(state.stage)) {
          this.requireManualAuth(''); return;
        }
        if (/^https:\/\/login\.microsoftonline\.com\/kmsi(?:\?|$)/.test(url) &&
          ['account', 'username', 'password'].includes(state.stage)) { this.requireManualAuth(''); return; }
        if (state.stage === 'loading') { await this.waitForAuthStep(); continue; }
        if (state.stage === 'manual' && state.reason === 'ACCOUNT_CHOOSER' &&
          this.authLedger.canWaitForInitialAccountChoice(initialChooserChecks)) {
          initialChooserChecks++;
          await this.waitForAuthStep(initialChooserChecks === 1 ? 250 : 500);
          continue;
        }
        if (!afterUsername && !afterAccount && !afterContinue && state.stage === 'manual' &&
          ['KNOWN_FORM_ABSENT', 'FORM_UNTRUSTED'].includes(state.reason)) {
          // First layout can trail onPageEnd. Waiting never submits a credential.
          await this.waitForAuthStep();
          continue;
        }
        if (account === null && (['username', 'password', 'continue'].includes(state.stage) || state.reason === 'ACCOUNT_MISMATCH' ||
          (state.stage === 'account' && state.reason === 'ACCOUNT_HINT_REQUIRED' && !state.accountMatch))) {
          account = await this.session.authorizedAccountHint(authorization);
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (account === null) { this.requireManualAuth(''); return; }
          continue;
        }
        if (account !== null && state.stage === 'account' && state.reason === 'READY' && state.accountMatch) {
          const freshAccount: string | null = await this.session.authorizedAccountHint(authorization);
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (freshAccount === null || freshAccount.trim().toLowerCase() !== account.trim().toLowerCase() ||
            !this.authLedger.claimAccount(nonce, state.accountMatch)) { this.requireManualAuth(''); return; }
          const code: string = await this.fillAuth(owner, page, url, nonce, freshAccount, null, 'account');
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (!this.authLedger.recordAccountSelection(nonce, code)) { this.requireManualAuth(''); return; }
          afterAccount = true;
          transition.beginSettling();
          this.authStatus = '';
          await this.waitForAuthStep();
          continue;
        }
        if (account !== null && state.stage === 'username' && state.reason === 'READY' &&
          this.authLedger.claimUsername(nonce)) {
          const code: string = await this.fillAuth(owner, page, url, nonce, account, null);
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (!this.authLedger.recordUsernameSubmission(nonce, code)) { this.requireManualAuth(''); return; }
          afterUsername = true;
          // Restore the ledger's first ACK deadline rather than a loop-local
          // zero (or a fresh budget on every foreground callback).
          transition.restoreUsernameBudget();
          this.authStatus = '';
          await this.waitForAuthStep();
          continue;
        }
        if (account !== null && state.stage === 'password' && !afterPassword && state.accountMatch &&
          (state.reason === 'READY' || (state.reason === 'CURRENT_ACCOUNT_VERIFIED' &&
            this.authLedger.acknowledgeCurrentAccount(nonce, state.accountMatch))) && this.authLedger.identityAcknowledged(nonce)) {
          const password: string | null = await this.session.authorizedPasswordFor(account, authorization);
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (password === null || !this.authLedger.claimPassword(nonce, state.accountMatch)) {
            this.requireManualAuth(''); return;
          }
          const code: string = await this.fillAuth(owner, page, url, nonce, account, password);
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (code === 'PASSWORD_SUBMITTED') {
            this.authStatus = '';
            afterPassword = true;
            passwordSubmittedHere = true;
            transition.beginSettling();
            await this.waitForAuthStep();
            continue;
          } else { this.requireManualAuth(''); }
          return;
        }
        if (account !== null && state.stage === 'continue' && state.accountMatch &&
          (state.reason === 'READY' || (state.reason === 'CURRENT_ACCOUNT_VERIFIED' &&
            this.authLedger.acknowledgeCurrentAccount(nonce, state.accountMatch))) &&
          this.authLedger.claimContinue(nonce, state.accountMatch)) {
          const code: string = await this.fillAuth(owner, page, url, nonce, account, null, 'continue');
          if (!this.sameAuthPage(owner, page, url, nonce)) { return; }
          if (code !== 'CONTINUE_SUBMITTED') { this.requireManualAuth(''); return; }
          afterContinue = true;
          transition.beginSettling();
          this.authStatus = '';
          await this.waitForAuthStep();
          continue;
        }
        if (afterAccount && this.authLedger.accountSelected(nonce) && !this.authLedger.passwordAttempted() &&
          state.stage === 'manual' && state.reason === 'ACCOUNT_CHOOSER' && transition.isWithinBudget()) {
          await this.waitForAuthStep();
          continue;
        }
        if ((passwordSubmittedHere || afterContinue) && state.stage === 'manual' && state.reason === 'INTERFERENCE' &&
          transition.isWithinBudget()) {
          await this.waitForAuthStep();
          continue;
        }
        if (transition.canWait(state.reason, afterUsername || afterAccount || afterPassword || afterContinue)) {
          await this.waitForAuthStep();
          continue;
        }
        this.requireManualAuth(state.reason);
        return;
      }
      if (this.sameAuthPage(owner, page, url, nonce)) { this.requireManualAuth(''); }
    } catch (e) {
      if (this.sameAuthPage(owner, page, url, nonce)) {
        // 不展示 ArkWeb 异常：它可能包含带密码的脚本或官方会话地址。
        this.requireManualAuth('');
      }
    }
  }

  private async runSync(): Promise<void> {
    if (!this.ownsLoginPresentation()) { return; }
    if (!QMPlusURLPolicy.isBusinessPage(this.safeCurrentURL())) {
      this.session.error = '请先在官方 QMplus 网页完成登录。';
      return;
    }
    const page: number = this.pageRevision;
    const authOwner: number = this.authPresentationRevision;
    const url: string = this.safeCurrentURL();
    try {
      const authenticated: string = await this.inspectQMPage(authOwner, page, url);
      if (!this.sameOwnedPage(authOwner, page, url)) { return; }
      if (authenticated === 'error') {
        if (this.loginOwner !== null) { this.session.noteOfficialPageError(this.loginOwner); }
        this.requireManualAuth('UNSUPPORTED_PAGE'); return;
      }
      if (authenticated !== 'authenticated') {
        this.session.errorCode = 'QM_LOGIN_REQUIRED';
        this.session.error = '请先在官方 QMplus 网页完成登录。';
        this.session.deferManualLogin();
        this.autoSyncPending = true;
        return;
      }
    } catch (e) {
      if (this.sameOwnedPage(authOwner, page, url)) { this.session.deferManualLogin(); }
      return;
    }
    const generation: number = this.session.beginSync();
    if (generation < 0) { return; }
    const owner: number = this.pageRevision;
    try {
      const source: string = await this.loadSharedScript();
      if (!this.samePage(owner, generation)) { return; }
      const start: string = '(function(){if(!(' + this.contextGuard() +
        '))return "QM_CONTEXT_REJECTED";' + source +
        ';if(typeof globalThis.WTSQmSync!=="function")return "QM_SCRIPT_UNAVAILABLE";' +
        'globalThis.__wtsQmResult=undefined;' +
        'globalThis.WTSQmSync().then(function(snapshot){var raw=JSON.stringify(snapshot);' +
        'globalThis.__wtsQmResult=(new TextEncoder().encode(raw).length<=524288)?raw:' +
        'JSON.stringify({schema_version:1,source:"qmplus",ok:false,error_code:"QM_SNAPSHOT_TOO_LARGE",' +
        'partial:false,courses:[],activities:[],warnings:[]});}).catch(function(){' +
        'globalThis.__wtsQmResult=JSON.stringify({schema_version:1,source:"qmplus",ok:false,' +
        'error_code:"QM_SYNC_FAILED",partial:false,courses:[],activities:[],warnings:[]});});' +
        'return "QM_STARTED";})()';
      const started: string = this.decodeJSString(await this.controller.runJavaScript(start));
      if (!this.samePage(owner, generation)) { return; }
      if (started !== 'QM_STARTED') { throw new Error('QMplus 同步未能启动。'); }
      const deadline: number = Date.now() + 125 * 1000;
      const poll: string = '(function(){if(!(' + this.contextGuard() +
        '))return "QM_CONTEXT_REJECTED";var raw=globalThis.__wtsQmResult;' +
        'if(typeof raw!=="string")return "";delete globalThis.__wtsQmResult;return raw;})()';
      while (this.samePage(owner, generation) && Date.now() < deadline) {
        const raw: string = this.decodeJSString(await this.controller.runJavaScript(poll));
        if (!this.samePage(owner, generation)) { return; }
        if (raw === 'QM_CONTEXT_REJECTED') { throw new Error('QMplus 页面已离开官方课程区域。'); }
        if (raw.length > 0) {
          if (raw.length > QMPlusSnapshotParser.maximumBytes) {
            throw new Error('QMplus 快照超过安全大小上限。');
          }
          this.session.completeSync(generation, raw);
          if (this.session.errorCode === 'QM_LOGIN_REQUIRED') { this.autoSyncPending = true; }
          return;
        }
        await this.waitForPoll();
      }
      if (this.samePage(owner, generation)) {
        this.cancelWebFlight();
        this.session.failSync(generation, 'QMplus 同步已超时，请稍后重试。');
      }
    } catch (e) {
      if (this.samePage(owner, generation)) {
        // ArkWeb 的原始异常可能附带带 sesskey 的请求 URL 或执行脚本文本。
        this.session.failSync(generation, 'QMplus 同步失败。');
      }
    }
  }

  private pageBegan(url: string): void {
    if (!this.ownsLoginPresentation()) { return; }
    this.session.resumeAutomaticLogin();
    this.documentReadyURL = '';
    if (this.loginOwner !== null) { this.session.noteOfficialPageLoading(this.loginOwner, true); }
    this.invalidateAuth();
    if (url === 'about:blank') { this.pageRevision++; return; }
    if (QMPlusAuthNavigationPolicy.isMicrosoftTransitPage(url) && this.authLedger.isActive()) {
      this.session.waitForMicrosoftTransit();
    }
    if (this.session.autoFillEnabled && !QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url) &&
      !QMPlusAuthNavigationPolicy.isVerificationPage(url) &&
      !QMPlusAuthNavigationPolicy.isMicrosoftTransitPage(url) &&
      !QMPlusAuthNavigationPolicy.isOfficialQMPage(url) &&
      url !== QMPlusAuthNavigationPolicy.qmSAMLStart && !QMPlusURLPolicy.isBusinessPage(url)) {
      this.requireManualAuth('');
    }
    this.session.noteWebLoaded();
    if (!this.session.explicitDetailRequest && (this.session.snapshot === null || !QMPlusURLPolicy.isBusinessPage(url))) {
      this.autoSyncPending = true;
    }
    this.pageRevision++;
    this.cancelDelay();
    this.session.cancelSync();
  }

  private async maybeStartSAML(owner: number, page: number, url: string): Promise<void> {
    if (this.model.isSampleMode() || this.authSAMLStarted || !this.authLedger.isActive() || this.authLedger.credentialsAttempted()) {
      this.session.deferManualLogin(); return;
    }
    // 冷启恢复匹配授权可能仍在ASSET/Preferences读取中；等待本机读取，
    // 不因页面先加载完就静默错过这一次用户主动连接。
    await this.session.restoreSavedLoginStatus();
    if (!this.mounted || owner !== this.authPresentationRevision || page !== this.pageRevision ||
      this.model.isSampleMode() || !QMPlusAuthNavigationPolicy.shouldStartSAML(
        url, this.safeCurrentURL(), this.session.loginVisible,
      this.session.autoFillEnabled, this.authSAMLStarted)) { return; }
    if (!await this.ensureAuthAuthorization(owner, page, url)) { return; }
    const source: string = await this.loadPageScript();
    if (!this.sameOwnedPage(owner, page, url)) { return; }
    const approved: string = this.decodeAuthReply(await this.controller.runJavaScript(
      '(function(){if(location.href!==' + JSON.stringify(url) + ')return false;const kind=' + source +
      ';if(kind!=="guest")return "none";const saml=' + JSON.stringify(QMPlusAuthNavigationPolicy.qmSAMLStart) +
      ',login=' + JSON.stringify(QMPlusAuthNavigationPolicy.qmLoginPage) +
      ';const targets=new Set(Array.from(document.querySelectorAll("a[href]")).flatMap(a=>{' +
      'try{const u=new URL(a.getAttribute("href"),location.href);return u.origin==="https://qmplus.qmul.ac.uk"&&[saml,login].includes(u.href)' +
      '&&!u.username&&!u.password&&!u.search&&!u.hash?[u.href]:[];}catch{return[];}}));return targets.has(saml)?"saml":targets.has(login)?"login":"none";})()'));
    if (!this.sameOwnedPage(owner, page, url)) { return; }
    if (!['saml', 'login'].includes(approved) || (approved === 'login' && (this.authPlainLoginStarted || url === QMPlusAuthNavigationPolicy.qmLoginPage))) {
      this.requireManualAuth(''); return;
    }
    if (!await this.ensureAuthAuthorization(owner, page, url)) { return; }
    if (approved === 'saml') { this.authSAMLStarted = true; } else { this.authPlainLoginStarted = true; }
    try {
      // 不附带账号、密码或任意网页提供的查询参数。
      this.controller.loadUrl(approved === 'saml' ? QMPlusAuthNavigationPolicy.qmSAMLStart : QMPlusAuthNavigationPolicy.qmLoginPage);
    } catch (e) {
      if (owner === this.authPresentationRevision) { this.requireManualAuth(''); }
    }
  }

  private pageEnded(url: string): void {
    if (!this.ownsLoginPresentation() || url !== this.safeCurrentURL()) { return; }
    this.documentReadyURL = url;
    if (this.loginOwner !== null) { this.session.noteOfficialPageLoading(this.loginOwner, false); }
    if (url === 'about:blank') {
      void this.preparePersistentProfile(this.authPresentationRevision, this.pageRevision);
      return;
    }
    if (!this.authForeground || !this.session.loginForeground) { return; }
    if (QMPlusAuthNavigationPolicy.isOfficialQMPage(url)) {
      void this.handleQMPage(this.authPresentationRevision, this.pageRevision, url);
      return;
    }
    if (!this.model.isSampleMode() && QMPlusAuthNavigationPolicy.isVerificationPage(url)) {
      if (this.authNonce.length > 0) { return; }
      try {
        this.authNonce = newQMPlusRecordID();
        this.authURL = url;
        void this.runVerificationInspection(this.authPresentationRevision, this.pageRevision, url, this.authNonce);
      } catch (e) { this.requireManualAuth(''); }
      return;
    }
    if (!this.model.isSampleMode() && QMPlusAuthNavigationPolicy.isKnownMicrosoftPage(url)) {
      void this.startMicrosoftAuthAfterRestore(this.authPresentationRevision, this.pageRevision, url);
      return;
    }
    if (QMPlusAuthNavigationPolicy.isMicrosoftTransitPage(url)) {
      // Unknown official Microsoft documents are transport only. Wait for
      // navigation without injecting or reading any saved credential.
      if (this.authLedger.isActive()) { this.session.waitForMicrosoftTransit(); }
      return;
    }
    if (this.session.autoFillEnabled) { this.requireManualAuth(''); }
  }

  private async startMicrosoftAuthAfterRestore(owner: number, page: number, url: string): Promise<void> {
    // A cookie can redirect straight to Microsoft before the local ASSET and
    // authorization journal finish loading. Re-check this exact document once
    // restoration completes; another page/end callback may already own it.
    await this.session.restoreSavedLoginStatus();
    if (!this.sameOwnedPage(owner, page, url) || this.documentReadyURL !== url ||
      this.model.isSampleMode() || this.authNonce.length > 0) { return; }
    if (!this.session.autoFillEnabled || !this.authLedger.isActive()) { this.session.deferManualLogin(); return; }
    try {
      const nonce: string = newQMPlusRecordID();
      this.authNonce = nonce;
      this.authLedger.beginDocument(nonce);
      this.authURL = url;
      await this.runAuth(owner, page, url, nonce);
    } catch (e) {
      if (this.sameOwnedPage(owner, page, url)) { this.requireManualAuth(''); }
    }
  }

  private sameVerificationPage(owner: number, page: number, url: string, nonce: string): boolean {
    return this.sameOwnedPage(owner, page, url) && !this.model.isSampleMode() && nonce.length > 0 &&
      nonce === this.authNonce && url === this.authURL && QMPlusAuthNavigationPolicy.isVerificationPage(url);
  }

  private async runVerificationInspection(owner: number, page: number, url: string, nonce: string,
    resumeDocument: boolean = false): Promise<void> {
    const guard: string = 'window.top===window&&location.origin==="https://login.microsoftonline.com"&&' +
      'location.pathname.toLowerCase()==="/common/deviceauthtls/reprocess"&&location.href===' + JSON.stringify(url);
    try {
      if (!this.sameVerificationPage(owner, page, url, nonce)) { return; }
      if (!resumeDocument) {
        const source: string = await this.loadAuthScript();
        if (!this.sameVerificationPage(owner, page, url, nonce)) { return; }
        const installed: string = this.decodeAuthReply(await this.controller.runJavaScript(
          'if(' + guard + '){\n' + source + '\n}else "STALE_DOCUMENT";'));
        if (!this.sameVerificationPage(owner, page, url, nonce)) { return; }
        if (installed !== 'AUTH_INSTALLED') { this.requireManualAuth(''); return; }
        this.authHelperInstalled = true;
      }
      let deadline: number = Date.now() + 4500;
      while (this.sameVerificationPage(owner, page, url, nonce) && Date.now() < deadline) {
        const raw: string = this.decodeAuthReply(await this.controller.runJavaScript(
          '(function(){if(!(' + guard + '))return "{}";return JSON.stringify(WTSQmAuth.inspect(' + JSON.stringify(nonce) + ',""));})()'));
        if (!this.sameVerificationPage(owner, page, url, nonce)) { return; }
        const state: QMPlusAuthInspection | null = QMPlusAuthInspection.parse(raw, nonce);
        if (state?.stage === 'challenge') {
          this.authStatus = this.manualAuthStatus(state.reason);
          this.session.presentVerification();
          await this.waitForAuthStep(750);
          deadline = Date.now() + 4500;
        } else if (state?.stage === 'loading' && state.reason === 'LOADING') {
          this.session.resumeAutomaticLogin();
          await this.waitForAuthStep();
        } else { this.requireManualAuth(''); return; }
      }
      if (this.sameVerificationPage(owner, page, url, nonce)) { this.requireManualAuth(''); }
    } catch (e) {
      if (this.sameVerificationPage(owner, page, url, nonce)) { this.requireManualAuth(''); }
    }
  }

  private async handleQMPage(owner: number, page: number, url: string): Promise<void> {
    try {
      const kind: string = await this.inspectQMPage(owner, page, url);
      if (!this.sameOwnedPage(owner, page, url)) { return; }
      if (kind === 'error') {
        if (this.loginOwner !== null) { this.session.noteOfficialPageError(this.loginOwner); }
        this.requireManualAuth('UNSUPPORTED_PAGE'); return;
      }
      if (kind === 'guest' && QMPlusAuthNavigationPolicy.isQMGuestEntry(url)) {
        await this.maybeStartSAML(owner, page, url); return;
      }
      if (kind === 'authenticated' && QMPlusAuthNavigationPolicy.isQMLoginLanding(url) && !this.dashboardRestored) {
        this.dashboardRestored = true; this.controller.loadUrl(QMPlusURLPolicy.home); return;
      }
      if (kind !== 'authenticated') {
        if (url !== QMPlusAuthNavigationPolicy.qmSAMLStart) { this.session.deferManualLogin(); }
        return;
      }
      if (this.loginOwner !== null) {
        await this.session.flushOfficialWeb(this.loginOwner);
        if (!this.sameOwnedPage(owner, page, url)) { return; }
      }
      this.authStatus = '';
      if (this.session.explicitDetailRequest) {
        if (url === QMPlusURLPolicy.home && !this.detailTargetRestored) { await this.restoreExplicitDetailAfterLogin(page, url); }
      } else if (this.autoSyncPending && QMPlusURLPolicy.isBusinessPage(url)) {
        this.autoSyncPending = false; await this.runSync();
      }
    } catch (e) { if (this.sameOwnedPage(owner, page, url)) { this.session.deferManualLogin(); } }
  }

  private close(): void {
    if (!this.ownsLoginPresentation()) { return; }
    this.invalidateAuth();
    this.authLedger.stop();
    this.authAuthorization = null;
    this.cancelWebFlight();
    this.cancelDelay();
    this.session.closeLogin();
  }

  private async restoreExplicitDetailAfterLogin(page: number, url: string): Promise<void> {
    try {
      const authenticated: string = await this.inspectQMPage(this.authPresentationRevision, page, url);
      if (!this.ownsLoginPresentation() || !this.session.explicitDetailRequest ||
        page !== this.pageRevision || this.safeCurrentURL() !== url || authenticated !== 'authenticated' ||
        this.detailTargetRestored || !QMPlusURLPolicy.isBusinessPage(this.session.targetURL)) { return; }
      this.detailTargetRestored = true;
      this.controller.loadUrl(this.session.targetURL);
    } catch (e) {
      if (this.ownsLoginPresentation() && page === this.pageRevision && this.safeCurrentURL() === url) {
        this.session.deferManualLogin();
      }
    }
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button(this.model.text('返回'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .id('qmplus.login.close')
          .onClick(() => this.close())
        Text('QMplus')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        if (this.session.errorCode === 'QM_ERROR_PAGE' || this.session.errorCode === 'QM_WEB_CLEAR_PENDING') {
          Button(this.model.text('连接 QMplus'))
            .height(ControlMetrics.height)
            .onClick(() => this.session.openLogin())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      Text(this.model.text('仅在官方网页完成 SSO/MFA；只有您主动保存时，本机系统安全存储才保存独立的 QMplus 登录资料。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      if (this.session.autoFillEnabled) {
        Text(this.model.text(this.authStatus.length > 0 ? this.authStatus :
          '已保存的账号和密码用于自动完成官方登录；只有验证码或 MFA 需要您操作。未知页面会暂停，可手动继续。'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
          .id('qmplus.login.auth-status')
      }
      if (this.session.error.length > 0) {
        Text(this.model.text(this.session.error) + (this.session.errorCode.length > 0 &&
          this.session.errorCode !== 'QM_LOGIN_REQUIRED' ? ' (' + this.session.errorCode + ')' : ''))
          .fontSize(12)
          .fontColor(AppTheme.danger())
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }
      // API24's app-wide normal profile is reserved for QMplus by policy.
      // A pending durable fence is resolved on a non-network blank page first.
      Web({ src: 'about:blank', controller: this.controller, incognitoMode: QMPlusWebProfileStore.incognitoMode })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .mixedMode(MixedMode.None)
        .allowWindowOpenMethod(false)
        .onOverrideUrlLoading((request) => request.isMainFrame() &&
          !(request.getRequestUrl() === 'about:blank' && !this.session.officialWebProfileReady) &&
          !QMPlusURLPolicy.isHTTPSPage(request.getRequestUrl()))
        .onPageBegin((event) => this.pageBegan(event.url))
        .onPageEnd((event) => this.pageEnded(event.url))
        .onErrorReceive((event) => {
          if (this.ownsLoginPresentation() && event.request.isMainFrame()) {
            this.requireManualAuth('');
            this.session.error = '官方登录页面暂时无法加载，请检查网络后重试。';
          }
        })
        .id('qmplus.official.web')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
  }
}
