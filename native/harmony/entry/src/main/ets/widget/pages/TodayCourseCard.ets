// 今日课程卡片 UI，对应 iOS 端 TodayCourseWidgetView。
// 卡片运行环境仅支持受限 ArkTS 子集，这里只使用基础容器与 Text。
@Entry
@Component
struct TodayCourseCard {
  @LocalStorageProp('todayTitle') todayTitle: string = '今日课程';
  @LocalStorageProp('todayCountText') todayCountText: string = '';
  @LocalStorageProp('todayLines') todayLines: string = '';
  @LocalStorageProp('moreHint') moreHint: string = '';
  @LocalStorageProp('tomorrowHint') tomorrowHint: string = '';
  @LocalStorageProp('emptyGlyph') emptyGlyph: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '';

  build() {
    Column() {
      Row() {
        Text(this.todayTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        Blank()
        Text(this.todayCountText)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#88000000')
      }
      .width('100%')

      Blank()
        .height(8)

      if (this.emptyText.length > 0) {
        Column() {
          Text(this.emptyGlyph)
            .fontSize(22)
            .fontColor('#166B5D')
          Text(this.emptyText)
            .fontSize(13)
            .fontColor('#88000000')
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          Text(this.todayLines)
            .fontSize(12)
            .fontColor('#1A1A1A')
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.moreHint.length > 0) {
            Text(this.moreHint)
              .fontSize(10)
              .fontColor('#88000000')
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      Text(this.tomorrowHint)
        .fontSize(11)
        .fontColor('#166B5D')
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F2F4F6')
  }
}
