// QMplus 的官方 ArkWeb 会话与教务/教学云账号完全分离。
// 课程快照只在内存；只有用户显式选择保存时，Microsoft 登录资料才进入独立
// ASSET 资产，授权nonce进入非敏感偏好；Cookie/sesskey永不跨业务桥。
import { webview } from '@kit.ArkWeb';
import { QMPlusSnapshot, QMPlusSnapshotParser, QMPlusURLPolicy } from '../net/QMPlusSnapshot';
import { PreferencesStore } from '../store/PreferencesStore';
import { AssetQMPlusSavedLoginStore, newQMPlusRecordID, QMPlusSavedLogin,
  QMPlusSavedLoginStoring } from '../store/QMPlusSavedLoginStore';

export interface QMPlusAuthorizationJournal {
  getString(key: string): Promise<string | null>;
  setString(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}

// Callback identity only: these tickets never carry an account or password.
export class QMPlusLoginOwner {
  readonly sessionID: number;
  readonly presentationRevision: number;

  constructor(sessionID: number, presentationRevision: number) {
    this.sessionID = sessionID;
    this.presentationRevision = presentationRevision;
  }
}

export class QMPlusLoginAuthorization {
  readonly owner: QMPlusLoginOwner;
  readonly settingsRevision: number;
  readonly foregroundRevision: number;
  readonly recordID: string;

  constructor(owner: QMPlusLoginOwner, settingsRevision: number, foregroundRevision: number, recordID: string) {
    this.owner = owner;
    this.settingsRevision = settingsRevision;
    this.foregroundRevision = foregroundRevision;
    this.recordID = recordID;
  }
}

@ObservedV2
export class QMPlusSession {
  static readonly autoFillAuthorizationKey: string = 'qmplusAutoFillAuthorizedRecordID';
  // ArkWeb 文档要求先加载 Web 组件再调用 WebStorage；Root Session 重建不代表
  // 本进程的 incognito profile 未被使用过。
  private static ownedWebLoadedInProcess: boolean = false;
  // An incognito profile survives root/session recreation in this process,
  // though it cannot survive process death. Failed clearing fences that owner.
  // A future persistent Web profile must replace this with a durable fence.
  private static ownedWebClearPendingInProcess: boolean = false;
  private static nextSessionID: number = 0;
  private readonly sessionID: number = ++QMPlusSession.nextSessionID;
  @Trace loginVisible: boolean = false;
  @Trace isFeatureEnabled: boolean = true;
  // Mount the same ArkWeb with a real viewport during an authorized quiet flow.
  // Presentation is separate from ownership; unknown/MFA pages reveal this owner.
  @Trace loginPresented: boolean = false;
  @Trace loginForeground: boolean = true;
  @Trace explicitDetailRequest: boolean = false;
  @Trace targetURL: string = QMPlusURLPolicy.home;
  @Trace syncing: boolean = false;
  @Trace snapshot: QMPlusSnapshot | null = null;
  @Trace showingStalePartial: boolean = false;
  @Trace error: string = '';
  @Trace errorCode: string = '';
  @Trace savedLoginAvailable: boolean = false;
  @Trace autoFillEnabled: boolean = false;
  @Trace loginSettingsBusy: boolean = false;
  @Trace loginSettingsError: string = '';
  private generation: number = 0;
  private loginPresentationRevision: number = 0;
  private loginForegroundRevision: number = 0;
  private ownedWebOwner: QMPlusLoginOwner | null = null;
  private retireOwnedWeb: (() => void) | null = null;
  private restartOwnedWeb: (() => void) | null = null;
  private officialPageLoading: boolean = false;
  private readonly clearIncognitoData: () => void;
  private readonly savedLoginStore: QMPlusSavedLoginStoring;
  private readonly authorizationJournal: QMPlusAuthorizationJournal;
  private readonly recordIDFactory: () => string;
  private loginSettingsRevision: number = 0;
  private restoredLoginSettings: boolean = false;
  private loginMutation: Promise<boolean> = Promise.resolve(true);
  private quietDeadlineTimer: number = -1;

