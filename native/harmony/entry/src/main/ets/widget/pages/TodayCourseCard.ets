// 今日课程卡片 UI，对应 iOS 端 TodayCourseWidgetView 与
// Android 端 widget_today_course.xml：标题行 + 最多 3 行课程
// （金色强调条 + 课程名/时间·教室）+ 更多提示 + 明日提示 + 空态。
// 卡片运行环境仅支持受限 ArkTS 子集，这里只使用基础容器与 Text。
@Entry
@Component
struct TodayCourseCard {
  @LocalStorageProp('todayTitle') todayTitle: string = '今日课程';
  @LocalStorageProp('todayCountText') todayCountText: string = '';
  @LocalStorageProp('course1Name') course1Name: string = '';
  @LocalStorageProp('course1Details') course1Details: string = '';
  @LocalStorageProp('course2Name') course2Name: string = '';
  @LocalStorageProp('course2Details') course2Details: string = '';
  @LocalStorageProp('course3Name') course3Name: string = '';
  @LocalStorageProp('course3Details') course3Details: string = '';
  @LocalStorageProp('moreHint') moreHint: string = '';
  @LocalStorageProp('tomorrowHint') tomorrowHint: string = '';
  @LocalStorageProp('emptyGlyph') emptyGlyph: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '';

  private rowNames(): string[] {
    const names: string[] = [];
    if (this.course1Name.length > 0) {
      names.push(this.course1Name);
    }
    if (this.course2Name.length > 0) {
      names.push(this.course2Name);
    }
    if (this.course3Name.length > 0) {
      names.push(this.course3Name);
    }
    return names;
  }

  private rowDetails(): string[] {
    const details: string[] = [];
    if (this.course1Details.length > 0) {
      details.push(this.course1Details);
    }
    if (this.course2Details.length > 0) {
      details.push(this.course2Details);
    }
    if (this.course3Details.length > 0) {
      details.push(this.course3Details);
    }
    return details;
  }

  @Builder
  courseRow(name: string, details: string) {
    Row() {
      // 金色强调条：对应 Android WidgetCourseAccent（3dp x 30dp）。
      Column()
        .width(3)
        .height(30)
        .borderRadius(1.5)
        .backgroundColor($r('app.color.widget_accent'))
      Column({ space: 1 }) {
        Text(name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.widget_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(details)
          .fontSize(11)
          .fontColor($r('app.color.widget_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Text(this.todayTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.widget_text_primary'))
        Blank()
        Text(this.todayCountText)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_secondary'))
      }
      .width('100%')
      .height(28)
      .alignItems(VerticalAlign.Center)

      Blank()
        .height(8)

      if (this.emptyText.length > 0) {
        Row({ space: 9 }) {
          Text(this.emptyGlyph)
            .fontSize(22)
            .fontColor($r('app.color.widget_primary'))
          Text(this.emptyText)
            .fontSize(14)
            .fontColor($r('app.color.widget_text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 0 }) {
          ForEach(this.rowNames(), (name: string, index: number) => {
            this.courseRow(name, this.rowDetails()[index])
          }, (name: string, index: number) => 'row.' + name + '.' + index.toString())
          if (this.moreHint.length > 0) {
            Text(this.moreHint)
              .fontSize(11)
              .fontColor($r('app.color.widget_text_secondary'))
              .maxLines(1)
              .width('100%')
              .margin({ top: 2 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }

      Blank()

      Text(this.tomorrowHint)
        .fontSize(11)
        .fontColor($r('app.color.widget_primary'))
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(16)
    .backgroundColor($r('app.color.widget_background'))
  }
}
