// 与 Android ThemePalettes / Palette 对应的主题入口。
// 颜色值定义在 resources/base/element/color.json（浅色）与
// resources/dark/element/color.json（深色）中，引用后自动随系统深色模式切换，
// 调色板数值与 Android 端 light / dark 完全一致。

export class AppTheme {
  static primary(): Resource {
    return $r('app.color.app_primary');
  }

  static primaryFill(): Resource {
    return $r('app.color.app_primary_fill');
  }

  static accent(): Resource {
    return $r('app.color.app_accent');
  }

  static onPrimary(): Resource {
    return $r('app.color.app_on_primary');
  }

  static background(): Resource {
    return $r('app.color.app_background');
  }

  static surface(): Resource {
    return $r('app.color.app_surface');
  }

  static surfaceVariant(): Resource {
    return $r('app.color.app_surface_variant');
  }

  static text(): Resource {
    return $r('app.color.app_text');
  }

  static secondaryText(): Resource {
    return $r('app.color.app_secondary_text');
  }

  static border(): Resource {
    return $r('app.color.app_border');
  }

  static danger(): Resource {
    return $r('app.color.app_danger');
  }

  // 当前时间/今日标记（对应 Android Palette.nowIndicator 与 Tauri --current-time）。
  static nowIndicator(): Resource {
    return $r('app.color.app_now_indicator');
  }

  // 法定节假日文字（对应 Android Palette.holiday）。
  static holiday(): Resource {
    return $r('app.color.app_holiday');
  }

  // 主色深档（对应 Android Palette.primaryDark，两模式同值）。
  static primaryDark(): Resource {
    return $r('app.color.app_primary_dark');
  }

  // 列表选中背景（深浅色各有独立 alpha，BUG-045 修复）。
  static selection(): Resource {
    return $r('app.color.app_selection');
  }

  static selectionSurface(): Resource {
    return $r('app.color.app_selection_surface');
  }

  static segmentedSelection(): Resource {
    return $r('app.color.app_segmented_selection');
  }
}
