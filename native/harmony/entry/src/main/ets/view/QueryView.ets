// 全平台“查询”入口的 HarmonyOS 原生页面：班车查询 + 重要事件。
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { DeadlineVisual } from '../common/DeadlineVisual';
import { AppContext } from '../store/AppContext';
import {
  ImportantEventFilter, ImportantEventQueryLogic, QueryPageContract, QueryPageTab
} from '../common/QueryLogic';
import {
  CalendarDailyInfoSources, PublicDeadlineItem, PublicDeadlineKindInfo, PublicDeadlineSource
} from '../net/CalendarDailyInfoClient';
import {
  ShuttleBusClient, ShuttleBusDailyView, ShuttleBusFetching, ShuttleBusLogic,
  ShuttleBusPeriodState, ShuttleBusRow, ShuttleBusSchedule, ShuttleBusService,
  ShuttleBusSnapshot, ShuttleBusSources
} from '../net/ShuttleBusClient';

@ComponentV2
export struct QueryView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Local selectedTabRawValue: string = QueryPageTab.shuttle;
  @Local eventFilterRawValue: string = ImportantEventFilter.all;
  @Local eventCategory: string = '';
  @Local showEndedEvents: boolean = false;
  @Local searchText: string = '';
  @Local requestedVisibleEventCount: number = ImportantEventQueryLogic.initialRequestedCount();
  @Local contentWidth: number = 390;
  @Local shuttleSnapshot: ShuttleBusSnapshot | null = null;
  @Local shuttleLoading: boolean = false;
  @Local shuttleError: string = '';
  private readonly shuttleClient: ShuttleBusFetching = new ShuttleBusClient();
  private readonly eventScroller: Scroller = new Scroller();

  @Monitor('searchText', 'eventFilterRawValue', 'eventCategory', 'showEndedEvents',
    'model.importantEventsCatalog', 'model.favoriteDeadlines')
  onEventQueryOrDataChange(monitor: IMonitor): void {
    this.resetEventRendering();
  }

  aboutToAppear(): void {
    this.loadShuttle();
    this.model.loadImportantEvents(false);
  }

  private selectedTab(): QueryPageTab {
    return this.selectedTabRawValue === QueryPageTab.events ? QueryPageTab.events : QueryPageTab.shuttle;
  }

  private eventFilter(): ImportantEventFilter {
    for (const filter of this.availableEventFilters()) {
      if (filter === this.eventFilterRawValue) {
        return filter;
      }
    }
    return ImportantEventFilter.all;
  }

  private isWide(): boolean {
    return this.contentWidth >= 760;
  }

  private loadShuttle(): void {
    if (this.shuttleLoading) {
      return;
    }
    this.shuttleLoading = true;
    this.shuttleError = '';
    this.shuttleClient.fetch().then((snapshot: ShuttleBusSnapshot): void => {
      this.shuttleSnapshot = snapshot;
    }).catch((error: Error): void => {
      this.shuttleError = error.message.length > 0 ? error.message : '班车信息暂时无法读取。';
    }).finally((): void => {
      this.shuttleLoading = false;
    });
  }

  private filteredEvents(): PublicDeadlineItem[] {
    return ImportantEventQueryLogic.filter(this.eventCatalog(), this.searchText, this.eventFilter(),
      this.effectiveEventCategory(), this.showEndedEvents);
  }

  private visibleEvents(): PublicDeadlineItem[] {
    return ImportantEventQueryLogic.visiblePage(
      this.filteredEvents(), this.requestedVisibleEventCount);
  }

  private resetEventRendering(): void {
    this.requestedVisibleEventCount = ImportantEventQueryLogic.initialRequestedCount();
    try {
      this.eventScroller.scrollToIndex(0, false, ScrollAlign.START);
    } catch (e) {
      // 查询页尚未切到重要事件或列表为空时 Scroller 还未绑定；状态仍已完成重置。
    }
  }

  private appendEventPage(endingIndex: number): void {
    const totalCount: number = this.filteredEvents().length;
    const visibleCount: number = ImportantEventQueryLogic.visibleCount(
      totalCount, this.requestedVisibleEventCount);
    if (!ImportantEventQueryLogic.shouldAppend(endingIndex, visibleCount, totalCount)) {
      return;
    }
    this.requestedVisibleEventCount = ImportantEventQueryLogic.nextRequestedCount(
      this.requestedVisibleEventCount, totalCount);
  }

  private eventCatalog(): PublicDeadlineItem[] {
    return ImportantEventQueryLogic.mergeCatalog(
      this.model.importantEventsCatalog, this.model.favoriteDeadlines);
  }

  private availableEventFilters(): ImportantEventFilter[] {
    return ImportantEventQueryLogic.availableFilters(this.eventCatalog());
  }

  private availableEventCategories(): string[] {
    return ImportantEventQueryLogic.availableCategories(
      this.eventCatalog(),
      this.eventFilter(), this.showEndedEvents);
  }

  private effectiveEventCategory(): string {
    return this.availableEventCategories().indexOf(this.eventCategory) >= 0 ?
      this.eventCategory : '';
  }

  private openURL(url: string | null): void {
    if (url === null) {
      return;
    }
    try {
      AppContext.get().openLink(url);
    } catch (e) {
      // 保持在本页；系统无法打开链接时不丢失查询状态。
    }
  }

  build() {
    Column({ space: 0 }) {
      this.pageHeader()
      this.tabPicker()
      if (this.selectedTab() === QueryPageTab.shuttle) {
        this.shuttleContent()
      } else {
        this.eventsContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width);
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('Where To Study')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.secondaryText())
        Text(this.model.text('查询'))
          .fontSize(this.isWide() ? 28 : 24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(17)
          .fontColor([AppTheme.primary()])
      }
      .type(ButtonType.Normal)
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor(AppTheme.surface())
      .id('query.reload')
      .enabled(this.selectedTab() === QueryPageTab.shuttle ?
        !this.shuttleLoading : !this.model.isLoadingImportantEvents)
      .onClick(() => {
        if (this.selectedTab() === QueryPageTab.shuttle) {
          this.loadShuttle();
        } else {
          this.model.loadImportantEvents(true);
        }
      })
    }
    .width('100%')
    .height(this.isWide() ? 70 : 58)
    .padding({ left: this.isWide() ? 24 : 10, right: this.isWide() ? 24 : 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.surface())
  }

  @Builder
  tabPicker() {
    Row() {
      ForEach(QueryPageContract.tabs, (tab: QueryPageTab) => {
        Text(this.model.text(QueryPageContract.tabTitle(tab)))
          .fontSize(14)
          .fontWeight(this.selectedTab() === tab ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.selectedTab() === tab ? AppTheme.onPrimary() : AppTheme.text())
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(34)
          .borderRadius(8)
          .backgroundColor(this.selectedTab() === tab ? AppTheme.primaryFill() : Color.Transparent)
          .id(QueryPageContract.tabAccessibilityID(tab))
          .animation({ duration: 160, curve: Curve.EaseOut })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, (): void => {
              this.selectedTabRawValue = tab;
            });
          })
      }, (tab: QueryPageTab) => 'query-tab.' + tab)
    }
    .width(this.isWide() ? 520 : 'calc(100% - 28vp)')
    .height(40)
    .padding(3)
    .margin({ top: 12, bottom: 12 })
    .borderRadius(11)
    .backgroundColor(AppTheme.surfaceVariant())
    .alignSelf(ItemAlign.Center)
  }

  @Builder
  shuttleContent() {
    if (this.shuttleLoading && this.shuttleSnapshot === null) {
      this.loadingMessage('正在读取最新班车信息')
    } else if (this.shuttleSnapshot === null) {
      this.errorMessage(this.shuttleError, (): void => this.loadShuttle())
    } else {
      Scroll() {
        Column({ space: 14 }) {
          this.shuttleStatusCard(ShuttleBusLogic.dailyView(this.shuttleSnapshot as ShuttleBusSnapshot))
          this.shuttleScheduleGrid(ShuttleBusLogic.dailyView(this.shuttleSnapshot as ShuttleBusSnapshot))
          this.sourceCard('第三方来源：北京邮电大学后勤部公开通知；由 Where To Study 服务端每小时整理，结果仅供参考。',
            ShuttleBusSources.sourcePage)
        }
        .width('100%')
        .constraintSize({ maxWidth: 1100 })
        .padding({ left: 16, right: 16, top: 2, bottom: this.isWide() ? 28 : 92 })
        .alignSelf(ItemAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
  }

  @Builder
  shuttleStatusCard(daily: ShuttleBusDailyView) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(this.model.text('今日校区班车'))
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
          Text(daily.date + ' · ' + this.model.text(this.periodStateTitle(daily.state)))
            .fontSize(13)
            .fontColor(AppTheme.secondaryText())
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.shuttleSnapshot?.status === 'healthy' ? this.model.text('数据最新') :
          this.model.text('缓存数据'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.primary())
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(11)
          .backgroundColor(AppTheme.selection())
      }
      .width('100%')
      if (daily.period !== null) {
        Text(this.periodLabel(daily))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .width('100%')
      }
      if (daily.usingFallback && daily.state === ShuttleBusPeriodState.active) {
        Text(this.model.text('最新通知尚未完成结构化识别，以下为上一份可安全展示的时刻表，仅供对照。'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .lineHeight(17)
          .width('100%')
      }
      Text(this.model.text('法定节假日班车安排以学校通知为准，请提前五分钟候车。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .lineHeight(17)
        .width('100%')
      if (daily.latestNotice !== null) {
        Text(daily.latestNotice?.title ?? '')
          .fontSize(13)
          .fontColor(AppTheme.primary())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .onClick(() => {
            this.openURL(daily.latestNotice?.sourceURL ?? ShuttleBusSources.sourcePage);
          })
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(10)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  shuttleScheduleGrid(daily: ShuttleBusDailyView) {
    if (daily.state !== ShuttleBusPeriodState.active || daily.schedules.length === 0) {
      Column({ space: 6 }) {
        Text(this.model.text('今日暂无生效的班车时刻表'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
        Text(this.model.text('不会使用未来或历史时刻表代替今日安排，请以后勤部最新通知为准。'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .lineHeight(17)
          .textAlign(TextAlign.Center)
      }
      .padding(18)
      .width('100%')
      .borderRadius(10)
      .border({ width: 1, color: AppTheme.border() })
      .backgroundColor(AppTheme.surface())
    } else {
      Grid() {
        ForEach(daily.schedules, (schedule: ShuttleBusSchedule) => {
          GridItem() {
            this.shuttleRouteCard(schedule, daily)
          }
        }, (schedule: ShuttleBusSchedule) => schedule.period.key() + '.' + schedule.from + '.' + schedule.to)
      }
      .columnsTemplate(this.isWide() ? '1fr 1fr' : '1fr')
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
    }
  }

  @Builder
  shuttleRouteCard(schedule: ShuttleBusSchedule, daily: ShuttleBusDailyView) {
    Column({ space: 9 }) {
      Text(schedule.from + ' → ' + schedule.to)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
        .width('100%')
      if (daily.scheduleNotice?.stopLocation(schedule.from) !== null) {
        Text(this.model.text('发车地点：') + (daily.scheduleNotice?.stopLocation(schedule.from) ?? ''))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      }
      if (ShuttleBusLogic.servicesForToday(schedule, daily.weekdayKey).length === 0) {
        Text(this.model.text('今日暂无计划班车'))
          .fontSize(14)
          .fontColor(AppTheme.secondaryText())
          .padding({ top: 12, bottom: 12 })
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        ForEach(ShuttleBusLogic.servicesForToday(schedule, daily.weekdayKey),
          (row: ShuttleBusRow, index: number) => {
            this.shuttleDepartureRow(row, daily.weekdayKey,
              index === ShuttleBusLogic.nextDepartureIndex(
                ShuttleBusLogic.servicesForToday(schedule, daily.weekdayKey), daily.state))
          }, (row: ShuttleBusRow) => schedule.from + '.' + row.departureTime)
      }
    }
    .padding(15)
    .width('100%')
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  shuttleDepartureRow(row: ShuttleBusRow, weekdayKey: string, isNext: boolean) {
    Row({ space: 10 }) {
      Text(row.departureTime)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(isNext ? AppTheme.onPrimary() : AppTheme.text())
        .width(62)
      Text(this.serviceLabel(row.services.get(weekdayKey)))
        .fontSize(13)
        .fontColor(isNext ? AppTheme.onPrimary() : AppTheme.secondaryText())
        .layoutWeight(1)
      if (isNext) {
        Text(this.model.text('下一班'))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.onPrimary())
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: 9, right: 9 })
    .borderRadius(7)
    .backgroundColor(isNext ? AppTheme.primaryFill() : AppTheme.surfaceVariant())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  eventsContent() {
    Column({ space: 10 }) {
      TextInput({ placeholder: this.model.text('搜索名称、主办方、分类、地点或来源'), text: this.searchText })
        .id('query.events.search')
        .type(InputType.Normal)
        .fontSize(14)
        .fontColor(AppTheme.text())
        .placeholderColor(AppTheme.secondaryText())
        .backgroundColor(AppTheme.surface())
        .border({ width: 1, color: AppTheme.border() })
        .borderRadius(8)
        .height(38)
        .padding({ left: 12, right: 12 })
        .width('100%')
        .enableKeyboardOnFocus(true)
        .onChange((value: string) => {
          this.searchText = value;
        })
      Scroll() {
        Row({ space: 7 }) {
          ForEach(this.availableEventFilters(), (filter: ImportantEventFilter) => {
            Text(this.model.text(QueryPageContract.filterTitle(filter)))
              .fontSize(12)
              .fontWeight(this.eventFilter() === filter ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.eventFilter() === filter ? AppTheme.onPrimary() : AppTheme.text())
              .height(30)
              .padding({ left: 11, right: 11 })
              .textAlign(TextAlign.Center)
              .borderRadius(15)
              .backgroundColor(this.eventFilter() === filter ?
                AppTheme.primaryFill() : AppTheme.surfaceVariant())
              .onClick(() => {
                this.eventFilterRawValue = filter;
                this.eventCategory = '';
              })
          }, (filter: ImportantEventFilter) => 'query-filter.' + filter)
        }
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      if (this.availableEventCategories().length > 0) {
        Scroll() {
          Row({ space: 7 }) {
            Text(this.model.text('全部分类'))
              .fontSize(12)
              .fontWeight(this.effectiveEventCategory().length === 0 ?
                FontWeight.Bold : FontWeight.Regular)
              .fontColor(this.effectiveEventCategory().length === 0 ?
                AppTheme.onPrimary() : AppTheme.text())
              .height(28)
              .padding({ left: 10, right: 10 })
              .textAlign(TextAlign.Center)
              .borderRadius(14)
              .backgroundColor(this.effectiveEventCategory().length === 0 ?
                AppTheme.primaryFill() : AppTheme.surface())
              .onClick(() => {
                this.eventCategory = '';
              })
            ForEach(this.availableEventCategories(), (category: string) => {
              Text(category)
                .fontSize(12)
                .fontWeight(this.effectiveEventCategory() === category ?
                  FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.effectiveEventCategory() === category ?
                  AppTheme.onPrimary() : AppTheme.text())
                .height(28)
                .padding({ left: 10, right: 10 })
                .textAlign(TextAlign.Center)
                .borderRadius(14)
                .backgroundColor(this.effectiveEventCategory() === category ?
                  AppTheme.primaryFill() : AppTheme.surface())
                .onClick(() => {
                  this.eventCategory = category;
                })
            }, (category: string) => 'query-category.' + category)
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }
      Row({ space: 8 }) {
        Text(this.model.text('显示已结束或归档事件'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.showEndedEvents })
          .id('query.events.show_ended')
          .selectedColor(AppTheme.primaryFill())
          .width(46)
          .height(26)
          .onChange((value: boolean) => {
            this.showEndedEvents = value;
          })
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)
      if (this.model.isLoadingImportantEvents && this.model.importantEventsCatalog.length === 0) {
        this.loadingMessage('正在读取重要事件')
      } else if (this.model.importantEventsError.length > 0 &&
        this.model.importantEventsCatalog.length === 0 &&
        this.model.favoriteDeadlines.length === 0) {
        this.errorMessage(this.model.importantEventsError,
          (): void => this.model.loadImportantEvents(true))
      } else if (this.visibleEvents().length === 0) {
        Column({ space: 6 }) {
          Text(this.model.text('没有符合条件的重要事件'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.text())
          Text(this.model.text('请调整搜索关键词或分类筛选。'))
            .fontSize(13)
            .fontColor(AppTheme.secondaryText())
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 9, scroller: this.eventScroller }) {
          ForEach(this.visibleEvents(), (item: PublicDeadlineItem) => {
            ListItem() {
              this.eventRow(item)
            }
          }, (item: PublicDeadlineItem) => this.model.favoriteDeadlineKey(item))
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .onScrollIndex((start: number, end: number, center: number) => {
          this.appendEventPage(end);
        })
      }
      this.sourceCard('第三方来源：Contest DDL 公开活动与校内竞赛通知；校内通知由脚本从学校内部网站公开通知页提取整理。',
        CalendarDailyInfoSources.deadlinePrimaryPage)
    }
    .layoutWeight(1)
    .width('100%')
    .constraintSize({ maxWidth: 1100 })
    .padding({ left: 16, right: 16, bottom: this.isWide() ? 18 : 78 })
    .alignSelf(ItemAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  eventRow(item: PublicDeadlineItem) {
    Row({ space: 10 }) {
      Column({ space: 5 }) {
        Row({ space: 7 }) {
          Text(this.model.text(item.source === PublicDeadlineSource.schoolNotice ?
            '校内竞赛通知' : PublicDeadlineKindInfo.title(item.kind)))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(DeadlineVisual.colorForItem(item))
          Text(this.deadlineLabel(item.deadline))
            .fontSize(11)
            .fontColor(AppTheme.secondaryText())
        }
        .width('100%')
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (item.organizer !== null) {
          Text(item.organizer ?? '')
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (this.eventMetadataLine(item).length > 0) {
          Text(this.eventMetadataLine(item))
            .fontSize(11)
            .fontColor(AppTheme.secondaryText())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        this.openURL(item.officialURL);
      })
      Button() {
        SymbolGlyph(this.model.isFavoriteDeadline(item) ?
          $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(19)
          .fontColor([this.model.isFavoriteDeadline(item) ?
            AppTheme.assignment() : AppTheme.secondaryText()])
      }
      .type(ButtonType.Normal)
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.model.text(this.model.isFavoriteDeadline(item) ? '取消收藏' : '收藏'))
      .onClick(() => {
        this.model.toggleFavoriteDeadline(item).catch(() => {
          this.model.statusMessage = '无法保存收藏';
        });
      })
    }
    .padding(14)
    .width('100%')
    .borderRadius(10)
    .border({ width: 1, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  loadingMessage(message: string) {
    Column({ space: 8 }) {
      Text(this.model.text(message))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.text())
      Text(this.model.text('请稍候…'))
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  errorMessage(message: string, retry: () => void) {
    Column({ space: 10 }) {
      Text(this.model.text(message.length > 0 ? message : '数据暂时无法读取。'))
        .fontSize(14)
        .fontColor(AppTheme.secondaryText())
        .textAlign(TextAlign.Center)
      Button(this.model.text('重新加载'))
        .fontSize(13)
        .fontColor(AppTheme.onPrimary())
        .backgroundColor(AppTheme.primaryFill())
        .borderRadius(8)
        .onClick(() => {
          retry();
        })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  sourceCard(message: string, url: string) {
    Text(this.model.text(message))
      .fontSize(11)
      .fontColor(AppTheme.secondaryText())
      .lineHeight(16)
      .width('100%')
      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
      .onClick(() => {
        this.openURL(url);
      })
  }

  private periodStateTitle(state: ShuttleBusPeriodState): string {
    if (state === ShuttleBusPeriodState.active) {
      return '当前执行';
    }
    if (state === ShuttleBusPeriodState.upcoming) {
      return '尚未开始';
    }
    if (state === ShuttleBusPeriodState.ended) {
      return '历史时段';
    }
    if (state === ShuttleBusPeriodState.inactive) {
      return '今日无生效时刻表';
    }
    return '时段待确认';
  }

  private periodLabel(daily: ShuttleBusDailyView): string {
    if (daily.period === null) {
      return '';
    }
    if (daily.period.startDate !== null && daily.period.endDate !== null) {
      return daily.period.startDate + ' — ' + daily.period.endDate;
    }
    if (daily.period.startDate !== null) {
      return daily.period.startDate + this.model.text(' 起');
    }
    return daily.period.label;
  }

  private serviceLabel(service: ShuttleBusService | undefined): string {
    if (service === undefined) {
      return this.model.text('计划班次');
    }
    return service.vehicle + ' × ' + service.count.toString();
  }

  private deadlineLabel(value: string): string {
    return value.length >= 16 ? value.substring(0, 10) + ' ' + value.substring(11, 16) : value;
  }

  private eventMetadataLine(item: PublicDeadlineItem): string {
    const fields: string[] = [];
    if (item.categories.length > 0) {
      fields.push(item.categories.slice(0, 3).join(' · '));
    }
    if (item.level !== null) {
      fields.push(item.level);
    }
    if (item.location !== null) {
      fields.push(item.location);
    }
    if (item.sourceName !== null) {
      fields.push(item.sourceName);
    }
    return fields.join(' · ');
  }
}
