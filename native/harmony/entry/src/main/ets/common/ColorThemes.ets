// contracts/v1/color-themes.json 的 ArkTS 原生实现；默认色保留资源中的精确值。
export class ColorThemeSeed {
  readonly id: string;
  readonly nameZh: string;
  readonly nameEn: string;
  readonly primary: string;
  readonly accent: string;
  readonly selectedDate: string;

  constructor(id: string, nameZh: string, nameEn: string,
    primary: string, accent: string, selectedDate: string) {
    this.id = id;
    this.nameZh = nameZh;
    this.nameEn = nameEn;
    this.primary = primary;
    this.accent = accent;
    this.selectedDate = selectedDate;
  }
}

export class ColorThemeSelection {
  readonly preset: string;
  readonly primary: string;
  readonly accent: string;
  readonly selectedDate: string;

  constructor(preset: string = 'default', primary: string = '#166B5D',
    accent: string = '#E2BC62', selectedDate: string = '#2563EB') {
    this.preset = preset;
    this.primary = primary;
    this.accent = accent;
    this.selectedDate = selectedDate;
  }

  selecting(preset: string): ColorThemeSelection {
    return new ColorThemeSelection(ColorThemes.normalizePreset(preset),
      this.primary, this.accent, this.selectedDate);
  }
}

export class ColorThemes {
  static readonly presets: ColorThemeSeed[] = [
    new ColorThemeSeed('default', '默认青绿', 'Classic Teal', '#166B5D', '#E2BC62', '#2563EB'),
    new ColorThemeSeed('ocean', '海洋蓝', 'Ocean Blue', '#1565C0', '#26A69A', '#7C3AED'),
    new ColorThemeSeed('violet', '鸢尾紫', 'Iris Violet', '#7C3AED', '#D08A2E', '#00796B'),
    new ColorThemeSeed('amber', '暖琥珀', 'Warm Amber', '#A65300', '#2E7D6F', '#2563EB'),
    new ColorThemeSeed('rose', '玫瑰', 'Rose', '#B42368', '#8C6A35', '#2563EB')
  ];

  static normalizeHex(value: string): string | null {
    const trimmed: string = value.trim();
    return /^#?[0-9a-fA-F]{6}$/.test(trimmed) ?
      '#' + trimmed.replace('#', '').toUpperCase() : null;
  }

  static normalizePreset(value: string): string {
    return value === 'custom' || ColorThemes.presets.some((seed: ColorThemeSeed) =>
      seed.id === value) ? value : 'default';
  }

  static custom(primary: string, accent: string, selectedDate: string): ColorThemeSelection | null {
    const p: string | null = ColorThemes.normalizeHex(primary);
    const a: string | null = ColorThemes.normalizeHex(accent);
    const s: string | null = ColorThemes.normalizeHex(selectedDate);
    return p !== null && a !== null && s !== null ? new ColorThemeSelection('custom', p, a, s) : null;
  }

  static seeds(selection: ColorThemeSelection): ColorThemeSeed {
    if (selection.preset === 'custom') {
      return new ColorThemeSeed('custom', '自定义', 'Custom', selection.primary,
        selection.accent, selection.selectedDate);
    }
    return ColorThemes.presets.find((seed: ColorThemeSeed) => seed.id === selection.preset) ??
      ColorThemes.presets[0];
  }

  static encode(selection: ColorThemeSelection): string {
    return JSON.stringify(selection);
  }

  static decode(value: string | null): ColorThemeSelection {
    if (value === null || value.length === 0) {
      return new ColorThemeSelection();
    }
    try {
      const raw: Record<string, Object> = JSON.parse(value) as Record<string, Object>;
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        return new ColorThemeSelection();
      }
      return new ColorThemeSelection(
        ColorThemes.normalizePreset(typeof raw['preset'] === 'string' ? raw['preset'] as string : ''),
        ColorThemes.readHex(raw['primary'], '#166B5D'),
        ColorThemes.readHex(raw['accent'], '#E2BC62'),
        ColorThemes.readHex(raw['selectedDate'], '#2563EB'));
    } catch (e) {
      return new ColorThemeSelection();
    }
  }

  private static readHex(value: Object | undefined, fallback: string): string {
    return typeof value === 'string' ? ColorThemes.normalizeHex(value as string) ?? fallback : fallback;
  }

  private static channels(hex: string): number[] {
    return [parseInt(hex.substring(1, 3), 16), parseInt(hex.substring(3, 5), 16),
      parseInt(hex.substring(5, 7), 16)];
  }

  static blend(seed: string, target: string, amount: number): string {
    const from: number[] = ColorThemes.channels(seed);
    const to: number[] = ColorThemes.channels(target);
    const alpha: number = Math.min(1, Math.max(0, amount));
    return '#' + from.map((value: number, index: number) =>
      Math.round(value + (to[index] - value) * alpha).toString(16).padStart(2, '0')).join('').toUpperCase();
  }

  static luminance(hex: string): number {
    const values: number[] = ColorThemes.channels(hex).map((value: number) => {
      const c: number = value / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2];
  }

  static contrast(first: string, second: string): number {
    const a: number = ColorThemes.luminance(first);
    const b: number = ColorThemes.luminance(second);
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
  }

  private static accessible(seed: string, background: string, target: string): string {
    for (let step = 0; step <= 50; step++) {
      const color: string = ColorThemes.blend(seed, target, step * 0.02);
      if (ColorThemes.contrast(color, background) >= 4.5) {
        return color;
      }
    }
    return target;
  }

  static fill(seed: string): string {
    return ColorThemes.accessible(seed, '#FFFFFF', '#000000');
  }

  static text(seed: string, dark: boolean): string {
    return dark ? ColorThemes.accessible(seed, '#282828', '#FFFFFF') : ColorThemes.fill(seed);
  }

  static textOn(seed: string, background: string): string {
    return ColorThemes.accessible(seed, background,
      ColorThemes.contrast('#000000', background) >= ColorThemes.contrast('#FFFFFF', background) ?
        '#000000' : '#FFFFFF');
  }

  static primary(selection: ColorThemeSelection, dark: boolean): string {
    return selection.preset === 'default' ? (dark ? '#5AD2B8' : '#166B5D') :
      ColorThemes.text(ColorThemes.seeds(selection).primary, dark);
  }

  static primaryWithAlpha(selection: ColorThemeSelection, alpha: number, dark: boolean): string {
    return ColorThemes.blend(dark ? '#000000' : '#F2F2F7', ColorThemes.primary(selection, dark), alpha);
  }
}

// ArkUI 在每个 AppTheme 方法读取时跟踪 @Trace，无需替换页面或刷新数据。
@ObservedV2
export class ColorThemeState {
  @Trace selection: ColorThemeSelection = new ColorThemeSelection();
  @Trace dark: boolean = false;
}
