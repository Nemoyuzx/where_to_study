// 与 iOS 端 AppTheme.swift 的 PageTitle/Surface 及各处重复使用的
// 小部件对应的共享 UI 组件。
import { AppTheme } from '../common/AppTheme';

// 对应 PageTitle：小标题 eyebrow（大写）+ 大标题。
@ComponentV2
export struct PageTitle {
  @Param eyebrow: string = '';
  @Param title: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.eyebrow.toUpperCase())
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.secondaryText())
      Text(this.title)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

// 对应 Surface：圆角表面卡片，内容通过尾随闭包传入。
@ComponentV2
export struct SurfaceCard {
  @Param cardPadding: number = 16;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content();
    }
    .padding(this.cardPadding)
    .width('100%')
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.border() })
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
        .fontSize(16)
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
      .fontSize(14)
      .fontColor(AppTheme.secondaryText())
      .width('100%')
      .height(72)
      .textAlign(TextAlign.Center)
  }
}

// 胶囊按钮（用于节次/教学楼等筛选芯片）。
@ComponentV2
export struct ChipButton {
  @Param selected: boolean = false;
  @Param busy: boolean = false;
  @Param interactive: boolean = true;
  @BuilderParam content: () => void;
  @Event onTap: () => void = () => {
  };

  build() {
    Column() {
      this.content();
    }
    .width('100%')
    .height(54)
    .padding(4)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selected ? AppTheme.primaryFill() :
      (this.busy ? '#73E2BC62' : AppTheme.background()))
    .borderRadius(6)
    .border({
      width: 1,
      color: this.selected ? AppTheme.primaryFill() : AppTheme.border()
    })
    .onClick(() => {
      if (this.interactive) {
        this.onTap();
      }
    })
  }
}