  constructor(clearIncognitoData?: () => void, savedLoginStore?: QMPlusSavedLoginStoring,
    authorizationJournal?: QMPlusAuthorizationJournal, recordIDFactory?: () => string) {
    this.clearIncognitoData = clearIncognitoData ?? ((): void => {
      webview.WebCookieManager.clearAllCookiesSync(true);
      webview.WebStorage.deleteAllData(true);
    });
    this.savedLoginStore = savedLoginStore ?? new AssetQMPlusSavedLoginStore();
    this.authorizationJournal = authorizationJournal ?? new PreferencesStore();
    this.recordIDFactory = recordIDFactory ?? ((): string => newQMPlusRecordID());
  }

  async restoreSavedLoginStatus(): Promise<void> {
    if (this.restoredLoginSettings || this.loginSettingsBusy) { return; }
    const revision: number = this.loginSettingsRevision;
    try {
      const login: QMPlusSavedLogin | null = await this.savedLoginStore.load();
      const authorization: string | null = await this.authorizationJournal.getString(
        QMPlusSession.autoFillAuthorizationKey);
      if (revision !== this.loginSettingsRevision || this.loginSettingsBusy) { return; }
      this.savedLoginAvailable = login !== null;
      this.autoFillEnabled = login !== null && authorization === login.recordID;
      this.loginSettingsError = '';
      this.restoredLoginSettings = true;
    } catch (e) {
      if (revision !== this.loginSettingsRevision) { return; }
      this.autoFillEnabled = false;
      this.loginSettingsError = '无法读取 QMplus 登录资料，自动填写已关闭。';
    }
  }

  loginOwner(): QMPlusLoginOwner {
    return new QMPlusLoginOwner(this.sessionID, this.loginPresentationRevision);
  }

  isLoginOwnerCurrent(owner: QMPlusLoginOwner): boolean {
    return this.isFeatureEnabled && this.loginVisible && owner.sessionID === this.sessionID &&
      owner.presentationRevision === this.loginPresentationRevision;
  }

  bindLoginWeb(owner: QMPlusLoginOwner, retire: () => void, restart?: () => void): void {
    if (!this.isLoginOwnerCurrent(owner)) { return; }
    this.ownedWebOwner = owner;
    this.retireOwnedWeb = retire;
    this.restartOwnedWeb = restart ?? null;
  }

  unbindLoginWeb(owner: QMPlusLoginOwner): void {
    if (this.ownedWebOwner === null || owner.sessionID !== this.ownedWebOwner.sessionID ||
      owner.presentationRevision !== this.ownedWebOwner.presentationRevision) { return; }
    this.ownedWebOwner = null;
    this.retireOwnedWeb = null;
    this.restartOwnedWeb = null;
  }

  private stopOwnedLoginWeb(): boolean {
    const retire: (() => void) | null = this.retireOwnedWeb;
    this.ownedWebOwner = null;
    this.retireOwnedWeb = null;
    this.restartOwnedWeb = null;
    if (retire === null) { return true; }
    try { retire(); return true; } catch (e) {
      QMPlusSession.ownedWebClearPendingInProcess = true;
      return false;
    }
  }

  isAuthorizationCurrent(authorization: QMPlusLoginAuthorization): boolean {
    return this.isLoginOwnerCurrent(authorization.owner) && this.autoFillEnabled &&
      this.loginForeground && !this.loginSettingsBusy &&
      authorization.foregroundRevision === this.loginForegroundRevision &&
      authorization.settingsRevision === this.loginSettingsRevision;
  }

  async captureLoginAuthorization(owner: QMPlusLoginOwner): Promise<QMPlusLoginAuthorization | null> {
    if (!this.isLoginOwnerCurrent(owner) || !this.loginForeground || !this.autoFillEnabled || this.loginSettingsBusy) { return null; }
    const settingsRevision: number = this.loginSettingsRevision;
    const foregroundRevision: number = this.loginForegroundRevision;
    try {
      const login: QMPlusSavedLogin | null = await this.savedLoginStore.load();
      const authorization: string | null = await this.authorizationJournal.getString(
        QMPlusSession.autoFillAuthorizationKey);
      if (!this.isLoginOwnerCurrent(owner) || !this.loginForeground || !this.autoFillEnabled || this.loginSettingsBusy ||
        foregroundRevision !== this.loginForegroundRevision || settingsRevision !== this.loginSettingsRevision) { return null; }
      if (login === null || authorization !== login.recordID) {
        this.autoFillEnabled = false;
        this.loginSettingsError = 'QMplus 自动填写授权与已保存资料不匹配，请在设置中重新确认。';
        return null;
      }
      return new QMPlusLoginAuthorization(owner, settingsRevision, foregroundRevision, login.recordID);
    } catch (e) {
      if (settingsRevision === this.loginSettingsRevision && foregroundRevision === this.loginForegroundRevision &&
        this.loginForeground && this.isLoginOwnerCurrent(owner)) {
        this.autoFillEnabled = false;
        this.loginSettingsError = '无法读取 QMplus 登录资料，自动填写已关闭。';
      }
      return null;
    }
  }

