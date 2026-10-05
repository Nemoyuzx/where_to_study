import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import { AppContext } from './AppContext';

export interface QMPlusWebProfileStoring {
  reserveWebMount(): boolean;
  noteWebLoaded(): void;
  isReady(): boolean;
  requiresRestart(): boolean;
  markClearPending(): boolean;
  hasDurableClearPending(): boolean;
  prepare(): Promise<boolean>;
  clear(): Promise<boolean>;
  flush(): Promise<boolean>;
}

// API24 has no named ArkWeb profile. The application's normal ArkWeb data area
// is exclusively QMplus; every future unrelated Web must use incognitoMode:true.
// BUPT uses native HTTP/ASSET, not this store. sharedRenderProcessToken does not
// isolate storage. No cookie/token is read, copied to JSON or sent to native DTOs.
// Only a fixed non-secret clear fence is stored in this separate Preferences
// namespace, which AppModel's general preference clearing never removes.
export class QMPlusWebProfileStore implements QMPlusWebProfileStoring {
  static readonly incognitoMode: boolean = false;
  private static initializedInProcess: boolean = false;
  private static restartRequiredInProcess: boolean = false;
  private static blockedInProcess: boolean = false;
  private static clearRevision: number = 0;
  private static clearWork: Promise<boolean> | null = null;
  private static readonly key: string = 'profileState';
  private static readonly unused: string = 'v1:unused';
  private static readonly ready: string = 'v1:ready';
  private static readonly clearUnused: string = 'v1:clear-unused';
  private static readonly clearUsed: string = 'v1:clear-used';

  private open(): preferences.Preferences {
    return preferences.getPreferencesSync(AppContext.get(), { name: 'where-to-study-qmplus-web-profile-v1' });
  }

  private read(): string {
    const store: preferences.Preferences = this.open();
    // Previous app versions used only incognito Web, so an absent record means
    // this app-owned normal profile has never been mounted by QMplus.
    if (!store.hasSync(QMPlusWebProfileStore.key)) { return QMPlusWebProfileStore.unused; }
    const value: preferences.ValueType = store.getSync(QMPlusWebProfileStore.key, 'invalid');
    if (typeof value !== 'string' || ![QMPlusWebProfileStore.unused, QMPlusWebProfileStore.ready,
      QMPlusWebProfileStore.clearUnused, QMPlusWebProfileStore.clearUsed].includes(value as string)) {
      throw new Error('QM_WEB_PROFILE_STATE_INVALID');
    }
    return value as string;
  }

  private write(value: string): void {
    const store: preferences.Preferences = this.open();
    store.putSync(QMPlusWebProfileStore.key, value);
    store.flushSync();
    if (store.getSync(QMPlusWebProfileStore.key, 'invalid') !== value) {
      throw new Error('QM_WEB_PROFILE_STATE_WRITE_FAILED');
    }
  }

  private pending(value: string): boolean {
    return value === QMPlusWebProfileStore.clearUsed || value === QMPlusWebProfileStore.clearUnused;
  }

  reserveWebMount(): boolean {
    if (QMPlusWebProfileStore.restartRequiredInProcess) { return false; }
    try {
      let state: string = this.read();
      if (QMPlusWebProfileStore.blockedInProcess && !this.pending(state)) {
        if (!this.markClearPending()) { return false; }
        state = this.read();
      }
      // Record ownership before even the quarantine about:blank Web is mounted.
      if (state === QMPlusWebProfileStore.unused) { this.write(QMPlusWebProfileStore.ready); }
      if (state === QMPlusWebProfileStore.clearUnused) { this.write(QMPlusWebProfileStore.clearUsed); }
      return true;
    } catch (e) { QMPlusWebProfileStore.blockedInProcess = true; return false; }
  }

  noteWebLoaded(): void { QMPlusWebProfileStore.initializedInProcess = true; }
  requiresRestart(): boolean { return QMPlusWebProfileStore.restartRequiredInProcess; }

  isReady(): boolean {
    try { return !QMPlusWebProfileStore.restartRequiredInProcess && !QMPlusWebProfileStore.blockedInProcess && !this.pending(this.read()); }
    catch (e) { QMPlusWebProfileStore.blockedInProcess = true; return false; }
  }

