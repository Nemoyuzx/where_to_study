// 与 Android UiSupport.kt 的 pageTitle/surface 及各处重复使用的小部件对应。
import { AppTheme } from '../common/AppTheme';
import { accessibility } from '@kit.AccessibilityKit';

// A non-interactive vertical Scroll measures nested content independently of
// its initially zero-height viewport. The one ideal-size body stays mounted
// after first expansion; clipping does not recreate drafts or start data work.
@ComponentV2
export struct DisclosureClip {
  @Param expanded: boolean = false;
  @BuilderParam content: () => void;
  @Local mounted: boolean = false;
  @Local viewportHeight: number = 0;
  private bodyHeight: number = 0;

  aboutToAppear(): void { this.mounted = this.expanded; }

  @Monitor('expanded')
  onExpandedChanged(): void {
    if (this.expanded) { this.mounted = true; }
    this.updateHeight();
  }

  private updateHeight(): void {
    const target: number = this.expanded ? this.bodyHeight : 0;
    if (target === this.viewportHeight) { return; }
    let reduced: boolean = false;
    try { reduced = accessibility.isAnimationReduceEnabledSync(); } catch (e) {}
    this.getUIContext().animateTo({ duration: reduced ? 0 : 180, curve: Curve.EaseOut }, (): void => {
      this.viewportHeight = target;
    });
  }

  build() {
    Scroll() {
      if (this.mounted) {
        Column() { this.content(); }
          .width('100%').height(LayoutPolicy.fixAtIdealSize)
          .alignItems(HorizontalAlign.Start)
          .onAreaChange((oldArea: Area, area: Area): void => {
            const height: number = Number(area.height);
            if (!Number.isFinite(height) || height < 0 || Math.abs(height - this.bodyHeight) < 0.5) { return; }
            this.bodyHeight = height; this.updateHeight();
          })
      }
    }
      .width('100%').height(this.viewportHeight).clip(true)
      .scrollable(ScrollDirection.Vertical)
      .enableScrollInteraction(false)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.TopStart)
      .hitTestBehavior(this.expanded ? HitTestMode.Default : HitTestMode.None)
      .accessibilityLevel(this.expanded ? 'auto' : 'no-hide-descendants')
  }
}

// 对应 PageTitle：小标题 eyebrow（大写）+ 大标题。
@ComponentV2
export struct PageTitle {
  @Param eyebrow: string = '';
  @Param title: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.eyebrow.toUpperCase())
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.secondaryText())
      Text(this.title)
        .fontSize(26)
        .minFontSize(19.5)
        .maxFontSize(26)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

// 对应 Surface：圆角表面卡片，内容通过尾随闭包传入。
@ComponentV2
export struct SurfaceCard {
  @Param cardPadding: number = 16;
  @Param showsBorder: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content();
    }
    .padding(this.cardPadding)
    .width('100%')
    .borderRadius(8)
    .border({ width: this.showsBorder ? 1 : 0, radius: 8, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }
}

// 分组标题：系统符号 + 标题文本。
@ComponentV2
export struct SectionHeader {
  @Param icon: Resource = $r('sys.symbol.calendar');
  @Param title: string = '';

  build() {
    Row({ space: 8 }) {
      SymbolGlyph(this.icon)
        .fontSize(18)
        .fontColor([AppTheme.text()])
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .alignItems(VerticalAlign.Center)
  }
}

// 空态提示文本。
@ComponentV2
export struct EmptyMessage {
  @Param message: string = '';

  build() {
    Text(this.message)
      .fontSize(12.5)
      .fontColor(AppTheme.secondaryText())
      .width('100%')
      .height(56)
      .textAlign(TextAlign.Center)
  }
}

// 胶囊按钮（用于节次/教学楼等筛选芯片）。
@ComponentV2
export struct ChipButton {
  @Param selected: boolean = false;
  @Param busy: boolean = false;
  @Param interactive: boolean = true;
  @Param controlHeight: number = 46;
  @BuilderParam content: () => void;
  @Event onTap: () => void = () => {
  };

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .height(this.controlHeight)
    .padding(2)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selected ? AppTheme.primaryFill() :
      (this.busy ? AppTheme.accentSurface() : AppTheme.background()))
    .borderRadius(8)
    .border({
      width: 1,
      radius: 8,
      color: this.selected ? AppTheme.primaryFill() : AppTheme.border()
    })
    .onClick(() => {
      if (this.interactive) {
        this.onTap();
      }
    })
  }
}
