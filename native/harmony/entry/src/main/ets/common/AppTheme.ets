// 与 Android ThemePalettes / Palette 对应的主题入口。
// 颜色值定义在 resources/base/element/color.json（浅色）与
// resources/dark/element/color.json（深色）中，引用后自动随系统深色模式切换，
// 核心品牌调色板与 Android light / dark 对齐；日程分类色复用鸿蒙日历现有语义。

import { ColorThemes, ColorThemeState, ColorThemeSurfaces } from './ColorThemes';

export class AppTheme {
  static readonly state: ColorThemeState = new ColorThemeState();

  private static surfaces(): ColorThemeSurfaces {
    return ColorThemes.surfaces(AppTheme.state.selection, AppTheme.state.dark);
  }

  // 仅供缓存了颜色值的 ForEach 条目使用，保留外层视图/Scroller 的身份。
  static colorKey(): string {
    const selection = AppTheme.state.selection;
    return selection.preset + selection.primary + selection.accent + selection.selectedDate + AppTheme.state.dark;
  }

  static primary(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_primary') :
      ColorThemes.primary(AppTheme.state.selection, AppTheme.state.dark);
  }

  static primaryFill(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_primary_fill') :
      ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).primary);
  }

  // 日期选择使用独立颜色；默认主题保留原蓝色。
  static selectedDate(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_selected_date') :
      ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).selectedDate);
  }

  static selectedDateStrong(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_selected_date_strong') :
      ColorThemes.blend(ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).selectedDate), '#000000', 0.22);
  }

  static selectedDateSurface(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_selected_date_surface') :
      (AppTheme.state.dark ? '#40' : '#1A') +
        ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).selectedDate).substring(1);
  }

  // 黑色自定义选中色在深色背景中仍须有清晰轮廓；不改用户请求的填色。
  static selectedDateOutline(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? AppTheme.selectedDateStrong() :
      ColorThemes.textOn(ColorThemes.text(ColorThemes.seeds(AppTheme.state.selection).selectedDate,
        AppTheme.state.dark), AppTheme.surfaces().worstSurface);
  }

  static shouldOutlineSelectedDate(selected: boolean, hasSemanticBorder: boolean): boolean {
    return selected && !hasSemanticBorder && AppTheme.state.selection.preset !== 'default';
  }

  static accent(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_accent') :
      ColorThemes.seeds(AppTheme.state.selection).accent;
  }

  static accentSurface(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? '#73E2BC62' :
      ColorThemes.blend(AppTheme.surfaces().surface, ColorThemes.seeds(AppTheme.state.selection).accent, 0.10);
  }

  static onAccent(): ResourceColor {
    if (AppTheme.state.selection.preset === 'default') {
      return AppTheme.text();
    }
    const accent: string = ColorThemes.seeds(AppTheme.state.selection).accent;
    return ColorThemes.contrast(accent, '#000000') >= ColorThemes.contrast(accent, '#FFFFFF') ?
      '#000000' : '#FFFFFF';
  }

  static primaryWithAlpha(alpha: number, dark: boolean): string {
    return ColorThemes.primaryWithAlpha(AppTheme.state.selection, alpha, dark);
  }

  static textOnPrimaryBlend(alpha: number, dark: boolean, secondary: boolean = false): ResourceColor {
    if (AppTheme.state.selection.preset === 'default') {
      return secondary ? AppTheme.secondaryText() : AppTheme.text();
    }
    const surfaces = ColorThemes.surfaces(AppTheme.state.selection, dark);
    return ColorThemes.textOn(secondary ? surfaces.secondaryText : surfaces.text,
      AppTheme.primaryWithAlpha(alpha, dark));
  }

  static textOnSelectionBlend(alpha: number, dark: boolean): ResourceColor {
    if (AppTheme.state.selection.preset === 'default') { return AppTheme.primary(); }
    const background: string = ColorThemes.blend(AppTheme.primaryWithAlpha(alpha, dark),
      ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).primary), dark ? 77 / 255 : 26 / 255);
    return ColorThemes.textOn(ColorThemes.surfaces(AppTheme.state.selection, dark).text, background);
  }

  static selectionText(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? AppTheme.primary() : AppTheme.text();
  }

  static onPrimary(): Resource {
    return $r('app.color.app_on_primary');
  }

  static background(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_background') :
      AppTheme.surfaces().background;
  }

  static surface(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_surface') :
      AppTheme.surfaces().surface;
  }

  static elevated(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_surface') :
      AppTheme.surfaces().elevated;
  }

  static inputSurface(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_surface') :
      AppTheme.surfaces().surfaceVariant;
  }

  static surfaceVariant(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_surface_variant') :
      AppTheme.surfaces().surfaceVariant;
  }

  static text(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_text') : AppTheme.surfaces().text;
  }

  static secondaryText(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_secondary_text') :
      AppTheme.surfaces().secondaryText;
  }

  // 轻度染色条目上的次要说明保留字号，用正文墨色补足合成底色的对比度。
  static secondaryTextOnTint(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? AppTheme.secondaryText() : AppTheme.text();
  }

  // 禁用操作使用不透明的中性配色，避免系统淡化后文字难以辨认。
  static disabledText(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_disabled_text') :
      AppTheme.surfaces().secondaryText;
  }

  static border(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_border') : AppTheme.surfaces().border;
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

  static assignment(): Resource {
    return $r('app.color.app_assignment');
  }

  static assignmentSurface(): Resource {
    return $r('app.color.app_assignment_surface');
  }

  static schoolNotice(): Resource {
    return $r('app.color.app_school_notice');
  }

  static schoolNoticeSurface(): Resource {
    return $r('app.color.app_school_notice_surface');
  }

  static competitionDeadline(): Resource {
    return $r('app.color.app_competition_deadline');
  }

  static competitionDeadlineSurface(): Resource {
    return $r('app.color.app_competition_deadline_surface');
  }

  static conferenceDeadline(): Resource {
    return $r('app.color.app_conference_deadline');
  }

  static conferenceDeadlineSurface(): Resource {
    return $r('app.color.app_conference_deadline_surface');
  }

  static summerCampDeadline(): Resource {
    return $r('app.color.app_summer_camp_deadline');
  }

  static summerCampDeadlineSurface(): Resource {
    return $r('app.color.app_summer_camp_deadline_surface');
  }

  static hackathonDeadline(): Resource {
    return $r('app.color.app_hackathon_deadline');
  }

  static hackathonDeadlineSurface(): Resource {
    return $r('app.color.app_hackathon_deadline_surface');
  }

  static customDeadline(): Resource {
    return $r('app.color.app_custom_deadline');
  }

  static customDeadlineSurface(): Resource {
    return $r('app.color.app_custom_deadline_surface');
  }

  // 兼容旧调用：公开 DDL 的默认颜色等同于学科竞赛色。
  static publicDeadline(): Resource {
    return AppTheme.competitionDeadline();
  }

  static publicDeadlineSurface(): Resource {
    return AppTheme.competitionDeadlineSurface();
  }

  // 主色深档（对应 Android Palette.primaryDark，两模式同值）。
  static primaryDark(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_primary_dark') :
      ColorThemes.blend(ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).primary), '#000000', 0.3);
  }

  // 列表选中背景（深浅色各有独立 alpha，BUG-045 修复）。
  static selection(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_selection') :
      (AppTheme.state.dark ? '#4D' : '#1A') +
        ColorThemes.fill(ColorThemes.seeds(AppTheme.state.selection).primary).substring(1);
  }

  static selectionSurface(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_selection_surface') :
      ColorThemes.blend(AppTheme.surfaces().surface, ColorThemes.seeds(AppTheme.state.selection).primary,
        AppTheme.state.dark ? 0.16 : 0.12);
  }

  static segmentedSelection(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? $r('app.color.app_segmented_selection') :
      AppTheme.surfaces().elevated;
  }
}
