import { ColorThemes, ColorThemeSelection, ColorThemeState } from '../common/ColorThemes';

export interface ColorThemePreferences {
  getString(key: string): Promise<string | null>;
  setString(key: string, value: string): Promise<void>;
}

// 单条 JSON 原子存储，快速切换顺序写入；示例模式只更新内存。
export class ColorThemeStore {
  static readonly key: string = 'colorThemeV1';
  private pendingWrite: Promise<void> = Promise.resolve();
  private revision: number = 0;
  readonly state: ColorThemeState;
  private readonly preferences: ColorThemePreferences;

  constructor(state: ColorThemeState, preferences: ColorThemePreferences) {
    this.state = state;
    this.preferences = preferences;
  }

  async restore(sample: boolean): Promise<void> {
    const revision: number = ++this.revision;
    if (sample) {
      this.state.selection = new ColorThemeSelection();
      return;
    }
    await this.pendingWrite.catch(() => {});
    const selection: ColorThemeSelection = ColorThemes.decode(await this.preferences.getString(ColorThemeStore.key));
    if (this.revision === revision) {
      this.state.selection = selection;
    }
  }

  save(selection: ColorThemeSelection, sample: boolean): Promise<void> {
    this.revision++;
    this.state.selection = selection;
    if (sample) {
      return Promise.resolve();
    }
    const serialized: string = ColorThemes.encode(selection);
    const write: Promise<void> = this.pendingWrite.catch(() => {}).then(() =>
      this.preferences.setString(ColorThemeStore.key, serialized));
    this.pendingWrite = write;
    return write;
  }
}
