// 手机布局以 Android PlannerPage.kt 为视觉和交互基准。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { Classroom, Course, SlotMetadata } from '../common/Models';
import { StrictDates } from '../common/StrictDates';

export class PlannerLayoutMetrics {
  static readonly slotMinimumWidth: number = 104;
  static readonly slotMaximumWidth: number = 156;
  static readonly slotSpacing: number = 4;
  static readonly buildingMinimumWidth: number = 128;
  static readonly buildingMaximumWidth: number = 220;
  static readonly buildingSpacing: number = 5;
}

@ComponentV2
export struct PlannerView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local contentWidth: number = 350;
  // 当天日期文本：跨午夜自动刷新（BUG-024 修复）。
  @Local todayText: string = StrictDates.formatDateParts(StrictDates.todayParts());
  // 派生数据缓存（BUG-015/023 修复）：由 @Monitor 在依赖状态变化时刷新。
  @Local todayCoursesValue: Course[] = [];
  @Local busySlotsValue: Set<number> = new Set<number>();
  @Local pageVisible: boolean = false;
  private dayRefreshTimer: number = -1;

  @Monitor('model.schedule', 'model.usePersonalSchedule')
  onDerivedStateChange(monitor: IMonitor): void {
    this.refreshDerivedState();
  }

  private refreshDerivedState(): void {
    this.todayCoursesValue = this.model.todayCourses();
    this.busySlotsValue = this.model.usePersonalSchedule ?
      this.model.personalBusySlots() : new Set<number>();
  }

  aboutToAppear(): void {
    this.refreshDerivedState();
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.pageVisible = true;
    });
    this.dayRefreshTimer = setInterval(() => {
      const today: string = StrictDates.formatDateParts(StrictDates.todayParts());
      if (today !== this.todayText) {
        this.todayText = today;
        // 跨午夜后课程/空闲节次也要重算（BUG-024 修复）。
        this.refreshDerivedState();
      }
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.dayRefreshTimer >= 0) {
      clearInterval(this.dayRefreshTimer);
      this.dayRefreshTimer = -1;
    }
  }

  private slotColumnCount(): number {
    const available: number = Math.max(this.contentWidth, 200);
    const count: number = Math.floor(
      (available + PlannerLayoutMetrics.slotSpacing) /
      (PlannerLayoutMetrics.slotMinimumWidth + PlannerLayoutMetrics.slotSpacing));
    return Math.max(2, Math.min(count, 6));
  }

  private buildingColumnCount(): number {
    const available: number = Math.max(this.contentWidth, 200);
    const count: number = Math.floor(
      (available + PlannerLayoutMetrics.buildingSpacing) /
      (PlannerLayoutMetrics.buildingMinimumWidth + PlannerLayoutMetrics.buildingSpacing));
    return Math.max(2, Math.min(count, 4));
  }

  private isCompact(): boolean {
    return this.contentWidth < 700;
  }

  private sectionSpacing(): number {
    return this.isCompact() ? 10 : 16;
  }

  private surfacePadding(): number {
    return this.isCompact() ? 12 : 16;
  }

  private sectionTitleSize(): number {
    return this.isCompact() ? 15 : 17;
  }

  build() {
    Scroll() {
      Column({ space: this.sectionSpacing() }) {
        this.header()
        this.querySurface()
        this.slotSurface()
        this.todayCoursesSurface()
        this.buildingsSurface()
        this.resultsSurface()
        this.summarySurface()
        if (this.isCompact()) {
          Blank().height(72)
        }
      }
      .padding({ left: 20, right: 20, top: 20, bottom: 28 })
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.contentWidth = Number(newArea.width) - 40;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .align(Alignment.Top)
    .opacity(this.pageVisible ? 1 : 0)
    .translate({ y: this.pageVisible ? 0 : 6 })
  }

  @Builder
  header() {
    Column({ space: 3 }) {
      Text('Where To Study')
        .fontSize(this.isCompact() ? 11 : 12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.secondaryText())
      Row({ space: 12 }) {
        Text('联动查询')
          .fontSize(this.isCompact() ? 28 : 34)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(14)
            .fontColor([AppTheme.secondaryText()])
          Text(this.todayText)
            .fontSize(this.isCompact() ? 13 : 14)
            .fontColor(AppTheme.secondaryText())
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: this.isCompact() ? 2 : 6 })
  }

  @Builder
  sectionHeader(icon: Resource, title: string) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([AppTheme.text()])
      Text(title)
        .fontSize(this.sectionTitleSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .height(this.isCompact() ? 22 : 24)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  emptyMessage(message: string) {
    Text(message)
      .fontSize(this.isCompact() ? 12.5 : 14)
      .fontColor(AppTheme.secondaryText())
      .width('100%')
      .height(this.isCompact() ? 56 : 72)
      .textAlign(TextAlign.Center)
  }

  @Builder
  querySurface() {
    Column() {
      this.sectionHeader($r('sys.symbol.calendar_badge_clock'), '查询条件')
      Blank().height(6)
      this.campusSegment()
      Blank().height(6)
      Button() {
        Text(this.model.isRefreshingClassrooms ? '正在获取当天空教室…' : '获取空教室信息')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.onPrimary())
      }
      .type(ButtonType.Normal)
      .borderRadius(8)
      .backgroundColor(AppTheme.primaryFill())
      .width('100%')
      .height(36)
      .enabled(!this.model.isRefreshingClassrooms)
      .onClick(() => {
        this.model.refreshClassrooms(true);
      })

      if (this.model.classroomsCache !== null) {
        Text((this.model.isSampleMode() ? '数据源：内置示例数据 · ' : '数据源：移动教务实时接口 · ') +
          this.model.classroomsCache.targetDate)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .margin({ top: 4 })
      }
    }
    .padding(this.surfacePadding())
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  campusSegment() {
    Row() {
      ForEach(['01', '04'], (id: string) => {
        Text(id === '01' ? '西土城' : '沙河')
          .fontSize(14)
          .fontWeight(this.model.queryCampusID === id ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(AppTheme.text())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(28)
          .backgroundColor(this.model.queryCampusID === id ?
            AppTheme.segmentedSelection() : Color.Transparent)
          .borderRadius(6)
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            this.model.selectQueryCampus(id);
          })
      }, (id: string) => 'campus.' + id)
    }
    .width('100%')
    .height(32)
    .padding(2)
    .borderRadius(8)
    .backgroundColor(AppTheme.surfaceVariant())
  }

  @Builder
  slotSurface() {
    Column() {
      this.sectionHeader($r('sys.symbol.clock'), '节次筛选')
      Row({ space: 8 }) {
        Text('使用个人课表排除已有课程')
          .fontSize(14)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.model.usePersonalSchedule })
          .width(40)
          .height(24)
          .selectedColor(AppTheme.primaryFill())
          .onChange((value: boolean) => {
            this.model.setUsePersonalSchedule(value);
          })
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 4, bottom: 4 })

      Row({ space: 6 }) {
        Button('选中空闲')
          .fontSize(13)
          .fontWeight(FontWeight.Regular)
          .fontColor(AppTheme.text())
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .border({ width: 1, color: AppTheme.border() })
          .backgroundColor(AppTheme.surface())
          .onClick(() => {
            this.model.selectFreeSlots();
          })
        Button('清空')
          .fontSize(13)
          .fontWeight(FontWeight.Regular)
          .fontColor(AppTheme.text())
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .border({ width: 1, color: AppTheme.border() })
          .backgroundColor(AppTheme.surface())
          .onClick(() => {
            this.model.clearSelectedSlots();
          })
      }
      .margin({ bottom: 6 })

      Grid() {
        ForEach(this.model.slots, (slot: SlotMetadata) => {
          GridItem() {
            this.slotChip(slot)
          }
        }, (slot: SlotMetadata) => 'slot.' + slot.index.toString())
      }
      .columnsTemplate('repeat(' + this.slotColumnCount().toString() + ', 1fr)')
      .columnsGap(PlannerLayoutMetrics.slotSpacing)
      .rowsGap(PlannerLayoutMetrics.slotSpacing)
      .width('100%')
    }
    .padding(this.surfacePadding())
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  slotChip(slot: SlotMetadata) {
    Column({ space: 2 }) {
      Text('第 ' + slot.label + ' 节')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.model.selectedSlots.has(slot.index) ? AppTheme.onPrimary() : AppTheme.text())
      Text(slot.start + '-' + slot.end)
        .fontSize(10.5)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.model.selectedSlots.has(slot.index) ? AppTheme.onPrimary() : AppTheme.text())
    }
    .width('100%')
    .height(this.isCompact() ? 46 : 54)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.model.selectedSlots.has(slot.index) ? AppTheme.primaryFill() :
      (this.busySlotsValue.has(slot.index) ? '#73E2BC62' : AppTheme.surface()))
    .borderRadius(6)
    .border({
      width: 1,
      color: this.model.selectedSlots.has(slot.index) ? AppTheme.primaryFill() : AppTheme.border()
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      if (!this.busySlotsValue.has(slot.index)) {
        this.model.toggleSlot(slot.index);
      }
    })
  }

  @Builder
  todayCoursesSurface() {
    Column() {
      this.sectionHeader($r('sys.symbol.calendar'), '当天课程')
      if (this.todayCoursesValue.length === 0) {
        this.emptyMessage('暂无本地课程，请在设置中获取/刷新个人课表')
      } else {
        ForEach(this.todayCoursesValue, (course: Course, index: number) => {
          Column() {
            this.courseRow(course)
            if (index < this.todayCoursesValue.length - 1) {
              Divider().color(AppTheme.border())
            }
          }
          .width('100%')
        }, (course: Course, index: number) => 'today-course.' + course.id + '.' + index.toString())
      }
    }
    .padding(this.surfacePadding())
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  courseRow(course: Course) {
    Row({ space: 12 }) {
      Column({ space: 1 }) {
        Text(course.examWeekNumbers.length > 0 ? '试  ' + course.name : course.name)
          .fontSize(this.isCompact() ? 14 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
        Text(course.room.length === 0 ? '地点未标注' : course.room)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(course.timeRange)
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
    }
    .width('100%')
    .padding({ top: this.isCompact() ? 7 : 10, bottom: this.isCompact() ? 7 : 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildingsSurface() {
    Column() {
      this.sectionHeader($r('sys.symbol.building'), '教学楼')
      Blank().height(this.isCompact() ? 8 : 12)
      if (this.model.campusBuildings().length === 0) {
        this.emptyMessage('暂无教学楼，请先获取当天空教室')
      } else {
        Grid() {
          ForEach(this.model.campusBuildings(), (building: string) => {
            GridItem() {
              this.buildingChip(building)
            }
          }, (building: string) => 'building.' + building)
        }
        .columnsTemplate('repeat(' + this.buildingColumnCount().toString() + ', 1fr)')
        .columnsGap(PlannerLayoutMetrics.buildingSpacing)
        .rowsGap(PlannerLayoutMetrics.buildingSpacing)
        .width('100%')
      }
    }
    .padding(this.surfacePadding())
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildingChip(building: string) {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.pin'))
        .fontSize(18)
        .fontColor([this.model.selectedBuildings.has(building) ? AppTheme.onPrimary() : AppTheme.text()])
      Text(building)
        .fontSize(this.isCompact() ? 13 : 15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.model.selectedBuildings.has(building) ? AppTheme.onPrimary() : AppTheme.text())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.isCompact() ? 40 : 46)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.model.selectedBuildings.has(building) ? AppTheme.primaryFill() : AppTheme.surface())
    .borderRadius(6)
    .border({
      width: 1,
      color: this.model.selectedBuildings.has(building) ? AppTheme.primaryFill() : AppTheme.border()
    })
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onClick(() => {
      this.model.toggleBuilding(building);
    })
  }

  @Builder
  resultsSurface() {
    Column() {
      this.sectionHeader($r('sys.symbol.checkmark_circle'), '空教室结果')
      if (this.model.classroomsCache === null) {
        this.emptyMessage('暂无本地空教室数据')
      } else if (this.model.selectedBuildings.size === 0) {
        this.emptyMessage('未选择教学楼')
      } else if (this.model.selectedSlots.size === 0) {
        this.emptyMessage('未选择节次')
      } else if (this.model.matchingRooms().length === 0) {
        this.emptyMessage('暂无匹配空教室')
      } else {
        ForEach(this.model.matchingRooms(), (room: Classroom, index: number) => {
          Column() {
            this.classroomRow(room)
            if (index < this.model.matchingRooms().length - 1) {
              Divider().color(AppTheme.border())
            }
          }
          .width('100%')
        }, (room: Classroom) => room.id)
      }
    }
    .padding(this.surfacePadding())
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  classroomRow(room: Classroom) {
    Column({ space: 3 }) {
      Row({ space: 12 }) {
        Text(room.name)
          .fontSize(this.isCompact() ? 13.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Text(room.size !== null ? room.size.toString() + ' 座' : '座位未知')
          .fontSize(this.isCompact() ? 11 : 12)
          .fontColor(AppTheme.secondaryText())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.selectedRanges())
        .fontSize(this.isCompact() ? 11 : 12)
        .fontColor(AppTheme.primary())
    }
    .width('100%')
    .padding({ top: this.isCompact() ? 7 : 10, bottom: this.isCompact() ? 7 : 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  summarySurface() {
    Column() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(18)
          .fontColor([AppTheme.text()])
        Text('查询概览')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
      }
      .height(24)
      .alignItems(VerticalAlign.Center)
      Row({ space: 0 }) {
        this.summaryItem('当天课程', this.todayCoursesValue.length)
        Divider()
          .vertical(true)
          .height(64)
          .color(AppTheme.border())
        this.summaryItem('个人空闲节次', this.freeSlotCount())
        Divider()
          .vertical(true)
          .height(64)
          .color(AppTheme.border())
        this.summaryItem('匹配教室', this.model.matchingRooms().length)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .padding({ left: 10, right: 10, top: 16, bottom: 16 })
    .width('100%')
    .borderRadius(8)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  summaryItem(label: string, value: number) {
    Column({ space: 1 }) {
      Text(label)
        .fontSize(11.5)
        .fontColor(AppTheme.secondaryText())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(value.toString())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .layoutWeight(1)
    .height(72)
    .padding({ left: 2, right: 2, top: 10, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private freeSlotCount(): number {
    if (this.model.usePersonalSchedule) {
      return this.model.slots.length - this.busySlotsValue.size;
    }
    return this.model.slots.length;
  }

  private selectedRanges(): string {
    const slots: number[] = [];
    for (const slot of this.model.selectedSlots) {
      slots.push(slot);
    }
    slots.sort((a: number, b: number) => a - b);
    if (slots.length === 0) {
      return '未选择';
    }
    const parts: string[] = [];
    let start: number = slots[0];
    let end: number = slots[0];
    for (let i = 1; i < slots.length; i++) {
      if (slots[i] === end + 1) {
        end = slots[i];
      } else {
        parts.push(this.rangeLabel(start, end));
        start = slots[i];
        end = slots[i];
      }
    }
    parts.push(this.rangeLabel(start, end));
    return parts.join(' / ');
  }

  private rangeLabel(start: number, end: number): string {
    const first: SlotMetadata = this.model.slots[start];
    const last: SlotMetadata = this.model.slots[end];
    const label: string = start === end ?
      '第 ' + first.label + ' 节' :
      '第 ' + first.label + '-' + last.label + ' 节';
    return label + ' ' + first.start + '-' + last.end;
  }
}
