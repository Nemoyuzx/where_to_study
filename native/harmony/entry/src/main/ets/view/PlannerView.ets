// 与 iOS 端 PlannerView.swift 对应的空教室联动查询页。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { AdaptiveLayoutPolicy } from '../common/DeviceState';
import { Classroom, Course, SlotMetadata } from '../common/Models';
import { StrictDates } from '../common/StrictDates';
import { PageTitle, SurfaceCard, SectionHeader, EmptyMessage, ChipButton } from './SharedComponents';

export class PlannerLayoutMetrics {
  static readonly slotMinimumWidth: number = 104;
  static readonly slotMaximumWidth: number = 156;
  static readonly slotSpacing: number = 6;
  static readonly buildingMinimumWidth: number = 128;
  static readonly buildingMaximumWidth: number = 220;
  static readonly buildingSpacing: number = 8;
}

@ComponentV2
export struct PlannerView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local contentWidth: number = 350;

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

  build() {
    Scroll() {
      Column({ space: 16 }) {
        this.header()
        if (AdaptiveLayoutPolicy.useTwoColumn(this.contentWidth)) {
          Row({ space: 16 }) {
            Column({ space: 16 }) {
              this.querySurface()
              this.slotSurface()
              this.buildingsSurface()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 16 }) {
              this.todayCoursesSurface()
              this.resultsSurface()
              this.summarySurface()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
        } else {
          Column({ space: 16 }) {
            this.querySurface()
            this.slotSurface()
            this.todayCoursesSurface()
            this.buildingsSurface()
            this.resultsSurface()
            this.summarySurface()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .padding(20)
      .width('100%')
      .constraintSize({ maxWidth: 1200 })
      .alignItems(HorizontalAlign.Start)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.contentWidth = Number(newArea.width) - 40;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .align(Alignment.Top)
  }

  @Builder
  header() {
    Row({ space: 12 }) {
      PageTitle({ eyebrow: 'BUPT Classroom Planner', title: '联动查询' })
        .layoutWeight(1)
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(14)
          .fontColor([AppTheme.secondaryText()])
        Text(StrictDates.formatDateParts(StrictDates.todayParts()))
          .fontSize(14)
          .fontColor(AppTheme.secondaryText())
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }

  @Builder
  querySurface() {
    SurfaceCard() {
      Column({ space: 14 }) {
        SectionHeader({ icon: $r('sys.symbol.calendar_badge_clock'), title: '查询条件' })
        this.campusSegment()
        Button() {
          Row({ space: 8 }) {
            if (this.model.isRefreshingClassrooms) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(AppTheme.onPrimary())
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor([AppTheme.onPrimary()])
            }
            Text(this.model.isRefreshingClassrooms ? '正在获取当天空教室…' : '获取空教室信息')
              .fontSize(14)
              .fontColor(AppTheme.onPrimary())
          }
        }
        .type(ButtonType.Normal)
        .borderRadius(6)
        .backgroundColor(AppTheme.primaryFill())
        .width('100%')
        .height(36)
        .enabled(!this.model.isRefreshingClassrooms)
        .onClick(() => {
          this.model.refreshClassrooms(true);
        })

        if (this.model.classroomStatusMessage.length > 0) {
          Text(this.model.classroomStatusMessage)
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
        } else if (this.model.classroomsCache !== null) {
          Text((this.model.isSampleMode() ? '数据源：内置示例数据 · ' : '数据源：移动教务实时接口 · ') +
            this.model.classroomsCache.targetDate)
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  campusSegment() {
    Row() {
      ForEach(['01', '04'], (id: string) => {
        Text(id === '01' ? '西土城' : '沙河')
          .fontSize(14)
          .fontWeight(this.model.queryCampusID === id ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.model.queryCampusID === id ? AppTheme.onPrimary() : AppTheme.text())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(32)
          .backgroundColor(this.model.queryCampusID === id ?
            AppTheme.primaryFill() : Color.Transparent)
          .borderRadius(6)
          .onClick(() => {
            this.model.selectQueryCampus(id);
          })
      }, (id: string) => 'campus.' + id)
    }
    .width('100%')
    .padding(2)
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.background())
  }

  @Builder
  slotSurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.clock'), title: '节次筛选' })
        Row({ space: 8 }) {
          Text('使用个人课表排除已有课程')
            .fontSize(14)
            .fontColor(AppTheme.text())
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.model.usePersonalSchedule })
            .selectedColor(AppTheme.primaryFill())
            .onChange((value: boolean) => {
              this.model.setUsePersonalSchedule(value);
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('选中空闲')
            .fontSize(13)
            .borderRadius(6)
            .border({ width: 1, color: AppTheme.border() })
            .backgroundColor(AppTheme.background())
            .fontColor(AppTheme.text())
            .onClick(() => {
              this.model.selectFreeSlots();
            })
          Button('清空')
            .fontSize(13)
            .borderRadius(6)
            .border({ width: 1, color: AppTheme.border() })
            .backgroundColor(AppTheme.background())
            .fontColor(AppTheme.text())
            .onClick(() => {
              this.model.clearSelectedSlots();
            })
        }

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
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  slotChip(slot: SlotMetadata) {
    ChipButton({
      selected: this.model.selectedSlots.has(slot.index),
      busy: this.model.usePersonalSchedule && this.model.personalBusySlots().has(slot.index),
      interactive: !(this.model.usePersonalSchedule && this.model.personalBusySlots().has(slot.index)),
      onTap: (): void => {
        this.model.toggleSlot(slot.index);
      }
    }) {
      Column({ space: 3 }) {
        Text('第 ' + slot.label + ' 节')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.model.selectedSlots.has(slot.index) ? AppTheme.onPrimary() : AppTheme.text())
        Text(slot.start + '-' + slot.end)
          .fontSize(11)
          .fontColor(this.model.selectedSlots.has(slot.index) ? AppTheme.onPrimary() : AppTheme.text())
      }
    }
  }

  @Builder
  todayCoursesSurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.calendar'), title: '当天课程' })
        if (this.model.todayCourses().length === 0) {
          EmptyMessage({ message: '暂无本地课程，请在设置中获取/刷新个人课表' })
        } else {
          ForEach(this.model.todayCourses(), (course: Course, index: number) => {
            Column() {
              this.courseRow(course)
              if (index < this.model.todayCourses().length - 1) {
                Divider()
                  .color(AppTheme.border())
                  .margin({ top: 6, bottom: 6 })
              }
            }
            .width('100%')
          }, (course: Course) => course.id)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  courseRow(course: Course) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          if (course.examWeekNumbers.length > 0) {
            Text('试')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
              .padding({ left: 5, right: 5, top: 3, bottom: 3 })
              .borderRadius(4)
              .backgroundColor(AppTheme.accent())
          }
          Text(course.name)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
        }
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
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  buildingsSurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.building'), title: '教学楼' })
        if (this.model.campusBuildings().length === 0) {
          EmptyMessage({ message: '暂无教学楼，请先获取当天空教室' })
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
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  buildingChip(building: string) {
    ChipButton({
      selected: this.model.selectedBuildings.has(building),
      busy: false,
      interactive: true,
      onTap: (): void => {
        this.model.toggleBuilding(building);
      }
    }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.building'))
          .fontSize(14)
          .fontColor([this.model.selectedBuildings.has(building) ? AppTheme.onPrimary() : AppTheme.text()])
        Text(building)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.model.selectedBuildings.has(building) ? AppTheme.onPrimary() : AppTheme.text())
          .maxLines(2)
          .textAlign(TextAlign.Center)
      }
    }
  }

  @Builder
  resultsSurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.checkmark_circle'), title: '空教室结果' })
        if (this.model.classroomsCache === null) {
          EmptyMessage({ message: '暂无本地空教室数据' })
        } else if (this.model.selectedBuildings.size === 0) {
          EmptyMessage({ message: '请选择教学楼' })
        } else if (this.model.selectedSlots.size === 0) {
          EmptyMessage({ message: '请选择节次' })
        } else if (this.model.matchingRooms().length === 0) {
          EmptyMessage({ message: '暂无匹配空教室' })
        } else {
          ForEach(this.model.matchingRooms(), (room: Classroom, index: number) => {
            Column() {
              this.classroomRow(room)
              if (index < this.model.matchingRooms().length - 1) {
                Divider()
                  .color(AppTheme.border())
                  .margin({ top: 6, bottom: 6 })
              }
            }
            .width('100%')
          }, (room: Classroom) => room.id)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  classroomRow(room: Classroom) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(room.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
        Text(this.selectedRanges())
          .fontSize(12)
          .fontColor(AppTheme.primary())
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(room.size !== null ? room.size.toString() + ' 座' : '座位未知')
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  summarySurface() {
    SurfaceCard() {
      Column({ space: 12 }) {
        SectionHeader({ icon: $r('sys.symbol.square_grid_2x2'), title: '查询概览' })
        Row({ space: 0 }) {
          this.summaryItem('当天课程', this.model.todayCourses().length)
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
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  summaryItem(label: string, value: number) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .width('100%')
        .height(30)
      Text(value.toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
    }
    .layoutWeight(1)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  private freeSlotCount(): number {
    if (this.model.usePersonalSchedule) {
      return this.model.slots.length - this.model.personalBusySlots().size;
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
