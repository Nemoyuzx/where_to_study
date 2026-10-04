// QMplus 的官方 ArkWeb 会话与教务/教学云账号完全分离。
// 只在内存保留有限的课程快照；不接收或持久化 Microsoft 密码、Cookie、sesskey。
import { webview } from '@kit.ArkWeb';
import { QMPlusSnapshot, QMPlusSnapshotParser, QMPlusURLPolicy } from '../net/QMPlusSnapshot';

@ObservedV2
export class QMPlusSession {
  @Trace loginVisible: boolean = false;
  @Trace targetURL: string = QMPlusURLPolicy.home;
  @Trace syncing: boolean = false;
  @Trace snapshot: QMPlusSnapshot | null = null;
  @Trace showingStalePartial: boolean = false;
  @Trace error: string = '';
  @Trace errorCode: string = '';
  private generation: number = 0;
  private webLoaded: boolean = false;

  noteWebLoaded(): void {
    this.webLoaded = true;
  }

  openLogin(url: string = QMPlusURLPolicy.home): void {
    this.targetURL = QMPlusURLPolicy.isBusinessPage(url) ? url : QMPlusURLPolicy.home;
    this.loginVisible = true;
    this.error = '';
    this.errorCode = '';
  }

  closeLogin(): void {
    this.cancelSync();
    this.loginVisible = false;
    this.targetURL = QMPlusURLPolicy.home;
  }

  beginSync(): number {
    if (this.syncing) { return -1; }
    const generation: number = ++this.generation;
    this.syncing = true;
    this.error = '';
    this.errorCode = '';
    return generation;
  }

  isCurrent(generation: number): boolean {
    return generation === this.generation && this.syncing && this.loginVisible;
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
      this.errorCode = /^[A-Z0-9_]{1,80}$/.test(message) ? message : '';
      this.error = this.errorCode === 'QM_LOGIN_REQUIRED' ? '请先在官方 QMplus 网页完成登录。' :
        this.errorCode.length > 0 ? 'QMplus 同步失败。' : message;
    }
    this.syncing = false;
  }

  failSync(generation: number, message: string): void {
    if (!this.isCurrent(generation)) { return; }
    this.syncing = false;
    this.errorCode = '';
    this.error = message;
  }

  cancelSync(): void {
    this.generation++;
    this.syncing = false;
  }

  logout(): boolean {
    this.cancelSync();
    this.loginVisible = false;
    this.targetURL = QMPlusURLPolicy.home;
    this.snapshot = null;
    this.showingStalePartial = false;
    this.error = '';
    this.errorCode = '';
    if (!this.webLoaded) { return true; }
    try {
      // 仅清除本应用 incognito ArkWeb profile 的 Cookie；不访问系统浏览器或其它应用。
      webview.WebCookieManager.clearAllCookiesSync(true);
      // 当前应用只为 QMplus 使用 incognito Web；同时删除该 profile 的网页存储，
      // 清除 Microsoft SSO 页面可能留在 Web Storage 的临时身份状态。
      webview.WebStorage.deleteAllData(true);
      this.webLoaded = false;
      return true;
    } catch (e) {
      this.error = 'QMplus 浏览器会话未能清除，请稍后重试。';
      return false;
    }
  }

  dispose(): void {
    this.cancelSync();
    this.loginVisible = false;
  }
}
