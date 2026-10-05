// 全平台“查询”入口的 HarmonyOS 原生页面：班车查询 + 重要事件。
import { deviceInfo, settings } from '@kit.BasicServicesKit';
import { accessibility } from '@kit.AccessibilityKit';
import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { DateParts, StrictDates } from '../common/StrictDates';
import { DeadlineVisual } from '../common/DeadlineVisual';
import { PhoneNavigationLayout } from '../common/DeviceState';
import { AppContext } from '../store/AppContext';
import { QuerySession } from './QuerySession';
import { DisclosureClip, PageTitle } from './SharedComponents';
import { ShuttleQueryLayout } from './ShuttleQueryLayout';
import {
  ImportantEventFilter, ImportantEventQueryLogic, QueryPageContract, QueryPageTab
} from '../common/QueryLogic';
import {
  CalendarDailyInfoSources, PublicDeadlineItem, PublicDeadlineKindInfo, PublicDeadlineSource
} from '../net/CalendarDailyInfoClient';
import {
  ShuttleBusClient, ShuttleBusDailyView, ShuttleBusFetching, ShuttleBusLogic,
  ShuttleBusPeriodState, ShuttleBusRow, ShuttleBusSchedule, ShuttleBusService,
  ShuttleBusSnapshot, ShuttleBusSources, ShuttleBusStop
} from '../net/ShuttleBusClient';

@ComponentV2
export struct QueryView {
  @Event onOpenSettings: () => void = () => {};
  @Consumer('appModel') model: AppModel = new AppModel();
  @Param session: QuerySession = new QuerySession();
  @Local tabContentOpacity: number = 1;
  @Local contentWidth: number = 390;
  @Local contentFontScale: number = 1;
  @Local tabPickerWidth: number = 358;
  @Local fullTimetableMotionDuration: number = 160;
  private readonly shuttleClient: ShuttleBusFetching = new ShuttleBusClient();
  private readonly eventScroller: Scroller = new Scroller();
  private readonly regularScroller: Scroller = new Scroller();
  private tabMotionGeneration: number = 0;
  private tabRestoreTimer: number = -1;

  @Monitor('session.searchText', 'session.eventFilterRawValue', 'session.eventCategory', 'session.showEndedEvents',
    'model.importantEventsCatalog', 'model.favoriteDeadlines')
  onEventQueryOrDataChange(monitor: IMonitor): void {
    this.resetEventRendering();
  }

  aboutToAppear(): void {
    this.updateFontScale();
    this.session.attachView();
    this.session.activateScope(this.model.isSampleMode());
    if (this.selectedTab() === QueryPageTab.shuttle) { this.loadShuttle(); }
    this.model.ensureHolidays(StrictDates.todayParts().year, false);
    this.model.loadImportantEvents(false);
    this.tabRestoreTimer = setTimeout(() => {
      this.tabRestoreTimer = -1;
      this.restoreSelectedTabScroll();
    }, 16);
  }

  aboutToDisappear(): void {
    this.saveCurrentTabScroll();
    this.session.detachView();
    this.tabMotionGeneration++;
    if (this.tabRestoreTimer >= 0) {
      clearTimeout(this.tabRestoreTimer);
      this.tabRestoreTimer = -1;
    }
    this.tabContentOpacity = 1;
  }

  @Monitor('model.runtimeMode')
  onRuntimeModeChange(): void {
    this.session.activateScope(this.model.isSampleMode());
    if (this.selectedTab() === QueryPageTab.shuttle) { this.loadShuttle(); }
  }

  private saveCurrentTabScroll(): void {
    if (this.selectedTab() === QueryPageTab.events) {
      return;
    }
    try {
      const offset: number = this.regularScroller.currentOffset().yOffset;
      if (Number.isFinite(offset)) {
        this.session.regularScrollOffsets.set(this.selectedTab(), Math.max(0, offset));
      }
    } catch (e) {
      // 首帧或空页面尚未绑定 Scroller；保留此前记录的偏移量。
    }
  }

  private restoreSelectedTabScroll(): void {
    if (this.selectedTab() === QueryPageTab.events) {
      try {
        this.eventScroller.scrollToIndex(this.session.eventFirstVisibleIndex, false, ScrollAlign.START);
      } catch (e) {
        // 事件列表为空或尚未挂载，不覆盖筛选条件与分页状态。
      }
      return;
    }
    try {
      this.regularScroller.scrollTo({ xOffset: 0,
        yOffset: this.session.regularScrollOffsets.get(this.selectedTab()) ?? 0, animation: false });
    } catch (e) {
      // 刚切换到尚未挂载的查询页时，从顶部开始，不改变已有偏移记录。
    }
  }

