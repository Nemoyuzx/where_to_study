import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { AppModel } from '../model/AppModel';
import { QMPlusSnapshotParser, QMPlusURLPolicy } from '../net/QMPlusSnapshot';
import { AppContext } from '../store/AppContext';
import { QMPlusSession } from './QMPlusSession';

// 仅官方 HTTPS 网页在本应用独立的 incognito ArkWeb 中登录。Microsoft SSO/MFA
// 页面可以正常导航，但绝不注入读取脚本，也不注册注入所有 frame 的 JS proxy。
@ComponentV2
export struct QMPlusConnectionView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: QMPlusSession = new QMPlusSession();
  private readonly controller: webview.WebviewController = new webview.WebviewController();
  private mounted: boolean = false;
  private pageRevision: number = 0;
  private autoSyncPending: boolean = true;
  private delayTimer: number = -1;
  private resolveDelay: (() => void) | null = null;

  aboutToAppear(): void {
    this.mounted = true;
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.pageRevision++;
    this.cancelWebFlight();
    this.cancelDelay();
    this.session.cancelSync();
  }

  private safeCurrentURL(): string {
    try { return this.controller.getUrl(); } catch (e) { return ''; }
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
    return this.mounted && owner === this.pageRevision && this.session.isCurrent(generation) &&
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

  private async runSync(): Promise<void> {
    if (!QMPlusURLPolicy.isBusinessPage(this.safeCurrentURL()) || !this.mounted) {
      this.session.error = '请先在官方 QMplus 网页完成登录。';
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
    if (!this.mounted) { return; }
    this.session.noteWebLoaded();
    if (this.session.snapshot === null || !QMPlusURLPolicy.isBusinessPage(url)) {
      this.autoSyncPending = true;
    }
    this.pageRevision++;
    this.cancelDelay();
    this.session.cancelSync();
  }

  private pageEnded(url: string): void {
    if (!this.mounted || !QMPlusURLPolicy.isBusinessPage(url) ||
      !QMPlusURLPolicy.isBusinessPage(this.safeCurrentURL()) || !this.autoSyncPending) { return; }
    this.autoSyncPending = false;
    void this.runSync();
  }

  private close(): void {
    this.cancelWebFlight();
    this.cancelDelay();
    this.session.closeLogin();
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
        Button(this.model.text(this.session.syncing ? '正在同步…' : '同步课程'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .enabled(!this.session.syncing)
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .id('qmplus.login.sync')
          .onClick(() => { void this.runSync(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      Text(this.model.text('仅在官方网页完成 SSO/MFA；应用不读取或保存 Microsoft 密码。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      if (this.session.error.length > 0) {
        Text(this.model.text(this.session.error) + (this.session.errorCode.length > 0 &&
          this.session.errorCode !== 'QM_LOGIN_REQUIRED' ? ' (' + this.session.errorCode + ')' : ''))
          .fontSize(12)
          .fontColor(AppTheme.danger())
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }
      Web({ src: this.session.targetURL, controller: this.controller, incognitoMode: true })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .mixedMode(MixedMode.None)
        .allowWindowOpenMethod(false)
        .onOverrideUrlLoading((request) => request.isMainFrame() &&
          !QMPlusURLPolicy.isHTTPSPage(request.getRequestUrl()))
        .onPageBegin((event) => this.pageBegan(event.url))
        .onPageEnd((event) => this.pageEnded(event.url))
        .onErrorReceive((event) => {
          if (this.mounted && event.request.isMainFrame()) {
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
