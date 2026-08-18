// 与 iOS 端 UserDefaults 对应的轻量设置存储（termID/termStartDate/campusID/
// 通知开关/UI 测试隔离域等）。数据无敏感信息，凭据一律走 ASSET 安全存储。
import { preferences } from '@kit.ArkData';
import { AppContext } from './AppContext';

export class PreferencesStore {
  private readonly name: string;

  constructor(name: string = 'where-to-study') {
    this.name = name;
  }

  private async open(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(AppContext.get(), { name: this.name });
  }

  async getString(key: string): Promise<string | null> {
    const store: preferences.Preferences = await this.open();
    const value: preferences.ValueType = await store.get(key, '');
    if (typeof value !== 'string') {
      return null;
    }
    return value as string;
  }

  async getBool(key: string, fallback: boolean): Promise<boolean> {
    const store: preferences.Preferences = await this.open();
    const value: preferences.ValueType = await store.get(key, fallback);
    return typeof value === 'boolean' ? value as boolean : fallback;
  }

  async getStringArray(key: string): Promise<string[]> {
    const store: preferences.Preferences = await this.open();
    const value: preferences.ValueType = await store.get(key, []);
    if (!Array.isArray(value)) {
      return [];
    }
    const result: string[] = [];
    for (const item of value as Object[]) {
      if (typeof item === 'string') {
        result.push(item as string);
      }
    }
    return result;
  }

  async getNumberArray(key: string): Promise<number[]> {
    const store: preferences.Preferences = await this.open();
    const value: preferences.ValueType = await store.get(key, []);
    if (!Array.isArray(value)) {
      return [];
    }
    const result: number[] = [];
    for (const item of value as Object[]) {
      if (typeof item === 'number') {
        result.push(item as number);
      }
    }
    return result;
  }

  async setString(key: string, value: string): Promise<void> {
    const store: preferences.Preferences = await this.open();
    await store.put(key, value);
    await store.flush();
  }

  async setBool(key: string, value: boolean): Promise<void> {
    const store: preferences.Preferences = await this.open();
    await store.put(key, value);
    await store.flush();
  }

  async setNumberArray(key: string, value: number[]): Promise<void> {
    const store: preferences.Preferences = await this.open();
    await store.put(key, value);
    await store.flush();
  }

  async remove(key: string): Promise<void> {
    const store: preferences.Preferences = await this.open();
    await store.delete(key);
    await store.flush();
  }

  async clearAll(): Promise<void> {
    const store: preferences.Preferences = await this.open();
    await store.clear();
    await store.flush();
  }
}