  private async authorizedLoginForCurrentPresentation(
    authorization: QMPlusLoginAuthorization): Promise<QMPlusSavedLogin | null> {
    if (!this.isAuthorizationCurrent(authorization)) { return null; }
    try {
      const login: QMPlusSavedLogin | null = await this.savedLoginStore.load();
      const consent: string | null = await this.authorizationJournal.getString(
        QMPlusSession.autoFillAuthorizationKey);
      if (!this.isAuthorizationCurrent(authorization)) { return null; }
      if (login === null || login.recordID !== authorization.recordID || consent !== authorization.recordID) {
        this.autoFillEnabled = false;
        this.loginSettingsError = 'QMplus 自动填写授权与已保存资料不匹配，请在设置中重新确认。';
        return null;
      }
      return login;
    } catch (e) {
      if (this.isAuthorizationCurrent(authorization)) {
        this.autoFillEnabled = false;
        this.loginSettingsError = '无法读取 QMplus 登录资料，自动填写已关闭。';
      }
      return null;
    }
  }

  async authorizedAccountHint(authorization: QMPlusLoginAuthorization): Promise<string | null> {
    const login: QMPlusSavedLogin | null = await this.authorizedLoginForCurrentPresentation(authorization);
    return login?.account ?? null;
  }

  async authorizedPasswordFor(account: string, authorization: QMPlusLoginAuthorization): Promise<string | null> {
    const login: QMPlusSavedLogin | null = await this.authorizedLoginForCurrentPresentation(authorization);
    return login !== null && login.account.toLowerCase() === account.trim().toLowerCase() ?
      login.password : null;
  }

  private async revokeBeforeRecordChange(): Promise<boolean> {
    try {
      await this.authorizationJournal.remove(QMPlusSession.autoFillAuthorizationKey);
      return true;
    } catch (e) {
      try {
        // 只要资产已移除，旧授权nonce便不再对应任何密码记录。
        await this.savedLoginStore.clear();
        this.savedLoginAvailable = false;
        return true;
      } catch (e2) {
        this.loginSettingsError = '无法确认已撤销 QMplus 自动填写；本次运行已停用，重启后请检查。';
        return false;
      }
    }
  }

  private enqueueLoginMutation(work: () => Promise<boolean>): Promise<boolean> {
    const next: Promise<boolean> = this.loginMutation.catch((): boolean => false)
      .then((_previous: boolean): Promise<boolean> => work());
    this.loginMutation = next;
    return next;
  }

  async saveSavedLogin(account: string, password: string): Promise<boolean> {
    if (this.loginSettingsBusy) { return false; }
    let login: QMPlusSavedLogin;
    let recordID: string;
    try {
      recordID = this.recordIDFactory();
    } catch (e) {
      this.loginSettingsError = '系统无法准备 QMplus 安全存储，请稍后重试。';
      return false;
    }
    try {
      login = new QMPlusSavedLogin(recordID, account, password);
    } catch (e) {
      this.loginSettingsError = '请填写有效的 QMplus 登录账号及密码。';
      return false;
    }
    const revision: number = ++this.loginSettingsRevision;
    this.loginSettingsBusy = true;
    this.autoFillEnabled = false;
    this.loginSettingsError = '';
    return this.enqueueLoginMutation(async (): Promise<boolean> => {
      if (revision !== this.loginSettingsRevision) { return false; }
      try {
        // A newly saved identity must not reuse the previous identity's cookie
        // or course snapshot, even when its official session is still valid.
        const webCleared: boolean = this.clearConnection();
        if (!await this.revokeBeforeRecordChange()) { return false; }
        if (!webCleared) { this.loginSettingsError = this.error; return false; }
        await this.savedLoginStore.save(login);
        if (revision !== this.loginSettingsRevision) { return false; }
        this.savedLoginAvailable = true;
        this.restoredLoginSettings = true;
        return true;
      } catch (e) {
        if (revision === this.loginSettingsRevision) {
          this.loginSettingsError = '无法保存 QMplus 登录资料，自动填写保持关闭。';
          try {
            this.savedLoginAvailable = (await this.savedLoginStore.load()) !== null;
          } catch (e2) {
            this.savedLoginAvailable = false;
          }
        }
        return false;
      } finally {
        if (revision === this.loginSettingsRevision) { this.loginSettingsBusy = false; }
      }
    });
  }

