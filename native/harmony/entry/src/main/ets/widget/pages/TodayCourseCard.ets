// 今日课程卡片 UI，对应 iOS 端 TodayCourseWidgetCard.swift 与
// Android 端 widget_today_course.xml（增强版）：
// 标题行 + 日期/状态上下文 + 最多 6 行课程（高亮前缀 + 强调条）+ 空态。
// 卡片运行环境仅支持受限 ArkTS 子集，这里只使用基础容器与 Text。
@Entry
@Component
struct TodayCourseCard {
  @LocalStorageProp('todayTitle') todayTitle: string = '今日课程';
  @LocalStorageProp('todayCountText') todayCountText: string = '';
  @LocalStorageProp('dateContext') dateContext: string = '';
  @LocalStorageProp('statusText') statusText: string = '';
  @LocalStorageProp('course1Name') course1Name: string = '';
  @LocalStorageProp('course1Details') course1Details: string = '';
  @LocalStorageProp('course1Highlighted') course1Highlighted: boolean = false;
  @LocalStorageProp('course2Name') course2Name: string = '';
  @LocalStorageProp('course2Details') course2Details: string = '';
  @LocalStorageProp('course2Highlighted') course2Highlighted: boolean = false;
  @LocalStorageProp('course3Name') course3Name: string = '';
  @LocalStorageProp('course3Details') course3Details: string = '';
  @LocalStorageProp('course3Highlighted') course3Highlighted: boolean = false;
  @LocalStorageProp('course4Name') course4Name: string = '';
  @LocalStorageProp('course4Details') course4Details: string = '';
  @LocalStorageProp('course4Highlighted') course4Highlighted: boolean = false;
  @LocalStorageProp('course5Name') course5Name: string = '';
  @LocalStorageProp('course5Details') course5Details: string = '';
  @LocalStorageProp('course5Highlighted') course5Highlighted: boolean = false;
  @LocalStorageProp('course6Name') course6Name: string = '';
  @LocalStorageProp('course6Details') course6Details: string = '';
  @LocalStorageProp('course6Highlighted') course6Highlighted: boolean = false;
  @LocalStorageProp('moreHint') moreHint: string = '';
  @LocalStorageProp('emptyGlyph') emptyGlyph: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '';

  private rows(): string[][] {
    const names: string[][] = [];
    if (this.course1Name.length > 0) {
      names.push([this.course1Name, this.course1Details, this.course1Highlighted ? '1' : '0']);
    }
    if (this.course2Name.length > 0) {
      names.push([this.course2Name, this.course2Details, this.course2Highlighted ? '1' : '0']);
    }
    if (this.course3Name.length > 0) {
      names.push([this.course3Name, this.course3Details, this.course3Highlighted ? '1' : '0']);
    }
    if (this.course4Name.length > 0) {
      names.push([this.course4Name, this.course4Details, this.course4Highlighted ? '1' : '0']);
    }
    if (this.course5Name.length > 0) {
      names.push([this.course5Name, this.course5Details, this.course5Highlighted ? '1' : '0']);
    }
    if (this.course6Name.length > 0) {
      names.push([this.course6Name, this.course6Details, this.course6Highlighted ? '1' : '0']);
    }
    return names;
  }

  @Builder
  courseRow(name: string, details: string, highlighted: boolean) {
    Row() {
      // 强调条：高亮课程用主色，其余金色（对应 Android/Apple）。
      Column()
        .width(3)
        .height(30)
        .borderRadius(1.5)
        .backgroundColor(highlighted ? $r('app.color.app_primary_fill') :
          $r('app.color.widget_accent'))
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
      // 标题行
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

      // 日期/状态上下文
      if (this.dateContext.length > 0) {
        Text(this.statusText.length > 0 ?
          this.dateContext + ' · ' + this.statusText : this.dateContext)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 3 })
      }

      Blank()
        .height(8)

      if (this.emptyText.length > 0) {
        Row({ space: 9 }) {
          Text(this.emptyGlyph)
            .fontSize(22)
            .fontColor($r('app.color.widget_primary'))
          Column({ space: 2 }) {
            Text(this.emptyText)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_text_primary'))
            Text(this.statusText)
              .fontSize(11)
              .fontColor($r('app.color.widget_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 0 }) {
          ForEach(this.rows(), (row: string[], index: number) => {
            this.courseRow(row[0], row[1], row[2] === '1')
          }, (row: string[], index: number) => 'row.' + row[0] + '.' + index.toString())
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
    }
    .padding(14)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(16)
    .backgroundColor($r('app.color.widget_background'))
  }
}
