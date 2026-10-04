// 仅保存设置页的临时 UI 状态，由 RootView 持有；不写入业务偏好或磁盘。
// 平板侧栏与手机底栏互切时 SettingsView 会重新创建，草稿仍应保留。
import { AppLanguage, AppLanguageInfo } from '../common/AppLocalization';

@ObservedV2
export class SettingsSession {
  @Trace showingPrivacyPolicy: boolean = false;
  @Trace showingLanguagePicker: boolean = false;
  @Trace requestedLanguageRawValue: string = '';
  @Trace customDeadlineURLDraft: string = '';
  @Trace editingPreClassReminders: boolean = false;
  @Trace preClassLeadDrafts: string[] = ['10'];
  @Trace preClassInputError: string = '';
  @Trace previewDimension: number = 3;
  // 仅 DEBUG review-demo 的显式 UI 生命周期测试使用；普通/真实输入场景始终为 false。
  @Trace seedOnlyScene: boolean = false;

  private customDeadlineURLDirty: boolean = false;
  private presentationSeeded: boolean = false;

  requestLanguage(value: AppLanguage): void {
    this.requestedLanguageRawValue = AppLanguageInfo.normalize(value);
    this.showingLanguagePicker = false;
  }

  takeLanguageRequest(): AppLanguage | null {
    if (this.requestedLanguageRawValue.length === 0) { return null; }
    const requested: AppLanguage = AppLanguageInfo.normalize(this.requestedLanguageRawValue);
    this.requestedLanguageRawValue = '';
    return requested;
  }

  seedReviewPresentationDraftsOnce(): boolean {
    if (this.presentationSeeded) { return false; }
    this.presentationSeeded = true;
    this.seedOnlyScene = true;
    this.editCustomDeadlineURL('https://example.org/review-only-feed.json');
    this.preClassLeadDrafts = ['17'];
    this.preClassInputError = '';
    this.editingPreClassReminders = true;
    return true;
  }

  syncCustomDeadlineURL(savedURL: string): void {
    if (!this.customDeadlineURLDirty) {
      this.customDeadlineURLDraft = savedURL;
    }
  }

  editCustomDeadlineURL(value: string): void {
    this.customDeadlineURLDraft = value;
    this.customDeadlineURLDirty = true;
  }

  savedCustomDeadlineURL(submitted: string, saved: string): void {
    // 保存期间用户继续输入时，较早请求的回调不得覆盖新草稿。
    if (this.customDeadlineURLDraft !== submitted) {
      return;
    }
    this.customDeadlineURLDraft = saved;
    this.customDeadlineURLDirty = false;
  }

  clearDrafts(): void {
    this.showingLanguagePicker = false;
    this.requestedLanguageRawValue = '';
    this.customDeadlineURLDraft = '';
    this.customDeadlineURLDirty = false;
    this.editingPreClassReminders = false;
    this.preClassLeadDrafts = ['10'];
    this.preClassInputError = '';
    this.previewDimension = 3;
  }
}
