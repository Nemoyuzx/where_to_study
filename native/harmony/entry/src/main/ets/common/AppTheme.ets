// 与 iOS 端 AppTheme.swift 对应的主题入口。
// 颜色值定义在 resources/base/element/color.json（浅色）与
// resources/dark/element/color.json（深色）中，引用后自动随系统深色模式切换，
// 与 SwiftUI 的 adaptiveColor 行为一致。
// 调色板数值与 AppThemePalette.light / .dark 完全一致。

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
    return $r('sys.color.ohos_id_color_background');
  }

  static surface(): Resource {
    return $r('sys.color.ohos_id_color_sub_background');
  }

  static text(): Resource {
    return $r('sys.color.ohos_id_color_text_primary');
  }

  static secondaryText(): Resource {
    return $r('sys.color.ohos_id_color_text_secondary');
  }

  static border(): Resource {
    return $r('sys.color.ohos_id_color_list_separator');
  }

  static danger(): Resource {
    return $r('app.color.app_danger');
  }
}