  markClearPending(): boolean {
    QMPlusWebProfileStore.clearRevision++;
    QMPlusWebProfileStore.blockedInProcess = true;
    try {
      const state: string = this.read();
      if ((state === QMPlusWebProfileStore.ready || state === QMPlusWebProfileStore.clearUsed) &&
        QMPlusWebProfileStore.initializedInProcess) {
        // stop()/component retirement is not an ACK that every in-flight HTTP
        // response can no longer write cookies. Never reuse this data area in
        // the same process after an identity change or disconnect.
        QMPlusWebProfileStore.restartRequiredInProcess = true;
      }
      this.write(state === QMPlusWebProfileStore.unused || state === QMPlusWebProfileStore.clearUnused ?
        QMPlusWebProfileStore.clearUnused : QMPlusWebProfileStore.clearUsed);
      return true;
    } catch (e) { return false; }
  }

  hasDurableClearPending(): boolean {
    try {
      const state: string = this.read();
      if (!this.pending(state)) { return false; }
      // A failed flush may leave only a cached Preferences value. Never treat
      // that cached read as a disk ACK: reflush before rotating an ASSET record.
      this.write(state);
      return true;
    } catch (e) { return false; }
  }

  async prepare(): Promise<boolean> {
    if (this.isReady()) { return true; }
    try {
      if (!this.pending(this.read()) && !this.markClearPending()) { return false; }
    } catch (e) { return false; }
    return await this.clear();
  }

  clear(): Promise<boolean> {
    if (QMPlusWebProfileStore.clearWork !== null) { return QMPlusWebProfileStore.clearWork; }
    const revision: number = QMPlusWebProfileStore.clearRevision;
    const work: Promise<boolean> = this.clearOnce(revision);
    QMPlusWebProfileStore.clearWork = work;
    return work.finally((): void => {
      if (QMPlusWebProfileStore.clearWork === work) { QMPlusWebProfileStore.clearWork = null; }
    });
  }

  private async clearOnce(revision: number): Promise<boolean> {
    if (QMPlusWebProfileStore.restartRequiredInProcess) { return false; }
    try {
      const state: string = this.read();
      if (!this.pending(state)) { return this.isReady(); }
      // Re-establish the durable fence before every deletion pass, including a
      // retry after a previous Preferences flush failure in this process.
      this.write(state);
      if (state === QMPlusWebProfileStore.clearUsed) {
        // WebStorage requires a loaded Web. A cold pending profile is first
        // mounted on about:blank, never on an official login/business URL.
        if (!QMPlusWebProfileStore.initializedInProcess) { return false; }
        await webview.WebCookieManager.clearAllCookies();
        webview.WebStorage.deleteAllData(false);
        // deleteAllData has no callback in API24. Do not invent a completion
        // ACK: inspect only storage usage metadata, and fail closed if any
        // origin still has data or the SDK cannot verify that projection.
        const origins: webview.WebStorageOrigin[] = await webview.WebStorage.getOrigins();
        if (origins.some((origin: webview.WebStorageOrigin): boolean =>
          !Number.isFinite(origin.usage) || origin.usage !== 0)) { return false; }
        await webview.WebCookieManager.saveCookieAsync();
        if (webview.WebCookieManager.existCookie(false)) { return false; }
      }
      if (revision !== QMPlusWebProfileStore.clearRevision) { return false; }
      this.write(state === QMPlusWebProfileStore.clearUnused ? QMPlusWebProfileStore.unused : QMPlusWebProfileStore.ready);
      QMPlusWebProfileStore.blockedInProcess = false;
      return true;
    } catch (e) { return false; }
  }

  async flush(): Promise<boolean> {
    if (!this.isReady() || !QMPlusWebProfileStore.initializedInProcess) { return false; }
    const revision: number = QMPlusWebProfileStore.clearRevision;
    try {
      await webview.WebCookieManager.saveCookieAsync();
      // ArkWeb persists only engine/server-permitted cookies. Session cookies
      // are not promised across restart (notably PC, 2-in-1 and tablet).
      return revision === QMPlusWebProfileStore.clearRevision && this.isReady();
    } catch (e) { return false; }
  }
}
