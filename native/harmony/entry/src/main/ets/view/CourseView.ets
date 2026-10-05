import { deviceInfo } from '@kit.BasicServicesKit';
import { accessibility } from '@kit.AccessibilityKit';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { CoursePageContract, CoursePageTab, CourseQMPlusScope,
  CourseCloudScope, CourseSubmissionCounts, UCloudCourseGroup } from '../common/CourseLogic';
import { AppLanguage } from '../common/AppLocalization';
import { PhoneNavigationLayout } from '../common/DeviceState';
import { AppModel } from '../model/AppModel';
import { DisclosureClip, PageTitle } from './SharedComponents';
import { AssignmentQueryView, ExamQueryView } from './AcademicQueryViews';
import { GradeQueryView } from './GradeQueryView';
import { CourseSession } from './CourseSession';
import { QMPlusSession } from './QMPlusSession';
import { QMPlusActivity, QMPlusCourse } from '../net/QMPlusSnapshot';
import { AppContext } from '../store/AppContext';
import { AssignmentDeadlineItem, CalendarDailyInfoSources } from '../net/CalendarDailyInfoClient';
import { ShuttleQueryLayout } from './ShuttleQueryLayout';
import { LengthMetrics } from '@kit.ArkUI';

@ComponentV2
export struct CourseView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Event onOpenSettings: () => void = () => {};
  @Param session: CourseSession = new CourseSession();
  @Param qmPlusSession: QMPlusSession = new QMPlusSession();
  @Local contentWidth: number = 390;
  @Local tabPickerWidth: number = 358;
  @Local tabContentOpacity: number = 1;
  private readonly contentScroller: Scroller = new Scroller();
  private tabMotionGeneration: number = 0;
  private tabRestoreTimer: number = -1;

  @Monitor('model.account', 'model.hasSavedPassword')
  onSavedAcademicAccountChanged(monitor: IMonitor): void {
    if (this.selectedTab() === CoursePageTab.current && this.model.canPreserveSavedPassword()) {
      if (this.session.skipNextAutomaticCourseLoad) { this.session.skipNextAutomaticCourseLoad = false; }
      else { void this.model.loadCloudCourseDirectory(false); }
    }
  }

  @Monitor('qmPlusSession.snapshot')
  onQMPlusSnapshotChanged(monitor: IMonitor): void {
    this.session.visibleQMActivities = 40;
  }

  @Monitor('model.qmplusEnabled')
  onQMplusEnabledChanged(monitor: IMonitor): void {
    if (!this.model.qmplusEnabled && this.session.selectedCourseSource === 'qmplus') { this.closeCourse(); }
  }

  aboutToAppear(): void {
    if (!this.model.qmplusEnabled && this.session.selectedCourseSource === 'qmplus') { this.closeCourse(); }
    if (this.selectedTab() === CoursePageTab.current) {
      if (this.session.skipNextAutomaticCourseLoad) { this.session.skipNextAutomaticCourseLoad = false; }
      else { void this.model.loadCloudCourseDirectory(false); }
    }
    this.tabRestoreTimer = setTimeout((): void => {
      this.tabRestoreTimer = -1;
      this.restoreScroll();
    }, 16);
  }

  aboutToDisappear(): void {
    this.saveScroll();
    this.tabMotionGeneration++;
    if (this.tabRestoreTimer >= 0) {
      clearTimeout(this.tabRestoreTimer);
      this.tabRestoreTimer = -1;
    }
    this.tabContentOpacity = 1;
  }

  private selectedTab(): CoursePageTab {
    if (this.session.selectedTabRawValue === CoursePageTab.grades) { return CoursePageTab.grades; }
    if (this.session.selectedTabRawValue === CoursePageTab.exams) { return CoursePageTab.exams; }
    if (this.session.selectedTabRawValue === CoursePageTab.assignments) { return CoursePageTab.assignments; }
    return CoursePageTab.current;
  }

  private localized(chinese: string, english: string): string {
    const translated: string = this.model.text(chinese);
    return this.model.resolvedLanguage() === AppLanguage.english && translated === chinese ? english : translated;
  }

  private cloudCourseGroups(): UCloudCourseGroup[] {
    return CourseCloudScope.groups(this.model.cloudCourses);
  }

  private selectedCloudCourse(): UCloudCourseGroup | undefined {
    return this.cloudCourseGroups().find((course: UCloudCourseGroup): boolean =>
      course.courseIDs.includes(this.session.selectedCourseID));
  }

  private selectedQMPlusCourse(): QMPlusCourse | undefined {
    return CourseQMPlusScope.courses(this.qmPlusSession.snapshot).find((course: QMPlusCourse): boolean =>
      course.id === this.session.selectedCourseID);
  }

  private cloudAssignments(course: UCloudCourseGroup): AssignmentDeadlineItem[] {
    return CourseCloudScope.groupAssignmentsFor(course, this.model.cloudCourses,
      this.model.assignmentCatalog, this.model.assignmentCatalogFetchedAt.length > 0);
  }

  private cloudSubmissionCounts(course: UCloudCourseGroup): CourseSubmissionCounts {
    return CourseCloudScope.submissionCounts(this.cloudAssignments(course));
  }

  private saveScroll(): void {
    try {
      const offset: number = this.contentScroller.currentOffset().yOffset;
      if (Number.isFinite(offset)) {
        if (this.session.selectedCourseSource.length > 0) {
          this.session.detailScrollOffset = Math.max(0, offset);
        } else {
          this.session.scrollOffsets.set(this.selectedTab(), Math.max(0, offset));
        }
      }
    } catch (e) {
      // 首帧尚未挂载 Scroll，保留旧位置。
    }
  }

  private restoreScroll(): void {
    try {
      this.contentScroller.scrollTo({ xOffset: 0,
        yOffset: this.session.selectedCourseSource.length > 0 ? this.session.detailScrollOffset :
          (this.session.scrollOffsets.get(this.selectedTab()) ?? 0), animation: false });
    } catch (e) {
      // 内容尚未挂载时由 ArkUI 使用初始位置。
    }
  }

  private restoreAfterOwnerChange(): void {
    const generation: number = ++this.tabMotionGeneration;
    if (this.tabRestoreTimer >= 0) {
      clearTimeout(this.tabRestoreTimer);
    }
    this.tabRestoreTimer = setTimeout((): void => {
      this.tabRestoreTimer = -1;
      if (generation === this.tabMotionGeneration) { this.restoreScroll(); }
    }, 16);
  }

  private openCourse(source: string, id: string): void {
    this.saveScroll();
    this.session.openCourse(source, id);
    this.restoreAfterOwnerChange();
  }

  private closeCourse(): void {
    this.session.closeCourse();
    this.restoreAfterOwnerChange();
  }

  private selectTab(tab: CoursePageTab): void {
    if (tab === this.selectedTab() && this.tabContentOpacity === 1) { return; }
    const generation: number = ++this.tabMotionGeneration;
    if (this.tabRestoreTimer >= 0) {
      clearTimeout(this.tabRestoreTimer);
      this.tabRestoreTimer = -1;
    }
    this.saveScroll();
    this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut,
      onFinish: (): void => {
        if (generation !== this.tabMotionGeneration) { return; }
        this.session.selectedTabRawValue = tab;
        if (tab === CoursePageTab.current) {
          void this.model.loadCloudCourseDirectory(false);
        }
        this.tabRestoreTimer = setTimeout((): void => {
          this.tabRestoreTimer = -1;
          if (generation !== this.tabMotionGeneration) { return; }
          this.restoreScroll();
          this.getUIContext().animateTo({ duration: 130, curve: Curve.EaseOut }, (): void => {
            this.tabContentOpacity = 1;
          });
        }, 16);
      }
    }, (): void => { this.tabContentOpacity = 0; });
  }

  private compactTabs(): boolean {
    return this.contentWidth < 600 || deviceInfo.deviceType === 'phone';
  }

  private tabTitle(tab: CoursePageTab): string {
    return this.model.text(this.compactTabs() ? CoursePageContract.compactTitle(tab) :
      CoursePageContract.title(tab));
  }

  private iconOnlyTabs(): boolean {
    let maximumWidth: number = 0;
    for (const tab of CoursePageContract.tabs) {
      const width: number = this.getUIContext().getMeasureUtils().measureText({
        textContent: this.tabTitle(tab), fontSize: '14vp', fontWeight: FontWeight.Bold
      });
      maximumWidth = Math.max(maximumWidth, this.getUIContext().px2vp(width));
    }
    return CoursePageContract.iconOnlyTabs(this.tabPickerWidth, maximumWidth, this.compactTabs());
  }

  private overviewCount(): string {
    const parts: string[] = [];
    if (this.model.cloudCoursesFetchedAt.length > 0) {
      parts.push(this.localized('教学云 ', 'Teaching Cloud ') + this.cloudCourseGroups().length.toString() +
        this.localized(' 门', ' courses'));
    }
    if (this.model.qmplusEnabled && this.qmPlusSession.snapshot !== null && !this.model.isSampleMode()) {
      parts.push('QMplus EBU ' + CourseQMPlusScope.courses(this.qmPlusSession.snapshot).length.toString() +
        this.localized(' 门', ' courses'));
    }
    return parts.join(' · ');
  }

  private toggleCourseInline(source: string, id: string): void {
    let reduced: boolean = false;
    try { reduced = accessibility.isAnimationReduceEnabledSync(); } catch (e) {}
    this.getUIContext().animateTo({ duration: reduced ? 0 : 160, curve: Curve.EaseOut }, (): void => {
      this.session.toggleExpanded(source, id);
    });
  }

  private inlineActivityMetadata(item: QMPlusActivity): string {
    const parts: string[] = [this.model.text(item.kind === 'quiz' ? '测验' : '作业')];
    if (item.kind === 'assignment') {
      if (item.dueAt !== null) { parts.push(this.model.text('截止时间：') + this.qmTime(item.dueAt)); }
      if (item.cutoffAt !== null) { parts.push(this.model.text('最终截止：') + this.qmTime(item.cutoffAt)); }
      if (item.dueAt === null && item.cutoffAt === null) { parts.push(this.model.text('截止时间未公布')); }
    } else {
      if (item.opensAt !== null) { parts.push(this.model.text('开放时间：') + this.qmTime(item.opensAt)); }
      if (item.closesAt !== null) { parts.push(this.model.text('关闭时间：') + this.qmTime(item.closesAt)); }
      if (item.timeLimitSeconds !== null) { parts.push(this.model.text('限时：') + item.timeLimitSeconds.toString() + this.model.text(' 秒')); }
    }
    if (item.status.length > 0 && item.status !== 'unknown') { parts.push(this.model.text('状态：') + item.status); }
    if (item.rawTimeText.length > 0) { parts.push(item.rawTimeText); }
    return parts.join(' · ');
  }

  @Builder
  inlineCloudAssignments(course: UCloudCourseGroup) {
    if (this.model.assignmentCatalogFetchedAt.length === 0) {
      Text(this.localized('该课作业尚未在本机同步；可到“作业”栏目手动刷新。',
        'Assignments for this course have not been synced here. Refresh manually in Assignments.'))
        .fontSize(13).fontColor(AppTheme.secondaryText()).width('100%')
    } else if (this.cloudAssignments(course).length === 0) {
      Text(this.localized('当前缓存没有可确认归属该课的作业条目。',
        'No assignment in the current cache can be reliably attributed to this course.'))
        .fontSize(13).fontColor(AppTheme.secondaryText()).width('100%')
    }
    ForEach(this.cloudAssignments(course).slice(0, this.session.visibleCloudAssignments), (item: AssignmentDeadlineItem) => {
      Column({ space: 5 }) {
        Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppTheme.text()).width('100%')
        Text([this.model.text('截止时间：') + item.deadline, item.status ?? ''].filter(
          (value: string): boolean => value.length > 0).join(' · '))
          .fontSize(12).fontColor(AppTheme.secondaryText()).width('100%')
      }.padding(10).width('100%').borderRadius(8).backgroundColor(AppTheme.surfaceVariant())
    }, (item: AssignmentDeadlineItem) => 'inline.cloud.' + course.id + '.' + CourseCloudScope.assignmentKey(item))
    if (this.cloudAssignments(course).length > this.session.visibleCloudAssignments) {
      Button(this.model.text('加载更多')).height(ControlMetrics.height)
        .onClick(() => { this.session.visibleCloudAssignments += 40; })
    }
  }

  @Builder
  inlineQMActivities(course: QMPlusCourse) {
    if (this.visibleQMActivitiesFor(course.id).length === 0) {
      Text(this.model.text('当前缓存没有可确认归属该课的作业条目。'))
        .fontSize(13).fontColor(AppTheme.secondaryText()).width('100%')
    }
    ForEach(this.visibleQMActivitiesFor(course.id).slice(0, this.session.visibleQMActivities), (item: QMPlusActivity) => {
      Column({ space: 5 }) {
        Text(item.title.length > 0 ? item.title : item.id).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text()).width('100%')
        Text(this.inlineActivityMetadata(item)).fontSize(12).fontColor(AppTheme.secondaryText()).width('100%')
      }.padding(10).width('100%').borderRadius(8).backgroundColor(AppTheme.surfaceVariant())
    }, (item: QMPlusActivity) => 'inline.qm.' + course.id + '.' + item.kind + '.' + item.id)
    if (this.visibleQMActivitiesFor(course.id).length > this.session.visibleQMActivities) {
      Button(this.model.text('加载更多')).height(ControlMetrics.height)
        .onClick(() => { this.session.visibleQMActivities += 40; })
    }
  }

  build() {
    Column({ space: 0 }) {
      Column({ space: 16 }) {
        if (this.session.selectedCourseSource.length > 0) {
          Row({ space: 10 }) {
            Button(this.localized('返回', 'Back'))
              .type(ButtonType.Normal)
              .height(ControlMetrics.height)
              .backgroundColor(AppTheme.surfaceVariant())
              .fontColor(AppTheme.primary())
              .id('courses.detail.back')
              .onClick(() => this.closeCourse())
            Text(this.localized('课程详情', 'Course Details'))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.text())
              .layoutWeight(1)
          }
          .width('100%')
        } else {
          PageTitle({ eyebrow: 'Where To Study', title: this.model.text('课程') })
          if (this.overviewCount().length > 0) {
            Text(this.overviewCount())
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
              .id('courses.overview.count')
          }
          this.tabPicker()
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: ShuttleQueryLayout.maximumPageWidthVp })
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignSelf(ItemAlign.Center)
      .alignItems(HorizontalAlign.Start)

      Scroll(this.contentScroller) {
        Column({ space: 16 }) {
          if (this.session.selectedCourseSource.length > 0) {
            this.courseDetailContent()
          } else if (this.selectedTab() === CoursePageTab.current) {
            this.currentCoursesContent()
          } else if (this.selectedTab() === CoursePageTab.grades) {
            GradeQueryView({ onOpenSettings: this.onOpenSettings })
              .direction(Direction.Ltr)
          } else if (this.selectedTab() === CoursePageTab.exams) {
            ExamQueryView({ onOpenSettings: this.onOpenSettings })
              .direction(Direction.Ltr)
          } else {
            AssignmentQueryView({ onOpenSettings: this.onOpenSettings })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: ShuttleQueryLayout.maximumPageWidthVp })
        .padding({ left: 16, right: 16, top: 0,
          bottom: this.contentWidth >= 760 ? 28 : PhoneNavigationLayout.minimumContentBottomInsetVp })
        .alignSelf(ItemAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .opacity(this.tabContentOpacity)
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
  tabPicker() {
    Row() {
      ForEach(CoursePageContract.tabs, (tab: CoursePageTab) => {
        this.tabLabel(tab, this.iconOnlyTabs())
      }, (tab: CoursePageTab) => CoursePageContract.accessibilityID(tab))
    }
    .width('100%')
    .constraintSize({ minHeight: ControlMetrics.height })
    .padding(3)
    .borderRadius(11)
    .backgroundColor(AppTheme.surfaceVariant())
    .id('courses.tab_picker')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.tabPickerWidth = Number(newArea.width);
    })
  }

  @Builder
  tabLabel(tab: CoursePageTab, iconOnly: boolean) {
    Button() {
      Row({ space: 4 }) {
        if (this.compactTabs() || iconOnly) {
          SymbolGlyph(CoursePageContract.symbol(tab))
            .fontSize('20vp')
            .fontColor([this.selectedTab() === tab ? AppTheme.primary() : AppTheme.text()])
            .accessibilityLevel('no')
        }
        if (!iconOnly) {
          Text(this.tabTitle(tab))
            .fontSize('14vp')
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
    .accessibilityText(this.model.text(CoursePageContract.title(tab)))
    .accessibilitySelected(this.selectedTab() === tab)
    .id(CoursePageContract.accessibilityID(tab))
    .onClick(() => this.selectTab(tab))
  }

  @Builder
  currentCoursesContent() {
    Column({ space: 12 }) {
      Text(this.model.text('当前课程'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      this.cloudCourseSection()
      if (this.model.isSampleMode()) {
        Text(this.model.text('示例模式不展示或连接真实 QMplus 数据。'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else if (this.model.qmplusEnabled) {
        this.qmPlusSection()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  courseDetailContent() {
    if (this.session.selectedCourseSource === 'ucloud' && this.selectedCloudCourse() !== undefined) {
      this.cloudCourseDetail(this.selectedCloudCourse() as UCloudCourseGroup)
    } else if (this.session.selectedCourseSource === 'qmplus' && this.selectedQMPlusCourse() !== undefined) {
      this.qmPlusCourseDetail(this.selectedQMPlusCourse() as QMPlusCourse)
    } else {
      Text(this.localized('课程资料已更新，请返回列表。', 'Course data changed. Return to the list.'))
        .fontSize(14)
        .fontColor(AppTheme.secondaryText())
    }
  }

  private openAssignmentsTab(): void {
    this.saveScroll();
    this.session.closeCourse();
    this.session.selectedTabRawValue = CoursePageTab.assignments;
    this.restoreAfterOwnerChange();
  }

  @Builder
  cloudCourseDetail(course: UCloudCourseGroup) {
    Column({ space: 12 }) {
      Text(course.name ?? course.id)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      if (course.teacherNames.length > 0) {
        Text(course.teacherNames.join('、'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      }
      Text(this.model.text('教学云当前课程'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
      if (this.model.assignmentCatalogFetchedAt.length === 0) {
        Text(this.localized('该课作业尚未在本机同步；可到“作业”栏目手动刷新。',
          'Assignments for this course have not been synced here. Refresh manually in Assignments.'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else {
        Text(this.model.text('更新时间：') + this.model.assignmentCatalogFetchedAt)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
        if (this.model.assignmentCatalogError.length > 0) {
          Text(this.model.text('正在显示此前查询结果。'))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
        }
        if (this.cloudAssignments(course).length === 0) {
          Text(this.localized('当前缓存没有可确认归属该课的作业条目。',
            'No assignment in the current cache can be reliably attributed to this course.'))
            .fontSize(13)
            .fontColor(AppTheme.secondaryText())
        }
        ForEach(this.cloudAssignments(course).slice(0, this.session.visibleCloudAssignments),
          (item: AssignmentDeadlineItem) => {
            Column({ space: 5 }) {
              Text(item.title)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.text())
              Text(this.model.text('截止时间：') + item.deadline)
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
              if (item.status !== null) {
                Text(this.model.text('状态：') + (item.status ?? ''))
                  .fontSize(12)
                  .fontColor(AppTheme.secondaryText())
              }
            }
            .width('100%')
            .padding(11)
            .borderRadius(8)
            .backgroundColor(AppTheme.surfaceVariant())
            .alignItems(HorizontalAlign.Start)
          }, (item: AssignmentDeadlineItem) => CourseCloudScope.assignmentKey(item) + '|' + item.deadline)
        if (this.cloudAssignments(course).length > this.session.visibleCloudAssignments) {
          Button(this.model.text('加载更多'))
            .type(ButtonType.Normal)
            .height(ControlMetrics.height)
            .backgroundColor(AppTheme.surfaceVariant())
            .fontColor(AppTheme.primary())
            .onClick(() => { this.session.visibleCloudAssignments += 40; })
        }
      }
      Button(this.localized('查看作业栏目', 'Open Assignments'))
        .type(ButtonType.Normal)
        .height(ControlMetrics.height)
        .backgroundColor(AppTheme.surfaceVariant())
        .fontColor(AppTheme.primary())
        .onClick(() => this.openAssignmentsTab())
      Button(this.model.text('打开教学云平台'))
        .type(ButtonType.Normal)
        .height(ControlMetrics.height)
        .backgroundColor(AppTheme.surfaceVariant())
        .fontColor(AppTheme.primary())
        .onClick(() => {
          try { AppContext.get().openLink(CalendarDailyInfoSources.assignments); } catch (e) {}
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(10)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  qmPlusCourseDetail(course: QMPlusCourse) {
    Column({ space: 12 }) {
      this.qmPlusCourseCard(course)
      if (course.currentTermStatus !== 'current') {
        Text(this.localized('该课程尚未确认为当前学期，未自动读取其作业或测验详情。',
          'This course is not verified as current, so its assignment and quiz details were not fetched.'))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
      }
      if (this.courseActivityCount(course.id) > this.session.visibleQMActivities) {
        Button(this.model.text('加载更多'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .onClick(() => { this.session.visibleQMActivities += 40; })
      }
      if (course.url !== null) {
        Button(this.localized('打开 QMplus 官方课程页', 'Open Official QMplus Course'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .onClick(() => this.qmPlusSession.openLogin(course.url ?? undefined))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cloudCourseSection() {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
      Text(this.model.text('教学云当前课程'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Button(this.model.text('刷新'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .enabled(!this.model.cloudCoursesLoading && !this.model.isSampleMode())
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .id('courses.cloud.refresh')
          .onClick(() => { void this.model.loadCloudCourseDirectory(true); })
      }
      .width('100%')
      if (!this.model.canPreserveSavedPassword() && !this.model.isSampleMode()) {
        Text(this.model.text('请先在账户设置中保存教务账号和密码。'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
        Button(this.model.text('前往个人账户'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .onClick(() => this.onOpenSettings())
      }
      if (this.model.cloudCoursesFetchedAt.length > 0) {
        Text(this.model.text('更新时间：') + this.model.cloudCoursesFetchedAt)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
      }
      if (this.model.cloudCoursesError.length > 0) {
        Text(this.model.text(this.model.cloudCoursesError))
          .fontSize(13)
          .fontColor(AppTheme.danger())
      }
      if (this.model.cloudCoursesLoading && this.model.cloudCourses.length === 0) {
        LoadingProgress().width(24).height(24).color(AppTheme.primary())
      } else if (this.model.cloudCourses.length === 0) {
        Text(this.model.text('暂无可显示的教学云当前课程。'))
          .fontSize(13)
          .fontColor(AppTheme.secondaryText())
      } else {
        ForEach(this.cloudCourseGroups(), (course: UCloudCourseGroup, index: number) => {
          this.cloudCourseRow(course)
          if (index < this.cloudCourseGroups().length - 1) {
            Divider().strokeWidth(0.5).color(AppTheme.border()).margin({ left: 52 })
          }
        }, (course: UCloudCourseGroup) => course.id)
      }
      Button(this.model.text('打开教学云平台'))
        .type(ButtonType.Normal)
        .height(ControlMetrics.height)
        .enabled(!this.model.isSampleMode())
        .backgroundColor(AppTheme.surfaceVariant())
        .fontColor(AppTheme.primary())
        .onClick(() => {
          try { AppContext.get().openLink(CalendarDailyInfoSources.assignments); } catch (e) {}
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(10)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  courseBookIcon() {
    Column() {
      SymbolGlyph($r('sys.symbol.book_open_fill'))
        .fontSize(23)
        .fontColor([AppTheme.primary()])
    }
    .width(40)
    .height(40)
    .borderRadius(10)
    .backgroundColor(AppTheme.selection())
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  courseChip(symbol: Resource, label: string) {
    Row({ space: 4 }) {
      SymbolGlyph(symbol)
        .fontSize(12)
        .fontColor([AppTheme.primary()])
      Text(label)
        .fontSize(12)
        .fontColor(AppTheme.primary())
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(12)
    .backgroundColor(AppTheme.selection())
    .constraintSize({ maxWidth: 210 })
  }

  @Builder
  cloudCourseRow(course: UCloudCourseGroup) {
    Column({ space: 8 }) {
    Row({ space: 12 }) {
      Row({ space: 12 }) {
      this.courseBookIcon()
      Column({ space: 5 }) {
        Text(course.name ?? course.id)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap,
          space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(5) } }) {
          if (course.teacherNames.length > 0) {
            ForEach(course.teacherNames, (teacher: string) => {
              this.courseChip($r('sys.symbol.book_open_fill'), teacher)
            }, (teacher: string) => teacher)
          } else {
            this.courseChip($r('sys.symbol.book_open_fill'), this.localized('教学云', 'Teaching Cloud'))
          }
          if (this.model.assignmentCatalogFetchedAt.length > 0 &&
            this.cloudSubmissionCounts(course).pending > 0) {
            this.courseChip($r('sys.symbol.clock'),
              this.localized('待交 ', 'Pending ') + this.cloudSubmissionCounts(course).pending.toString())
          }
          if (this.model.assignmentCatalogFetchedAt.length > 0 &&
            this.cloudSubmissionCounts(course).submitted > 0) {
            this.courseChip($r('sys.symbol.checkmark_circle'),
              this.localized('已交 ', 'Submitted ') + this.cloudSubmissionCounts(course).submitted.toString())
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .id('courses.cloud.disclosure.' + course.id)
      .accessibilityText(course.name ?? course.id)
      .accessibilityStateDescription(this.model.text(this.session.isExpanded('ucloud', course.id) ? '已展开' : '已折叠'))
      .onClick(() => this.toggleCourseInline('ucloud', course.id))
      this.courseDisclosureButton('ucloud', course.id)
      Button() { SymbolGlyph($r('sys.symbol.info_circle')).fontSize(18).fontColor([AppTheme.secondaryText()]) }
        .type(ButtonType.Normal).width(ControlMetrics.height).height(ControlMetrics.height).padding(4)
        .backgroundColor(Color.Transparent).accessibilityText(this.model.text('课程详情'))
        .id('courses.cloud.info.' + course.id)
        .onClick(() => this.openCourse('ucloud', course.id))
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .id('courses.cloud.row.' + course.id)
      DisclosureClip({ expanded: this.session.isExpanded('ucloud', course.id) }) {
        Column({ space: 8 }) { this.inlineCloudAssignments(course) }
          .width('100%').padding({ left: 52, bottom: 8 }).alignItems(HorizontalAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private currentQMPlusCourses(): QMPlusCourse[] {
    return CourseQMPlusScope.currentCourses(this.qmPlusSession.snapshot);
  }

  private otherQMPlusCourses(): QMPlusCourse[] {
    return CourseQMPlusScope.otherCourses(this.qmPlusSession.snapshot);
  }

  private courseActivityCount(courseID: string): number {
    return CourseQMPlusScope.currentActivities(this.qmPlusSession.snapshot)
      .filter((item: QMPlusActivity): boolean =>
      item.courseID === courseID).length;
  }

  private visibleQMActivitiesFor(courseID: string): QMPlusActivity[] {
    return CourseQMPlusScope.currentActivities(this.qmPlusSession.snapshot)
      .filter((item: QMPlusActivity): boolean => item.courseID === courseID);
  }

  private qmTime(utc: string): string {
    return CourseQMPlusScope.shanghaiTime(utc) + this.localized('（北京时间）', ' (Beijing time)');
  }

  @Builder
  qmPlusSection() {
    Column({ space: 9 }) {
      Row({ space: 8 }) {
        Text(this.model.text('QMplus 当前课程'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.text())
          .layoutWeight(1)
        Button(this.model.text(this.qmPlusSession.manualContinuationRequired ? '手动继续' :
          this.qmPlusSession.snapshot === null ? '连接QMplus' : '重新同步'))
          .type(ButtonType.Normal)
          .height(ControlMetrics.height)
          .backgroundColor(AppTheme.surfaceVariant())
          .fontColor(AppTheme.primary())
          .id('courses.qmplus.connect')
          .onClick(() => this.qmPlusSession.openLogin())
      }
      .width('100%')
      Text(this.model.text('通过官方网页完成 SSO/MFA；仅同步当前课程已发布作业与测验。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
      Text(this.model.text('第三方来源：QMplus 官方网页；时间以课程页面为准。'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
      Text(this.localized('以下换算为北京时间；原网页伦敦时间说明保持原文。',
        'Times below are converted to Beijing time; original London wording is unchanged.'))
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
      if (this.qmPlusSession.error.length > 0) {
        Text(this.model.text(this.qmPlusSession.error) + (this.qmPlusSession.errorCode.length > 0 &&
          this.qmPlusSession.errorCode !== 'QM_LOGIN_REQUIRED' ? ' (' + this.qmPlusSession.errorCode + ')' : ''))
          .fontSize(12)
          .fontColor(AppTheme.danger())
      }
      if (this.qmPlusSession.snapshot !== null) {
        Text(this.model.text('更新时间：') + (this.qmPlusSession.snapshot?.fetchedAt ?? ''))
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
        if (this.qmPlusSession.snapshot?.partial) {
          Text(this.model.text('部分课程或活动无法读取，以下为已核实的结果。'))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
        }
        if (this.qmPlusSession.showingStalePartial) {
          Text(this.model.text('本次仅部分同步成功，继续显示上次完整资料；时间仍以上次同步为准，仅供对照。'))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
        }
        if (this.currentQMPlusCourses().length === 0) {
          Text(this.model.text('暂无已确认的当前学期 QMplus 课程。'))
            .fontSize(13)
            .fontColor(AppTheme.secondaryText())
        }
        ForEach(this.currentQMPlusCourses(), (course: QMPlusCourse, index: number) => {
          this.qmPlusCourseRow(course)
          if (index < this.currentQMPlusCourses().length - 1) {
            Divider().strokeWidth(0.5).color(AppTheme.border()).margin({ left: 52 })
          }
        }, (course: QMPlusCourse) => course.id)
        if (this.otherQMPlusCourses().length > 0) {
          Text(this.model.text('其它或学期未确认的课程：'))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
          ForEach(this.otherQMPlusCourses(), (course: QMPlusCourse, index: number) => {
            this.qmPlusCourseRow(course)
            if (index < this.otherQMPlusCourses().length - 1) {
              Divider().strokeWidth(0.5).color(AppTheme.border()).margin({ left: 52 })
            }
          }, (course: QMPlusCourse) => course.id)
        }
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(10)
    .backgroundColor(AppTheme.surface())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  qmPlusCourseRow(course: QMPlusCourse) {
    Column({ space: 8 }) {
    Row({ space: 12 }) {
      Row({ space: 12 }) {
      this.courseBookIcon()
      Column({ space: 5 }) {
        Text(course.name.length > 0 ? course.name : course.id)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.text())
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap,
          space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(5) } }) {
          this.courseChip($r('sys.symbol.book_open_fill'),
            course.shortName.length > 0 ? course.shortName : 'QMplus')
          this.courseChip($r('sys.symbol.clock'), course.currentTermStatus === 'current' ?
            this.localized('当前学期', 'Current term') : course.currentTermStatus === 'other' ?
              this.localized('其它学期', 'Other term') : this.localized('学期未确认', 'Term unconfirmed'))
          if (course.currentTermStatus === 'current' && this.courseActivityCount(course.id) > 0) {
            this.courseChip($r('sys.symbol.checkmark_circle'),
              this.localized('已获取 ', 'Fetched ') + this.courseActivityCount(course.id).toString())
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .id('courses.qmplus.disclosure.' + course.id)
      .accessibilityText(course.name.length > 0 ? course.name : course.id)
      .accessibilityStateDescription(this.model.text(this.session.isExpanded('qmplus', course.id) ? '已展开' : '已折叠'))
      .onClick(() => this.toggleCourseInline('qmplus', course.id))
      this.courseDisclosureButton('qmplus', course.id)
      Button() { SymbolGlyph($r('sys.symbol.info_circle')).fontSize(18).fontColor([AppTheme.secondaryText()]) }
        .type(ButtonType.Normal).width(ControlMetrics.height).height(ControlMetrics.height).padding(4)
        .backgroundColor(Color.Transparent).accessibilityText(this.model.text('课程详情'))
        .id('courses.qmplus.info.' + course.id)
        .onClick(() => this.openCourse('qmplus', course.id))
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .id('courses.qmplus.row.' + course.id)
      DisclosureClip({ expanded: this.session.isExpanded('qmplus', course.id) }) {
        Column({ space: 8 }) { this.inlineQMActivities(course) }
          .width('100%').padding({ left: 52, bottom: 8 }).alignItems(HorizontalAlign.Start)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  courseDisclosureButton(source: string, id: string) {
    Button() {
      SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(18).fontColor([AppTheme.secondaryText()])
        .rotate({ angle: this.session.isExpanded(source, id) ? 180 : 0 })
    }
      .type(ButtonType.Normal).width(ControlMetrics.height).height(ControlMetrics.height).padding(4)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.model.text(this.session.isExpanded(source, id) ? '已展开' : '已折叠'))
      .onClick(() => this.toggleCourseInline(source, id))
  }

  @Builder
  qmPlusCourseCard(course: QMPlusCourse) {
    Column({ space: 7 }) {
      Text(course.name.length > 0 ? course.name : course.id)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.text())
      if (course.shortName.length > 0) {
        Text(course.shortName)
          .fontSize(12)
          .fontColor(AppTheme.secondaryText())
      }
      Text(this.model.text('已核实活动数量：') + this.courseActivityCount(course.id).toString())
        .fontSize(12)
        .fontColor(AppTheme.secondaryText())
      ForEach(this.visibleQMActivitiesFor(course.id).slice(0, this.session.visibleQMActivities), (item: QMPlusActivity) => {
        Column({ space: 3 }) {
          Text(item.title.length > 0 ? item.title : item.id)
            .fontSize(14)
            .fontColor(AppTheme.text())
          Text(this.model.text(item.kind === 'quiz' ? '测验' : '作业'))
            .fontSize(12)
            .fontColor(AppTheme.secondaryText())
          if (item.kind === 'assignment') {
            if (item.dueAt !== null) {
              Text(this.model.text('截止时间：') + this.qmTime(item.dueAt))
                .textDirection(TextDirection.LTR)
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
            if (item.cutoffAt !== null) {
              Text(this.model.text('最终截止：') + this.qmTime(item.cutoffAt))
                .textDirection(TextDirection.LTR)
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
            if (item.dueAt === null && item.cutoffAt === null) {
              Text(this.model.text('截止时间未公布'))
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
          } else {
            if (item.opensAt !== null) {
              Text(this.model.text('开放时间：') + this.qmTime(item.opensAt))
                .textDirection(TextDirection.LTR)
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
            if (item.closesAt !== null) {
              Text(this.model.text('关闭时间：') + this.qmTime(item.closesAt))
                .textDirection(TextDirection.LTR)
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
            if (item.timeLimitSeconds !== null) {
              Text(this.model.text('限时：') + item.timeLimitSeconds.toString() + this.model.text(' 秒'))
                .fontSize(12)
                .fontColor(AppTheme.secondaryText())
            }
          }
          if (item.rawTimeText.length > 0) {
            Text(item.rawTimeText)
              .textDirection(TextDirection.AUTO)
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
          }
          if (item.status.length > 0 && item.status !== 'unknown') {
            Text(this.model.text('状态：') + item.status)
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
          }
          if (item.detailStatus !== 'available') {
            Text(this.model.text(item.detailStatus === 'restricted' ?
              '详情受限，不能确认全部时间。' : '详情暂不可用，显示已核实时间。'))
              .fontSize(12)
              .fontColor(AppTheme.secondaryText())
          }
          Button(this.model.text('打开 QMplus 官方活动页'))
            .type(ButtonType.Normal)
            .height(ControlMetrics.height)
            .backgroundColor(AppTheme.surfaceVariant())
            .fontColor(AppTheme.primary())
            .onClick(() => this.qmPlusSession.openLogin(item.url))
        }
        .width('100%')
        .padding(9)
        .borderRadius(7)
        .backgroundColor(AppTheme.background())
        .alignItems(HorizontalAlign.Start)
      }, (item: QMPlusActivity) => item.id)
    }
    .width('100%')
    .padding(11)
    .borderRadius(7)
    .backgroundColor(AppTheme.surfaceVariant())
    .alignItems(HorizontalAlign.Start)
  }
}