  async setAutoFillEnabled(enabled: boolean): Promise<boolean> {
    if (!enabled) {
      // 用户关闭意图先即时生效；持久撤销失败时宁可删除资产也不悄悄重开。
      this.autoFillEnabled = false;
      const revision: number = ++this.loginSettingsRevision;
      this.loginSettingsBusy = true;
      return this.enqueueLoginMutation(async (): Promise<boolean> => {
        try {
          const revoked: boolean = await this.revokeBeforeRecordChange();
          if (revoked && revision === this.loginSettingsRevision) { this.loginSettingsError = ''; }
          return revoked;
        } finally {
          if (revision === this.loginSettingsRevision) { this.loginSettingsBusy = false; }
        }
      });
    }
    if (this.loginSettingsBusy || !this.savedLoginAvailable) {
      this.loginSettingsError = '请先安全保存 QMplus 登录账号及密码。';
      return false;
    }
    this.loginSettingsBusy = true;
    const revision: number = ++this.loginSettingsRevision;
    this.autoFillEnabled = false;
    return this.enqueueLoginMutation(async (): Promise<boolean> => {
      if (revision !== this.loginSettingsRevision) { return false; }
      try {
        const login: QMPlusSavedLogin | null = await this.savedLoginStore.load();
        if (login === null) {
          this.savedLoginAvailable = false;
          this.loginSettingsError = '请先安全保存 QMplus 登录账号及密码。';
          return false;
        }
        await this.authorizationJournal.setString(QMPlusSession.autoFillAuthorizationKey, login.recordID);
        const verified: string | null = await this.authorizationJournal.getString(
          QMPlusSession.autoFillAuthorizationKey);
        if (revision !== this.loginSettingsRevision || verified !== login.recordID) {
          throw new Error('QMplus authorization not confirmed');
        }
        this.autoFillEnabled = true;
        this.loginSettingsError = '';
        this.restoredLoginSettings = true;
        return true;
      } catch (e) {
        this.autoFillEnabled = false;
        if (!await this.revokeBeforeRecordChange()) { return false; }
        if (revision === this.loginSettingsRevision) {
          this.loginSettingsError = '无法保存 QMplus 自动填写授权，已保持关闭。';
        }
        return false;
      } finally {
        if (revision === this.loginSettingsRevision) { this.loginSettingsBusy = false; }
      }
    });
  }

  async deleteSavedLogin(): Promise<boolean> {
    this.autoFillEnabled = false;
    const revision: number = ++this.loginSettingsRevision;
    this.loginSettingsBusy = true;
    return this.enqueueLoginMutation(async (): Promise<boolean> => {
      // 即使prefs撤销失败也继续删秘密；任一成功都能阻止旧授权复活，
      // 但用户请求“删除密码”只有 ASSET 确实删除才报告成功。
      let authorizationRevoked: boolean = false;
      try {
        await this.authorizationJournal.remove(QMPlusSession.autoFillAuthorizationKey);
        authorizationRevoked = true;
      } catch (e) {}
      try {
        await this.savedLoginStore.clear();
        if (revision === this.loginSettingsRevision) {
          this.savedLoginAvailable = false;
          this.restoredLoginSettings = true;
          this.loginSettingsError = '';
        }
        return true;
      } catch (e) {
        if (revision === this.loginSettingsRevision) {
          this.loginSettingsError = authorizationRevoked ?
            'QMplus 自动填写已关闭，但保存的密码未能确认删除，请重试。' :
            '无法确认已撤销 QMplus 自动填写或删除密码；本次运行已停用，重启后请检查。';
        }
        return false;
      } finally {
        if (revision === this.loginSettingsRevision) { this.loginSettingsBusy = false; }
      }
    });
  }

