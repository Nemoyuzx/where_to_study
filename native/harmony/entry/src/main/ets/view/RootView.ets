// 与 iOS 端 RootView.swift 对应的根布局：
// 宽度 >= 700vp 时使用侧栏（对应 NavigationSplitView 的 regular 布局），
// 否则使用底部 Tabs（对应 compact 布局）；示例模式顶部显示提示条。

import { AppModel } from '../model/AppModel';
import { AppSection, AppSectionInfo } from '../common/AppSection';
import { AppTheme } from '../common/AppTheme';
import { PlannerView } from './PlannerView';
import { CalendarSectionView } from './CalendarSectionView';
import { SettingsView } from './SettingsView';

export class AdaptiveLayoutPolicy {
  static readonly minimumSidebarWidth: number = 700;
  static readonly minimumExpandedCalendarWidth: number = 760;

  // iOS 端 horizontalClass == .regular 等价于宽度 >= 600vp，
  // 与 minimumSidebarWidth 合取后侧栏阈值即 700vp。
  static useSidebar(width: number): boolean {
    return width >= AdaptiveLayoutPolicy.minimumSidebarWidth;
  }
}

@ComponentV2
export struct RootView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local currentSection: AppSection = AppSection.planner;
  @Local containerWidth: number = 390;

  aboutToAppear(): void {
    this.model.launch();
  }

  onPageShow(): void {
    // 对应 iOS scenePhase == .active 时的刷新。
    this.model.refreshClassroomsIfNeeded();
    this.model.refreshDailyCourseNotificationAuthorization();
  }

  build() {
    Column() {
      if (this.model.isSampleMode) {
        this.sampleModeBanner()
      }
      if (AdaptiveLayoutPolicy.useSidebar(this.containerWidth)) {
        this.sidebarLayout()
      } else {
        this.tabLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.containerWidth = Number(newArea.width);
    })
  }

  @Builder
  sampleModeBanner() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.eye'))
        .fontSize(14)
        .fontColor([AppTheme.text()])
      Text('示例数据 · 不连接北邮教务服务')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.text())
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.accent())
  }

  @Builder
  sidebarLayout() {
    Row() {
      this.sidebar()
      Divider()
        .vertical(true)
        .color(AppTheme.border())
      Column() {
        this.sectionView(this.currentSection)
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sidebar() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('BUPT')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
        Text('Where To Study')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 24, right: 24 })

      Divider()
        .color(AppTheme.border())

      ForEach(AppSectionInfo.all, (section: AppSection) => {
        Row({ space: 8 }) {
          SymbolGlyph(AppSectionInfo.symbol(section))
            .fontSize(18)
            .fontColor([AppTheme.text()])
          Text(AppSectionInfo.title(section))
            .fontSize(16)
            .fontWeight(this.currentSection === section ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(AppTheme.text())
        }
        .width('100%')
        .height(36)
        .padding({ left: 12, right: 12 })
        .borderRadius(6)
        .backgroundColor(this.currentSection === section ? '#24000000' : Color.Transparent)
        .onClick(() => {
          this.selectSection(section);
        })
      }, (section: AppSection) => AppSectionInfo.accessibilityId(section))
    }
    .width(230)
    .height('100%')
    .padding({ top: 16 })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tabLayout() {
    Tabs({ barPosition: BarPosition.End, index: this.sectionIndexOf(this.currentSection) }) {
      ForEach(AppSectionInfo.all, (section: AppSection) => {
        TabContent() {
          this.sectionView(section)
        }
        .tabBar(this.tabBarBuilder(section))
      }, (section: AppSection) => AppSectionInfo.accessibilityId(section))
    }
    .width('100%')
    .height('100%')
    .barBackgroundColor(AppTheme.surface())
    .onChange((index: number) => {
      const section: AppSection | undefined = this.sectionAt(index);
      if (section !== undefined) {
        this.selectSection(section);
      }
    })
    .scrollable(false)
  }

  @Builder
  tabBarBuilder(section: AppSection) {
    Column({ space: 2 }) {
      SymbolGlyph(AppSectionInfo.symbol(section))
        .fontSize(22)
        .fontColor([this.currentSection === section ? AppTheme.primary() : AppTheme.secondaryText()])
      Text(AppSectionInfo.title(section))
        .fontSize(10)
        .fontColor(this.currentSection === section ? AppTheme.primary() : AppTheme.secondaryText())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  sectionView(section: AppSection) {
    if (section === AppSection.planner) {
      PlannerView()
    } else if (section === AppSection.calendar) {
      CalendarSectionView({ containerWidth: this.containerWidth })
    } else {
      SettingsView()
    }
  }

  selectSection(section: AppSection): void {
    this.currentSection = section;
    this.model.selectedSection = section;
  }

  private sectionIndexOf(section: AppSection): number {
    for (let i = 0; i < AppSectionInfo.all.length; i++) {
      if (AppSectionInfo.all[i] === section) {
        return i;
      }
    }
    return 0;
  }

  private sectionAt(index: number): AppSection | undefined {
    if (index < 0 || index >= AppSectionInfo.all.length) {
      return undefined;
    }
    return AppSectionInfo.all[index];
  }
}
