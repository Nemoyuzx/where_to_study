// 与 Android ThemePalettes / Palette 对应的主题入口。
// 颜色值定义在 resources/base/element/color.json（浅色）与
// resources/dark/element/color.json（深色）中，引用后自动随系统深色模式切换，
// 核心品牌调色板与 Android light / dark 对齐；日程分类色复用鸿蒙日历现有语义。

import { ColorThemes, ColorThemeState } from './ColorThemes';

export class AppTheme {
  static readonly state: ColorThemeState = new ColorThemeState();

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
      ColorThemes.text(ColorThemes.seeds(AppTheme.state.selection).selectedDate, AppTheme.state.dark);
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
      '#73' + ColorThemes.seeds(AppTheme.state.selection).accent.substring(1);
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

  static textOnPrimaryBlend(alpha: number, dark: boolean): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? AppTheme.text() :
      ColorThemes.textOn(dark ? '#FFFFFF' : '#111111', AppTheme.primaryWithAlpha(alpha, dark));
  }

  static selectionText(): ResourceColor {
    return AppTheme.state.selection.preset === 'default' ? AppTheme.primary() : AppTheme.text();
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

  // 禁用操作使用不透明的中性配色，避免系统淡化后文字难以辨认。
  static disabledText(): Resource {
    return $r('app.color.app_disabled_text');
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
      ColorThemes.blend(AppTheme.state.dark ? '#1C1C1E' : '#FFFFFF',
        ColorThemes.primary(AppTheme.state.selection, AppTheme.state.dark), AppTheme.state.dark ? 0.18 : 0.15);
  }

  static segmentedSelection(): Resource {
    return $r('app.color.app_segmented_selection');
  }
}