  async disconnectAndDeleteSavedLogin(): Promise<boolean> {
    const webCleared: boolean = this.logout();
    const secretCleared: boolean = await this.deleteSavedLogin();
    return webCleared && secretCleared;
  }

  // 仅测试夹具使用；不写入持久状态，也不影响普通会话。
  static resetOwnedWebLoadedForTesting(): void {
    QMPlusSession.ownedWebLoadedInProcess = false;
    QMPlusSession.ownedWebClearPendingInProcess = false;
  }

  noteWebLoaded(): void {
    QMPlusSession.ownedWebLoadedInProcess = true;
  }

  openLogin(url: string = QMPlusURLPolicy.home): void {
    if (!this.isFeatureEnabled || this.loginSettingsBusy || (QMPlusSession.ownedWebClearPendingInProcess && !this.clearOwnedWebSession())) { return; }
    if (this.loginVisible) {
      if (this.errorCode !== 'QM_ERROR_PAGE' || this.officialPageLoading) { this.presentLogin(); return; }
      const restart: (() => void) | null = this.restartOwnedWeb;
      this.closeLogin();
      this.openLogin(QMPlusURLPolicy.home);
      if (restart !== null && this.loginVisible) { restart(); }
      return;
    }
    this.loginPresentationRevision++;
    this.targetURL = QMPlusURLPolicy.isBusinessPage(url) ? url : QMPlusURLPolicy.home;
    this.explicitDetailRequest = this.targetURL !== QMPlusURLPolicy.home &&
      this.targetURL !== 'https://qmplus.qmul.ac.uk/my';
    this.loginVisible = true;
    this.loginPresented = this.explicitDetailRequest || !this.autoFillEnabled;
    if (!this.loginPresented) {
      const revision: number = this.loginPresentationRevision;
      this.quietDeadlineTimer = setTimeout((): void => {
        this.quietDeadlineTimer = -1;
        if (this.loginVisible && revision === this.loginPresentationRevision && !this.syncing) {
          this.presentLogin();
        }
      }, 25000);
    }
    this.error = '';
    this.errorCode = '';
  }

  noteOfficialPageLoading(owner: QMPlusLoginOwner, loading: boolean): void {
    if (this.isLoginOwnerCurrent(owner)) { this.officialPageLoading = loading; }
  }

  noteOfficialPageError(owner: QMPlusLoginOwner): void {
    if (!this.isLoginOwnerCurrent(owner)) { return; }
    this.cancelSync();
    this.errorCode = 'QM_ERROR_PAGE';
    this.error = 'QMplus 同步失败。';
    this.presentLogin();
  }

  closeLogin(): void {
    this.stopOwnedLoginWeb();
    this.cancelQuietDeadline();
    this.loginPresentationRevision++;
    this.cancelSync();
    this.loginVisible = false;
    this.loginPresented = false;
    this.targetURL = QMPlusURLPolicy.home;
  }

  beginSync(): number {
    if (!this.isFeatureEnabled || this.syncing) { return -1; }
    const generation: number = ++this.generation;
    this.syncing = true;
    if (!this.explicitDetailRequest) { this.loginPresented = false; }
    this.cancelQuietDeadline();
    this.error = '';
    this.errorCode = '';
    return generation;
  }

  isCurrent(generation: number): boolean {
    return this.isFeatureEnabled && generation === this.generation && this.syncing && this.loginVisible;
  }

