import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { AcademicTerm, ExamArrangement } from '../common/AcademicModels';
import { AssignmentDeadlineItem, CalendarDailyInfoSources } from '../net/CalendarDailyInfoClient';
import { AppContext } from '../store/AppContext';

@ComponentV2
export struct AssignmentQueryView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Event onOpenSettings: () => void = () => {};
  @Local searchText: string = '';
  @Local visibleCount: number = 50;

  private filtered(): AssignmentDeadlineItem[] {
    const search: string = this.searchText.trim().toLowerCase();
    return this.model.assignmentCatalog.filter((item: AssignmentDeadlineItem): boolean =>
      [item.title, item.courseName ?? '', item.status ?? '', item.deadline].join(' ').toLowerCase().includes(search));
  }

  build() {
    Column({ space: 14 }) {
      Text(this.model.text('课程作业 DDL')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.text())
      Text(this.model.text('直接查询教学云课程作业，按截止时间排序。')).fontSize(13).fontColor(AppTheme.secondaryText())
      if (this.model.account.trim().length === 0 || !this.model.canPreserveSavedPassword()) {
        Text(this.model.text('请先在账户设置中保存教务账号和密码。')).fontSize(15).fontColor(AppTheme.secondaryText())
        Button(this.model.text('前往账户设置')).height(ControlMetrics.height)
          .id('query.assignments.settings').onClick(() => this.onOpenSettings())
      } else {
        Row({ space: 8 }) {
          Button(this.model.text(this.model.assignmentCatalogLoading ? '正在同步云课堂作业…' : '刷新作业'))
            .height(ControlMetrics.height).enabled(!this.model.assignmentCatalogLoading)
            .id('query.assignments.refresh').onClick(() => this.model.loadAssignmentCatalog(true))
          Button(this.model.text('打开教学云')).height(ControlMetrics.height)
            .onClick(() => {
              try { AppContext.get().openLink(CalendarDailyInfoSources.assignments); } catch (e) {}
            })
        }.width('100%')
        TextInput({ text: this.searchText, placeholder: this.model.text('搜索课程或作业') })
          .height(ControlMetrics.height).width('100%').id('query.assignments.search')
          .onChange((value: string) => { this.searchText = value; this.visibleCount = 50; })
        if (this.model.assignmentCatalogError.length > 0) {
          Text(this.model.text(this.model.assignmentCatalogError)).fontSize(14).fontColor(AppTheme.danger())
          if (this.model.assignmentCatalogFetchedAt.length > 0) {
            Text(this.model.text('正在显示此前查询结果。')).fontSize(13).fontColor(AppTheme.secondaryText())
          }
        }
        if (this.model.assignmentCatalogLoading && this.model.assignmentCatalogFetchedAt.length === 0) {
          LoadingProgress().width(30).height(30)
        } else if (this.model.assignmentCatalogFetchedAt.length > 0) {
          Text(this.model.text('更新时间：') + this.model.assignmentCatalogFetchedAt)
            .fontSize(12).fontColor(AppTheme.secondaryText())
          if (this.filtered().length === 0) {
            Text(this.model.text('暂无匹配的课程作业 DDL。')).fontSize(15).fontColor(AppTheme.secondaryText())
              .id('query.assignments.empty')
          }
          ForEach(this.filtered().slice(0, this.visibleCount), (item: AssignmentDeadlineItem) => {
            Column({ space: 8 }) {
              Text(item.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppTheme.text())
              if (item.courseName !== null) {
                Text(item.courseName ?? '').fontSize(14).fontColor(AppTheme.secondaryText())
              }
              Text(this.model.text('截止时间：') + item.deadline).fontSize(15).fontColor(AppTheme.primary())
              if (item.status !== null) {
                Text(this.model.text('状态：') + this.model.text(item.status ?? '')).fontSize(13).fontColor(AppTheme.secondaryText())
              }
            }.width('100%').padding(16).borderRadius(12).backgroundColor(AppTheme.surface())
              .alignItems(HorizontalAlign.Start)
          }, (item: AssignmentDeadlineItem) => item.id + '|' + item.deadline)
          if (this.filtered().length > this.visibleCount) {
            Button(this.model.text('加载更多')).height(ControlMetrics.height).onClick(() => { this.visibleCount += 50; })
          }
        } else if (this.model.assignmentCatalogError.length === 0) {
          Text(this.model.text('点击刷新以查询，切换页面保留上次结果。')).fontSize(14).fontColor(AppTheme.secondaryText())
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
export struct ExamQueryView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Event onOpenSettings: () => void = () => {};

  private termOptions(): SelectOption[] {
    return this.model.examTerms.map((term: AcademicTerm): SelectOption => ({ value: term.name }));
  }

  build() {
    Column({ space: 14 }) {
      Text(this.model.text('考试查询')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.text())
      Text(this.model.text('按学期查询教务考试安排。')).fontSize(13).fontColor(AppTheme.secondaryText())
      if (this.model.account.trim().length === 0 || !this.model.canPreserveSavedPassword()) {
        Text(this.model.text('请先在账户设置中保存教务账号和密码。')).fontSize(15).fontColor(AppTheme.secondaryText())
        Button(this.model.text('前往账户设置')).height(ControlMetrics.height)
          .id('query.exams.settings').onClick(() => this.onOpenSettings())
      } else {
        if (this.model.examTerms.length > 0) {
          Select(this.termOptions()).height(ControlMetrics.height).width('100%')
            .value(this.model.examTerms.find((term: AcademicTerm) => term.id === this.model.examQueryTermID)?.name ?? this.model.examQueryTermID)
            .enabled(!this.model.examQueryLoading).id('query.exams.term')
            .onSelect((index: number) => this.model.selectExamQueryTerm(this.model.examTerms[index].id))
        }
        Button(this.model.text(this.model.examQueryLoading ? '正在查询考试…' : '刷新考试'))
          .height(ControlMetrics.height).enabled(!this.model.examQueryLoading).id('query.exams.refresh')
          .onClick(() => this.model.loadExamQuery(true))
        if (this.model.examQueryError.length > 0) {
          Text(this.model.text(this.model.examQueryError)).fontSize(14).fontColor(AppTheme.danger())
          if (this.model.examQuerySnapshot !== null) {
            Text(this.model.text('正在显示此前查询结果。')).fontSize(13).fontColor(AppTheme.secondaryText())
          }
        }
        if (this.model.examQueryLoading && this.model.examQuerySnapshot === null) {
          LoadingProgress().width(30).height(30)
        } else if (this.model.examQuerySnapshot !== null) {
          Text(this.model.text('更新时间：') + (this.model.examQuerySnapshot?.fetchedAt ?? ''))
            .fontSize(12).fontColor(AppTheme.secondaryText())
          if ((this.model.examQuerySnapshot?.items.length ?? 0) === 0) {
            Text(this.model.text('本学期暂无考试安排。')).fontSize(15).fontColor(AppTheme.secondaryText()).id('query.exams.empty')
          }
          ForEach(this.model.examQuerySnapshot?.items ?? [], (item: ExamArrangement) => {
            Column({ space: 8 }) {
              Text(item.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppTheme.text())
              Text(item.timeText.length > 0 ? item.timeText : this.model.text('时间待定'))
                .fontSize(15).fontColor(AppTheme.primary())
              if (item.room.length > 0) { Text(this.model.text('考场：') + item.room).fontSize(14).fontColor(AppTheme.secondaryText()) }
              if (item.seat.length > 0) { Text(this.model.text('座位：') + item.seat).fontSize(14).fontColor(AppTheme.secondaryText()) }
            }.width('100%').padding(16).borderRadius(12).backgroundColor(AppTheme.surface())
              .alignItems(HorizontalAlign.Start)
          }, (item: ExamArrangement) => item.id)
        } else if (this.model.examQueryError.length === 0) {
          Text(this.model.text('点击刷新以查询，切换页面保留上次结果。')).fontSize(14).fontColor(AppTheme.secondaryText())
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
