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
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Text(this.todayCountText)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')

      Blank()
        .height(8)

      if (this.emptyText.length > 0) {
        Column() {
          Text(this.emptyGlyph)
            .fontSize(22)
            .fontColor($r('sys.color.ohos_id_color_primary'))
          Text(this.emptyText)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          Text(this.todayLines)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.moreHint.length > 0) {
            Text(this.moreHint)
              .fontSize(10)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      Text(this.tomorrowHint)
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_primary'))
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