  completeSync(generation: number, raw: string): void {
    if (!this.isCurrent(generation)) { return; }
    try {
      const next: QMPlusSnapshot = QMPlusSnapshotParser.parse(raw);
      if (next.partial && this.snapshot !== null && !this.snapshot.partial) {
        // 官方部分页面失败时不把旧完整课程误当作新抓取结果，也不清空上次完整快照。
        this.showingStalePartial = true;
      } else {
        this.snapshot = next;
        this.showingStalePartial = false;
      }
      this.error = '';
      this.errorCode = '';
    } catch (e) {
      // 部分失败保留上一份明确标注时间的快照，绝不把接口失败当空课程。
      const message: string = e instanceof Error ? e.message : 'QM_SYNC_FAILED';
      // 上游页面的 error_code 仍属未信任数据；只保留明确识别的登录状态。
      this.errorCode = message === 'QM_LOGIN_REQUIRED' || message === 'QM_ERROR_PAGE' ? message : '';
      this.error = this.errorCode === 'QM_LOGIN_REQUIRED' ? '请先在官方 QMplus 网页完成登录。' :
        'QMplus 同步失败。';
    }
    this.syncing = false;
    if (this.error.length === 0 && !this.explicitDetailRequest) { this.closeLogin(); }
    else if (this.error.length > 0) { this.presentLogin(); }
  }

  failSync(generation: number, message: string): void {
    if (!this.isCurrent(generation)) { return; }
    this.syncing = false;
    this.errorCode = '';
    // 只呈现本地固定文案，避免未来调用者把 ArkWeb 异常、URL 或令牌原文传到 UI。
    this.error = message === 'QMplus 同步已超时，请稍后重试。' ? message : 'QMplus 同步失败。';
    this.presentLogin();
  }

  cancelSync(): void {
    this.generation++;
    this.syncing = false;
  }

  setFeatureEnabled(enabled: boolean): void {
    if (enabled === this.isFeatureEnabled) { return; }
    this.isFeatureEnabled = enabled;
    // Feature Off retires in-flight owners without deleting the independently
    // saved record, incognito cookies, or the last verified business snapshot.
    if (!enabled) { this.closeLogin(); }
  }

  logout(): boolean {
    this.loginSettingsRevision++;
    this.autoFillEnabled = false;
    return this.clearConnection();
  }

  private clearConnection(): boolean {
    const webStopped: boolean = this.stopOwnedLoginWeb();
    this.cancelQuietDeadline();
    this.cancelSync();
    this.loginPresentationRevision++;
    this.loginVisible = false;
    this.loginPresented = false;
    this.targetURL = QMPlusURLPolicy.home;
    this.snapshot = null;
    this.showingStalePartial = false;
    this.error = '';
    this.errorCode = '';
    if (!webStopped) {
      this.error = 'QMplus 浏览器会话未能清除，请稍后重试。';
      return false;
    }
    return this.clearOwnedWebSession();
  }

  private clearOwnedWebSession(): boolean {
    if (!QMPlusSession.ownedWebLoadedInProcess) {
      QMPlusSession.ownedWebClearPendingInProcess = false;
      return true;
    }
    QMPlusSession.ownedWebClearPendingInProcess = true;
    try {
      // 仅清除本应用 incognito ArkWeb profile 的 Cookie；不访问系统浏览器或其它应用。
      // 当前应用只为 QMplus 使用 incognito Web；同时删除该 profile 的网页存储，
      // 清除 Microsoft SSO 页面可能留在 Web Storage 的临时身份状态。
      this.clearIncognitoData();
      QMPlusSession.ownedWebClearPendingInProcess = false;
      return true;
    } catch (e) {
      this.error = 'QMplus 浏览器会话未能清除，请稍后重试。';
      return false;
    }
  }

  dispose(): void {
    this.stopOwnedLoginWeb();
    this.cancelQuietDeadline();
    this.cancelSync();
    this.loginPresentationRevision++;
    this.loginVisible = false;
    this.loginPresented = false;
  }

  presentLogin(): void {
    if (!this.loginVisible) { return; }
    this.cancelQuietDeadline();
    this.loginPresented = true;
  }

  cancelQuietLoginOnBackground(): void {
    this.setLoginForeground(false);
    if (this.loginVisible && !this.loginPresented) { this.closeLogin(); }
  }

  setLoginForeground(foreground: boolean): void {
    if (this.loginForeground === foreground) { return; }
    this.loginForeground = foreground;
    // Preserve the visible official/MFA owner, but an old ASSET callback cannot
    // regain authority merely because the same window becomes active again.
    this.loginForegroundRevision++;
  }

  private cancelQuietDeadline(): void {
    if (this.quietDeadlineTimer >= 0) { clearTimeout(this.quietDeadlineTimer); this.quietDeadlineTimer = -1; }
  }
}
