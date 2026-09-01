// 与 Android ThemePalettes / Palette 对应的主题入口。
// 颜色值定义在 resources/base/element/color.json（浅色）与
// resources/dark/element/color.json（深色）中，引用后自动随系统深色模式切换，
// 核心品牌调色板与 Android light / dark 对齐；日程分类色复用鸿蒙日历现有语义。

export class AppTheme {
  static primary(): Resource {
    return $r('app.color.app_primary');
  }

  static primaryFill(): Resource {
    return $r('app.color.app_primary_fill');
  }

  // 日期选择使用独立蓝色，不再与课程/导航主绿色混淆。
  static selectedDate(): Resource {
    return $r('app.color.app_selected_date');
  }

  static selectedDateStrong(): Resource {
    return $r('app.color.app_selected_date_strong');
  }

  static selectedDateSurface(): Resource {
    return $r('app.color.app_selected_date_surface');
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