  private selectTab(tab: QueryPageTab): void {
    if (tab === this.selectedTab() && this.tabContentOpacity === 1) {
      return;
    }
    const generation: number = ++this.tabMotionGeneration;
    if (this.tabRestoreTimer >= 0) {
      clearTimeout(this.tabRestoreTimer);
      this.tabRestoreTimer = -1;
    }
    this.saveCurrentTabScroll();
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (generation !== this.tabMotionGeneration) {
          return;
        }
        this.session.selectedTabRawValue = tab;
        if (tab === QueryPageTab.shuttle) { this.loadShuttle(); }
        this.tabRestoreTimer = setTimeout(() => {
          this.tabRestoreTimer = -1;
          if (generation !== this.tabMotionGeneration) {
            return;
          }
          this.restoreSelectedTabScroll();
          this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, (): void => {
            this.tabContentOpacity = 1;
          });
        }, 16);
      }
    }, (): void => {
      this.tabContentOpacity = 0;
    });
  }

  private todayIsPublicHoliday(): boolean {
    const today: DateParts = StrictDates.todayParts();
    const date: string = StrictDates.formatDateParts(today);
    return this.model.holidayItems(today.year).some((item): boolean =>
      item.date === date && item.type === 'holiday');
  }

  private shuttleWeekdays(): string[] {
    return ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  }

  private shuttleWeekdayLabel(key: string): string {
    if (key === 'monday') { return '周一'; }
    if (key === 'tuesday') { return '周二'; }
    if (key === 'wednesday') { return '周三'; }
    if (key === 'thursday') { return '周四'; }
    if (key === 'friday') { return '周五'; }
    if (key === 'saturday') { return '周六'; }
    return '周日';
  }

  private shuttleWeekdayDepartures(schedule: ShuttleBusSchedule, key: string,
    separator: string = ' · '): string {
    const rows: ShuttleBusRow[] = ShuttleBusLogic.servicesForToday(schedule, key);
    if (rows.length === 0) {
      return this.model.text('无计划班次');
    }
    return rows.map((row: ShuttleBusRow): string =>
      row.departureTime + ' ' + this.serviceLabel(row.services.get(key))).join(separator);
  }

  private fullTimetablePeriodMetadata(schedule: ShuttleBusSchedule): string {
    const period = schedule.period;
    let dates: string = this.model.text('日期待确认');
    if (period.startDate !== null && period.endDate !== null) {
      dates = period.startDate + ' – ' + period.endDate;
    } else if (period.startDate !== null) {
      dates = period.startDate + ' ' + this.model.text('起');
    } else if (period.endDate !== null) {
      dates = this.model.text('截至') + ' ' + period.endDate;
    }
    const today: string = StrictDates.formatDateParts(StrictDates.todayParts());
    const state: ShuttleBusPeriodState = ShuttleBusLogic.periodState(period, today);
    const stateLabel: string = state === ShuttleBusPeriodState.active ? '当前生效' :
      state === ShuttleBusPeriodState.upcoming ? '即将生效' :
        state === ShuttleBusPeriodState.ended ? '已结束时段' : '时段待确认';
    return dates + ' · ' + this.model.text(stateLabel);
  }

  private reduceFullTimetableMotion(): boolean {
    // Fresh read per user action: no lifecycle listener/timer or preference write.
    try { if (accessibility.isAnimationReduceEnabledSync()) { return true; } } catch (e) {}
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) { return false; }
      const animator: string = settings.getValueSync(context, settings.display.ANIMATOR_DURATION_SCALE, '1');
      const transition: string = settings.getValueSync(context, settings.display.TRANSITION_ANIMATION_SCALE, '1');
      return (animator.length > 0 && Number(animator) === 0) ||
        (transition.length > 0 && Number(transition) === 0);
    } catch (e) { return false; }
  }

  private timetableSectionKey(schedule: ShuttleBusSchedule): string {
    return JSON.stringify([schedule.period.key(), schedule.from, schedule.to]);
  }

  private timetablePeriods(daily: ShuttleBusDailyView): ShuttleBusSchedule[] {
    const seen: Set<string> = new Set<string>();
    return (daily.scheduleNotice?.schedules ?? []).filter((schedule: ShuttleBusSchedule): boolean => {
      if (seen.has(schedule.period.key())) { return false; }
      seen.add(schedule.period.key()); return true;
    });
  }

  private timetableDirections(daily: ShuttleBusDailyView, period: ShuttleBusSchedule): ShuttleBusSchedule[] {
    return (daily.scheduleNotice?.schedules ?? []).filter((schedule: ShuttleBusSchedule): boolean => schedule.period.key() === period.period.key());
  }

  private toggleTimetablePeriod(schedule: ShuttleBusSchedule): void {
    this.fullTimetableMotionDuration = this.reduceFullTimetableMotion() ? 0 : 160;
    this.getUIContext().animateTo({ duration: this.fullTimetableMotionDuration, curve: Curve.EaseOut }, (): void => {
      this.session.toggleShuttlePeriod(schedule.period.key());
    });
  }

  private toggleTimetableSection(schedule: ShuttleBusSchedule): void {
    this.fullTimetableMotionDuration = this.reduceFullTimetableMotion() ? 0 : 160;
    // Only presentation changes; never reload or replace the cached snapshot.
    this.getUIContext().animateTo({ duration: this.fullTimetableMotionDuration, curve: Curve.EaseOut }, (): void => {
      this.session.toggleShuttleSection(this.timetableSectionKey(schedule));
    });
  }

  private selectedTab(): QueryPageTab {
    return this.session.selectedTabRawValue === QueryPageTab.events ? QueryPageTab.events : QueryPageTab.shuttle;
  }

  private eventFilter(): ImportantEventFilter {
    for (const filter of this.availableEventFilters()) {
      if (filter === this.session.eventFilterRawValue) {
        return filter;
      }
    }
    return ImportantEventFilter.all;
  }

  private isWide(): boolean {
    return this.contentWidth >= 760;
  }

  private updateFontScale(): void {
    try {
      this.contentFontScale = ShuttleQueryLayout.fontScale(AppContext.get().config.fontSizeScale ?? 1);
    } catch (e) {
      this.contentFontScale = 1;
    }
  }

  private compactTabs(): boolean {
    return this.contentWidth < 600 || deviceInfo.deviceType === 'phone';
  }

  private tabTitle(tab: QueryPageTab): string {
    return this.model.text(this.compactTabs() ?
      QueryPageContract.compactTabTitle(tab) : QueryPageContract.tabTitle(tab));
  }

  private iconOnlyTabs(): boolean {
    let maximumWidth: number = 0;
    for (const tab of QueryPageContract.tabs) {
      const width: number = this.getUIContext().getMeasureUtils().measureText({
        textContent: this.tabTitle(tab),
        fontSize: (14 * this.contentFontScale).toString() + 'vp',
        fontWeight: FontWeight.Bold
      });
      maximumWidth = Math.max(maximumWidth, this.getUIContext().px2vp(width));
    }
    return QueryPageContract.iconOnlyTabs(this.tabPickerWidth, maximumWidth, this.compactTabs());
  }

  private loadShuttle(force: boolean = false): void {
    void this.session.loadShuttle(this.shuttleClient, this.model.isSampleMode(), force);
  }

  private filteredEvents(): PublicDeadlineItem[] {
    return ImportantEventQueryLogic.filter(this.eventCatalog(), this.session.searchText, this.eventFilter(),
      this.effectiveEventCategory(), this.session.showEndedEvents);
  }

  private visibleEvents(): PublicDeadlineItem[] {
    return ImportantEventQueryLogic.visiblePage(
      this.filteredEvents(), this.session.requestedVisibleEventCount);
  }

  private resetEventRendering(): void {
    this.session.requestedVisibleEventCount = ImportantEventQueryLogic.initialRequestedCount();
    this.session.eventFirstVisibleIndex = 0;
    try {
      this.eventScroller.scrollToIndex(0, false, ScrollAlign.START);
    } catch (e) {
      // 查询页尚未切到重要事件或列表为空时 Scroller 还未绑定；状态仍已完成重置。
    }
  }

  private appendEventPage(endingIndex: number): void {
    const totalCount: number = this.filteredEvents().length;
    const visibleCount: number = ImportantEventQueryLogic.visibleCount(
      totalCount, this.session.requestedVisibleEventCount);
    if (!ImportantEventQueryLogic.shouldAppend(endingIndex, visibleCount, totalCount)) {
      return;
    }
    this.session.requestedVisibleEventCount = ImportantEventQueryLogic.nextRequestedCount(
      this.session.requestedVisibleEventCount, totalCount);
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
      this.eventFilter(), this.session.showEndedEvents);
  }

  private effectiveEventCategory(): string {
    return this.availableEventCategories().indexOf(this.session.eventCategory) >= 0 ?
      this.session.eventCategory : '';
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
      Column({ space: 16 }) {
        this.pageHeader()
        this.tabPicker()
      }
      .width('100%')
      .constraintSize({ maxWidth: ShuttleQueryLayout.maximumPageWidthVp })
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignSelf(ItemAlign.Center)
      .alignItems(HorizontalAlign.Start)
      if (this.selectedTab() !== QueryPageTab.events) {
        Scroll(this.regularScroller) {
          Column({ space: 16 }) {
            this.shuttleContent()
          }
          .width('100%')
          .constraintSize({ maxWidth: ShuttleQueryLayout.maximumPageWidthVp })
          .padding({ left: 16, right: 16, top: 0,
            bottom: this.isWide() ? 28 : PhoneNavigationLayout.minimumContentBottomInsetVp })
          .alignSelf(ItemAlign.Center)
          .alignItems(HorizontalAlign.Start)
        }
        .id('query.' + this.selectedTab() + '.scroll')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .opacity(this.tabContentOpacity)
      } else {
        Column() {
          this.eventsContent()
        }
        .width('100%')
        .layoutWeight(1)
        .opacity(this.tabContentOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.background())
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width);
      this.updateFontScale();
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  pageHeader() {
    Row({ space: 10 }) {
      PageTitle({ eyebrow: 'Where To Study', title: this.model.text('信息查询') })
      .layoutWeight(1)
      if (this.selectedTab() === QueryPageTab.events) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(17)
            .fontColor([AppTheme.primary()])
        }
        .type(ButtonType.Normal)
        .width(38)
        .height(38)
        .responseRegion({ x: -3, y: -3, width: 44, height: 44 })
        .borderRadius(8)
        .backgroundColor(AppTheme.surfaceVariant())
        .id('query.events.reload')
        .accessibilityText(this.model.text('刷新重要事件'))
        .enabled(!this.model.isLoadingImportantEvents)
        .onClick(() => {
          this.model.loadImportantEvents(true);
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tabPicker() {
    this.tabPickerRow(this.iconOnlyTabs())
  }

  @Builder
  tabPickerRow(iconOnly: boolean) {
    Row() {
      ForEach(QueryPageContract.tabs, (tab: QueryPageTab) => {
        this.tabLabel(tab, iconOnly)
      }, (tab: QueryPageTab) => 'query-tab.' + tab)
    }
    .width('100%')
    .constraintSize({ minHeight: ControlMetrics.height })
    .padding(3)
    .borderRadius(11)
    .backgroundColor(AppTheme.surfaceVariant())
    .alignSelf(ItemAlign.Center)
    .id('query.tab_picker')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.tabPickerWidth = Number(newArea.width);
    })
  }

  @Builder
  tabLabel(tab: QueryPageTab, iconOnly: boolean) {
    Button() {
      Row({ space: 4 }) {
        if (this.compactTabs() || iconOnly) {
          SymbolGlyph(QueryPageContract.tabSymbol(tab))
            .fontSize('20vp')
            .fontColor([this.selectedTab() === tab ? AppTheme.primary() : AppTheme.text()])
            .accessibilityLevel('no')
        }
        if (!iconOnly) {
          Text(this.tabTitle(tab))
            .fontSize((14 * this.contentFontScale).toString() + 'vp')
            .fontWeight(this.selectedTab() === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(AppTheme.text())
            .maxLines(1)
            .accessibilityLevel('no')
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .type(ButtonType.Normal)
    .layoutWeight(1)
    .constraintSize({ minHeight: 44 })
    .padding({ left: 6, right: 6, top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor(this.selectedTab() === tab ? AppTheme.surface() : Color.Transparent)
    .accessibilityText(this.model.text(QueryPageContract.tabTitle(tab)))
    .accessibilitySelected(this.selectedTab() === tab)
    .id(QueryPageContract.tabAccessibilityID(tab))
    .onClick(() => { this.selectTab(tab); })
  }

  @Builder
  shuttleContent() {
    if (this.session.shuttleLoading && this.session.shuttleSnapshot === null) {
      this.shuttleMessage('正在读取最新班车信息', '正在读取后勤部最新通知与当前生效时刻表。', false)
    } else if (this.session.shuttleSnapshot === null) {
      this.shuttleMessage('班车信息暂不可用', this.session.shuttleError, true)
    } else {
      this.shuttleSnapshotContent(ShuttleBusLogic.dailyView(this.session.shuttleSnapshot as ShuttleBusSnapshot))
    }
  }

  @Builder
  shuttleSnapshotContent(daily: ShuttleBusDailyView) {
    Column({ space: 16 }) {
      this.shuttleStatusCard(daily)
      this.shuttleScheduleGrid(daily)
      this.shuttleFullTimetable(daily)
      this.shuttleSourceCard()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  shuttleMessage(title: string, detail: string, retry: boolean) {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.bus_fill'))
        .fontSize(24)
        .fontColor([AppTheme.primary()])
      Text(this.model.text(title))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.text())
        .textAlign(TextAlign.Center)
      Text(this.model.text(detail))
        .fontSize(13)
        .fontColor(AppTheme.secondaryText())
        .textAlign(TextAlign.Center)
      if (retry) {
        Button(this.model.text('重新加载'))
          .fontColor(AppTheme.primary())
          .backgroundColor(AppTheme.surfaceVariant())
          .borderRadius(8)
          .onClick(() => this.loadShuttle(true))
      } else {
        LoadingProgress().width(22).height(22).color(AppTheme.primary())
      }
    }
    .padding(24)
    .width('100%')
    .constraintSize({ minHeight: 180 })
    .borderRadius(10)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  shuttleStatusCard(daily: ShuttleBusDailyView) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.bus_fill'))
          .fontSize(24)
          .fontColor([AppTheme.primary()])
        Column({ space: 4 }) {
          Text(this.model.text(this.todayIsPublicHoliday() ?
            '法定节假日，班车安排以学校通知为准' : ShuttleQueryLayout.statusTitle(daily)))
            .id('query.shuttle.status')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
            .width('100%')
          Text(this.model.text('今日共 {routes} 个方向、{departures} 个计划班次')
            .replace('{routes}', daily.schedules.length.toString())
            .replace('{departures}', ShuttleQueryLayout.departureCount(daily).toString()))
            .fontSize(14)
            .fontColor(AppTheme.secondaryText())
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(17)
            .fontColor([AppTheme.primary()])
        }
        .type(ButtonType.Normal)
        .width(36)
        .height(ControlMetrics.height)
        .responseRegion({ x: -4, y: -4, width: 44, height: 44 })
        .borderRadius(8)
        .backgroundColor(AppTheme.surfaceVariant())
        .id('query.reload')
        .accessibilityText(this.model.text('刷新班车信息'))
        .enabled(!this.session.shuttleLoading)
        .onClick(() => this.loadShuttle(true))
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      if (this.session.shuttleSnapshot?.status !== 'healthy') {
        Text(this.model.text('当前展示最近一次成功同步的缓存'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      }
      if (this.session.shuttleError.length > 0) {
        Text(this.model.text('班车刷新失败，继续显示上次获取的数据。') + ' ' + this.session.shuttleError)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      }
      Text(this.model.text('数据生成时间：') + (this.session.shuttleSnapshot?.generatedAt ?? ''))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
      if (this.session.shuttleFetchedAtMillis > 0) {
        Text(this.model.text('本机获取时间：') + StrictDates.formatFetchedAt(this.session.shuttleFetchedAtMillis))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      }
      if (daily.usingFallback && daily.state === ShuttleBusPeriodState.active) {
        Text(this.model.text('最新通知尚未完成结构化识别，以下为上一份可安全展示的时刻表，仅供对照。'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .lineHeight(17)
          .width('100%')
      }
      if (daily.latestNotice !== null) {
        Divider().strokeWidth(1).color(AppTheme.border())
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text(daily.latestNotice?.title ?? '')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.text())
              .width('100%')
            Text(this.model.text('后勤部通知 · ') + (daily.latestNotice?.publishedAt ?? ''))
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          SymbolGlyph($r('sys.symbol.arrow_up_right'))
            .fontSize(18)
            .fontColor([AppTheme.primary()])
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .alignItems(VerticalAlign.Top)
        .accessibilityText(this.model.text('查看班车通知原文'))
        .onClick(() => {
          this.openURL(daily.latestNotice?.sourceURL ?? ShuttleBusSources.sourcePage);
        })
      }
      ForEach(daily.scheduleNotice?.notes ?? [], (note: string) => {
        Text(note)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      }, (note: string) => 'shuttle-note.' + note)
      ForEach(ShuttleQueryLayout.unmatchedStops(daily), (stop: ShuttleBusStop) => {
        Text(this.model.text('发车地点：') + stop.campus + ' · ' + stop.location)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
      }, (stop: ShuttleBusStop) => 'shuttle-stop.' + stop.campus + '.' + stop.location)
      Text(this.model.text('法定节假日班车安排以学校通知为准，请提前五分钟候车。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
        .width('100%')
      if (this.todayIsPublicHoliday()) {
        Text(this.model.text('今日为法定节假日，班车不一定运行；请以学校放假安排为准，放假期间无班车。'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .lineHeight(17)
          .width('100%')
          .id('query.shuttle.holiday.warning')
      }
    }
    .padding(16)
    .width('100%')
    .borderRadius(10)
    .border({ width: 0.5, color: AppTheme.border() })
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
      Column({ space: ShuttleQueryLayout.routeGapVp }) {
        ForEach(ShuttleQueryLayout.rows(daily.schedules,
          ShuttleQueryLayout.routeColumns(this.contentWidth, this.contentFontScale)),
          (schedules: ShuttleBusSchedule[]) => {
            Row({ space: ShuttleQueryLayout.routeGapVp }) {
              ForEach(ShuttleQueryLayout.columnIndices(
                ShuttleQueryLayout.routeColumns(this.contentWidth, this.contentFontScale)),
                (column: number) => {
                  if (column < schedules.length) {
                    Column() {
                      this.shuttleRouteCard(schedules[column], daily)
                    }
                    .layoutWeight(1)
                  } else {
                    Column() {}
                    .layoutWeight(1)
                    .height(1)
                    .hitTestBehavior(HitTestMode.None)
                    .accessibilityLevel('no')
                  }
                }, (column: number) => 'route-column.' + column)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (schedules: ShuttleBusSchedule[]) => this.routeRowKey(schedules, daily))
      }
      .width('100%')
      .direction(Direction.Ltr)
    }
  }

  @Builder
  shuttleFullTimetable(daily: ShuttleBusDailyView) {
    if (daily.scheduleNotice !== null && daily.scheduleNotice.schedules.length > 0) {
      Column({ space: 12 }) {
        Text(this.model.text('完整班车时刻表'))
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppTheme.text()).width('100%')
        Text(daily.scheduleNotice.title)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
          .width('100%')
          Column({ space: 12 }) {
            ForEach(this.timetablePeriods(daily), (period: ShuttleBusSchedule) => {
              Column({ space: 5 }) {
                Button() {
                  Row({ space: 8 }) {
                    Column({ space: 5 }) {
                      Text(period.period.label).fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary()).width('100%')
                      Text(this.fullTimetablePeriodMetadata(period)).fontSize(12).fontColor(AppTheme.secondaryText()).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(18).fontColor([AppTheme.secondaryText()])
                      .rotate({ angle: this.session.isShuttlePeriodExpanded(period.period.key()) ? 180 : 0 }).accessibilityLevel('no')
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                  .type(ButtonType.Normal).padding(0).width('100%').constraintSize({ minHeight: ControlMetrics.height })
                  .backgroundColor(Color.Transparent).accessibilityText(period.period.label)
                  .accessibilityStateDescription(this.model.text(this.session.isShuttlePeriodExpanded(period.period.key()) ? '已展开' : '已折叠'))
                  .onClick(() => this.toggleTimetablePeriod(period))
                DisclosureClip({ expanded: this.session.isShuttlePeriodExpanded(period.period.key()) }) {
                  Column({ space: 10 }) {
                    ForEach(this.timetableDirections(daily, period), (schedule: ShuttleBusSchedule) => {
              Column({ space: 5 }) {
                Button() {
                  Row({ space: 8 }) {
                    Column({ space: 5 }) {
                      Text(schedule.from + ' → ' + schedule.to)
                        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary()).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(18).fontColor([AppTheme.secondaryText()])
                      .rotate({ angle: this.session.isShuttleSectionExpanded(this.timetableSectionKey(schedule)) ? 180 : 0 })
                      .accessibilityLevel('no')
                  }.width('100%').alignItems(VerticalAlign.Center)
                }
                  .type(ButtonType.Normal).padding(0).width('100%').constraintSize({ minHeight: ControlMetrics.height })
                  .backgroundColor(Color.Transparent)
                  .accessibilityText(schedule.period.label + ' · ' + schedule.from + ' → ' + schedule.to)
                  .accessibilityStateDescription(this.model.text(this.session.isShuttleSectionExpanded(this.timetableSectionKey(schedule)) ? '已展开' : '已折叠'))
                  .onClick(() => this.toggleTimetableSection(schedule))
                DisclosureClip({ expanded: this.session.isShuttleSectionExpanded(this.timetableSectionKey(schedule)) }) {
                Column({ space: 5 }) {
                if (this.isWide()) {
                  Row({ space: 6 }) {
                    ForEach(this.shuttleWeekdays(), (weekday: string) => {
                      Column({ space: 5 }) {
                        Text(this.model.text(this.shuttleWeekdayLabel(weekday)))
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(AppTheme.primary())
                        Text(this.shuttleWeekdayDepartures(schedule, weekday, '\n'))
                          .fontSize(11)
                          .fontColor(AppTheme.text())
                          .width('100%')
                      }
                      .layoutWeight(1)
                      .padding(6)
                      .borderRadius(6)
                      .backgroundColor(AppTheme.background())
                      .alignItems(HorizontalAlign.Start)
                    }, (weekday: string) => schedule.period.key() + schedule.from + schedule.to + weekday)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                } else {
                  ForEach(this.shuttleWeekdays(), (weekday: string) => {
                    Row({ space: 10 }) {
                      Text(this.model.text(this.shuttleWeekdayLabel(weekday)))
                        .fontSize(12)
                        .fontColor(AppTheme.secondaryText())
                        .width(34)
                      Text(this.shuttleWeekdayDepartures(schedule, weekday))
                        .fontSize(12)
                        .fontColor(AppTheme.text())
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)
                  }, (weekday: string) => schedule.period.key() + schedule.from + schedule.to + weekday)
                }
                }.width('100%').alignItems(HorizontalAlign.Start)
                }
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor(AppTheme.surfaceVariant())
              .alignItems(HorizontalAlign.Start)
            }, (schedule: ShuttleBusSchedule) =>
              schedule.period.key() + schedule.from + schedule.to)
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }
              }.width('100%').padding(12).borderRadius(8).backgroundColor(AppTheme.surfaceVariant())
                .alignItems(HorizontalAlign.Start)
            }, (period: ShuttleBusSchedule) => period.period.key())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .id('query.shuttle.full-timetable.content')
      }
      .padding(16)
      .width('100%')
      .borderRadius(10)
      .border({ width: 0.5, color: AppTheme.border() })
      .backgroundColor(AppTheme.surface())
      .alignItems(HorizontalAlign.Start)
      .id('query.shuttle.full-timetable')
      .direction(Direction.Ltr)
    }
  }

  @Builder
  shuttleRouteCard(schedule: ShuttleBusSchedule, daily: ShuttleBusDailyView) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.arrow_left_arrow_right'))
          .fontSize(18)
          .fontColor([AppTheme.primary()])
        Column({ space: 3 }) {
          Text(schedule.from + ' → ' + schedule.to)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.text())
            .width('100%')
          Text(this.routePeriodLabel(schedule))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
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
        Column({ space: ShuttleQueryLayout.departureGapVp }) {
          ForEach(ShuttleQueryLayout.rows(ShuttleBusLogic.servicesForToday(schedule, daily.weekdayKey),
            ShuttleQueryLayout.departureColumns(this.contentWidth, this.contentFontScale)),
            (departures: ShuttleBusRow[]) => {
              Row({ space: ShuttleQueryLayout.departureGapVp }) {
                ForEach(ShuttleQueryLayout.columnIndices(
                  ShuttleQueryLayout.departureColumns(this.contentWidth, this.contentFontScale)),
                  (column: number) => {
                    if (column < departures.length) {
                      Column() {
                        this.shuttleDepartureRow(departures[column], daily.weekdayKey,
                          this.isNextDeparture(departures[column], schedule, daily))
                      }
                      .layoutWeight(1)
                    } else {
                      Column() {}
                      .layoutWeight(1)
                      .height(1)
                      .hitTestBehavior(HitTestMode.None)
                      .accessibilityLevel('no')
                    }
                  }, (column: number) => 'departure-column.' + column)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (departures: ShuttleBusRow[]) => this.departureRowKey(departures, daily))
        }
        .width('100%')
      }
    }
    .padding(ShuttleQueryLayout.cardPaddingVp)
    .width('100%')
    .borderRadius(10)
    .border({ width: 0.5, color: AppTheme.border() })
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  shuttleDepartureRow(row: ShuttleBusRow, weekdayKey: string, isNext: boolean) {
    Column({ space: 2 }) {
      Row({ space: 4 }) {
        Text(row.departureTime)
          .fontSize(14)
          .fontFeature('"tnum" 1')
          .fontWeight(FontWeight.Bold)
          .fontColor(isNext ? AppTheme.textOnPrimaryBlend(0.12, AppTheme.state.dark) : AppTheme.text())
        if (isNext) {
          Circle().width(5).height(5).fill(AppTheme.primary())
        }
      }
      .justifyContent(FlexAlign.Center)
      Text(this.serviceLabel(row.services.get(weekdayKey)))
        .fontSize(11)
        .fontColor(isNext ? AppTheme.textOnPrimaryBlend(0.12, AppTheme.state.dark, true) :
          AppTheme.secondaryText())
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: 4, right: 4, top: 7, bottom: 7 })
    .borderRadius(8)
    .backgroundColor(isNext ? AppTheme.primaryWithAlpha(0.12, AppTheme.state.dark) : AppTheme.background())
    .alignItems(HorizontalAlign.Center)
    .accessibilityGroup(true)
    .accessibilityText(row.departureTime + ' ' + this.serviceLabel(row.services.get(weekdayKey)) +
      (isNext ? ' · ' + this.model.text('下一班') : ''))
  }

  @Builder
  eventsContent() {
    Column({ space: 10 }) {
      TextInput({ placeholder: this.model.text('搜索名称、主办方、分类、地点或来源'), text: this.session.searchText })
        .id('query.events.search')
        .type(InputType.Normal)
        .fontSize(14)
        .fontColor(AppTheme.text())
        .placeholderColor(AppTheme.secondaryText())
        .backgroundColor(AppTheme.inputSurface())
        .border({ width: 1, color: AppTheme.border() })
        .borderRadius(8)
        .height(38)
        .padding({ left: 12, right: 12 })
        .width('100%')
        .enableKeyboardOnFocus(true)
        .onChange((value: string) => {
          this.session.searchText = value;
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
                this.session.eventFilterRawValue = filter;
                this.session.eventCategory = '';
              })
          }, (filter: ImportantEventFilter) => 'query-filter.' + filter)
        }
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
                this.session.eventCategory = '';
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
                  this.session.eventCategory = category;
                })
            }, (category: string) => 'query-category.' + category)
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      Row({ space: 8 }) {
        Text(this.model.text('显示已结束或归档事件'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.session.showEndedEvents })
          .id('query.events.show_ended')
          .selectedColor(AppTheme.primaryFill())
          .width(46)
          .height(26)
          .onChange((value: boolean) => {
            this.session.showEndedEvents = value;
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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onScrollIndex((start: number, end: number, center: number) => {
          if (this.tabContentOpacity >= 0.99) {
            this.session.eventFirstVisibleIndex = start;
          }
          this.appendEventPage(end);
        })
      }
      this.sourceCard('第三方来源：Contest DDL 主源、较新镜像及备用 API；校内通知由脚本从学校内部网站公开通知页提取整理。',
        CalendarDailyInfoSources.deadlinePrimaryPage)
      this.sourceCard('Contest DDL 较新镜像数据', CalendarDailyInfoSources.deadlineMirror)
      this.sourceCard('Contest DDL 备用 API', CalendarDailyInfoSources.deadlineBackup)
    }
    .layoutWeight(1)
    .width('100%')
    .constraintSize({ maxWidth: 1100 })
    .padding({
      left: 16,
      right: 16,
      bottom: this.isWide() ? 18 : PhoneNavigationLayout.minimumContentBottomInsetVp
    })
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
        const ownerGeneration: number = this.tabMotionGeneration;
        const uiContext = this.getUIContext();
        const showFeedback = (message: string): void => {
          if (ownerGeneration !== this.tabMotionGeneration || this.selectedTab() !== QueryPageTab.events) {
            return;
          }
          try {
            uiContext.getPromptAction().showToast({ message: this.model.text(message) });
          } catch (e) {
            // 页面已离开时不覆盖模型中的准确失败原因。
          }
        };
        this.model.toggleFavoriteDeadline(item).then((changed: boolean): void => {
          if (!changed) {
            showFeedback(AppModel.favoriteDeadlineLimitMessage);
          }
        }, (): void => {
          this.model.statusMessage = '无法保存收藏';
          showFeedback('无法保存收藏');
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
  shuttleSourceCard() {
    Row({ space: 9 }) {
      SymbolGlyph($r('sys.symbol.info_circle'))
        .fontSize(16)
        .fontColor([AppTheme.textOnPrimaryBlend(0.08, AppTheme.state.dark)])
      Text(this.model.text('第三方来源：北京邮电大学后勤部公开通知，由 Where To Study 服务解析整理，仅供参考，请以官方原文为准。'))
        .fontSize(12)
        .fontColor(AppTheme.textOnPrimaryBlend(0.08, AppTheme.state.dark, true))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(16)
        .fontColor([AppTheme.textOnPrimaryBlend(0.08, AppTheme.state.dark)])
    }
    .id('query.shuttle.source')
    .padding(12)
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .borderRadius(10)
    .backgroundColor(AppTheme.primaryWithAlpha(0.08, AppTheme.state.dark))
    .alignItems(VerticalAlign.Top)
    .accessibilityText(this.model.text('查看数据来源'))
    .onClick(() => this.openURL(ShuttleBusSources.sourcePage))
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

  private routePeriodLabel(schedule: ShuttleBusSchedule): string {
    if (schedule.period.startDate !== null && schedule.period.endDate !== null) {
      return schedule.period.startDate + ' — ' + schedule.period.endDate;
    }
    if (schedule.period.startDate !== null) {
      return schedule.period.startDate + this.model.text(' 起');
    }
    return schedule.period.label;
  }

  private routeRowKey(schedules: ShuttleBusSchedule[], daily: ShuttleBusDailyView): string {
    return schedules.map((schedule: ShuttleBusSchedule): string =>
      schedule.period.key() + schedule.from + schedule.to).join('|') +
      this.departureRowKey([], daily);
  }

  private departureRowKey(rows: ShuttleBusRow[], daily: ShuttleBusDailyView): string {
    return rows.map((row: ShuttleBusRow): string =>
      row.departureTime + this.serviceLabel(row.services.get(daily.weekdayKey))).join('|') +
      daily.date + (this.session.shuttleSnapshot?.generatedAt ?? '') + AppTheme.colorKey() +
      this.model.languageSettingRawValue + this.contentFontScale.toString() + ':' +
      ShuttleQueryLayout.routeColumns(this.contentWidth, this.contentFontScale).toString() + ':' +
      ShuttleQueryLayout.departureColumns(this.contentWidth, this.contentFontScale).toString();
  }

  private isNextDeparture(row: ShuttleBusRow, schedule: ShuttleBusSchedule,
    daily: ShuttleBusDailyView): boolean {
    if (this.todayIsPublicHoliday()) {
      return false;
    }
    const rows: ShuttleBusRow[] = ShuttleBusLogic.servicesForToday(schedule, daily.weekdayKey);
    return rows.indexOf(row) === ShuttleBusLogic.nextDepartureIndex(rows, daily.state);
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
