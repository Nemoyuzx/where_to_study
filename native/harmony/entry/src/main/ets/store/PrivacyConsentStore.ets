// 首次启动隐私同意只保存在 HarmonyOS Preferences 中，不上传到任何服务。
// 使用版本号而不是布尔值，隐私声明发生实质变化时可以再次征求用户同意。
import { PreferencesStore } from './PreferencesStore';

export class PrivacyConsentInfo {
  static readonly preferenceKey: string = 'privacyConsentVersion';
  static readonly currentVersion: number = 1;

  static isAccepted(storedVersion: number): boolean {
    return storedVersion >= PrivacyConsentInfo.currentVersion;
  }
}

export class PrivacyConsentStore {
  private readonly preferences: PreferencesStore;

  constructor(preferencesName: string = 'where-to-study') {
    this.preferences = new PreferencesStore(preferencesName);
  }

  async isAccepted(): Promise<boolean> {
    const storedVersion: number = await this.preferences.getNumber(
      PrivacyConsentInfo.preferenceKey, 0);
    return PrivacyConsentInfo.isAccepted(storedVersion);
  }

  async accept(): Promise<void> {
    await this.preferences.setNumber(
      PrivacyConsentInfo.preferenceKey, PrivacyConsentInfo.currentVersion);
  }
}
