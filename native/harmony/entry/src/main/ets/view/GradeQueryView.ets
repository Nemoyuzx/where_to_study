import { AppModel } from '../model/AppModel';
import { AppTheme } from '../common/AppTheme';
import { ControlMetrics } from '../common/ControlMetrics';
import { AcademicTerm, GradeItem } from '../common/AcademicModels';

@ComponentV2
export struct GradeQueryView {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Event onOpenSettings: () => void = () => {};

  private termOptions(): SelectOption[] {
    const result: SelectOption[] = [{ value: this.model.text('全部学期') }];
    for (const term of this.model.gradeTerms) { result.push({ value: term.name }); }
    return result;
  }

  private termName(): string {
    if (this.model.gradeTermID.length === 0) { return this.model.text('全部学期'); }
    return this.model.gradeTerms.find((term: AcademicTerm) => term.id === this.model.gradeTermID)?.name ??
      this.model.gradeTermID;
  }

  private recordTypeName(): string {
    return this.model.text(this.model.gradeRecordType === '1' ? '最好成绩' :
      this.model.gradeRecordType === '0' ? '首次成绩' : '全部记录');
  }

  build() {
    Column({ space: 14 }) {
      Text(this.model.text('成绩查询'))
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.text())
      Text(this.model.text('成绩仅在本次运行中保留，直接向学校教务系统查询。'))
        .fontSize(13).fontColor(AppTheme.secondaryText())
      if (this.model.account.trim().length === 0 || !this.model.canPreserveSavedPassword()) {
        Text(this.model.text('请先在账户设置中保存教务账号和密码。'))
          .fontSize(15).fontColor(AppTheme.secondaryText())
        Button(this.model.text('前往账户设置'))
          .height(ControlMetrics.height)
          .id('query.grades.settings').onClick(() => this.onOpenSettings())
      } else {
        Column({ space: 10 }) {
          Text(this.model.text('学期')).fontSize(13).fontColor(AppTheme.secondaryText())
          Select(this.termOptions())
            .height(ControlMetrics.height)
            .value(this.termName()).width('100%').font({ size: 15 })
            .enabled(!this.model.gradeLoading && this.model.gradeTerms.length > 0)
            .id('query.grades.term')
            .onSelect((index: number) => {
              this.model.selectGradeTerm(index === 0 ? '' : this.model.gradeTerms[index - 1].id);
            })
          Select([{ value: this.model.text('最好成绩') }, { value: this.model.text('首次成绩') },
            { value: this.model.text('全部记录') }])
            .height(ControlMetrics.height)
            .value(this.recordTypeName()).width('100%').font({ size: 15 })
            .enabled(!this.model.gradeLoading).id('query.grades.type')
            .onSelect((index: number) => this.model.selectGradeRecordType(['1', '0', ''][index]))
          Button(this.model.text(this.model.gradeLoading ? '正在查询成绩…' : '刷新成绩'))
            .height(ControlMetrics.height)
            .id('query.grades.refresh').enabled(!this.model.gradeLoading)
            .onClick(() => this.model.loadGrades(true))
        }.width('100%').alignItems(HorizontalAlign.Start)
        if (this.model.gradeError.length > 0) {
          Text(this.model.text(this.model.gradeError))
            .fontSize(14).fontColor(AppTheme.danger()).id('query.grades.error')
          if (this.model.gradeSnapshot !== null) {
            Text(this.model.text('正在显示此前查询结果。')).fontSize(13).fontColor(AppTheme.secondaryText())
          }
        }
        if (this.model.gradeLoading && this.model.gradeSnapshot === null) {
          LoadingProgress().width(30).height(30)
        } else if (this.model.gradeSnapshot !== null) {
          if (this.model.gradeSnapshot?.averageGradePoint !== null) {
            Text(this.model.text('平均学分绩点：') + (this.model.gradeSnapshot?.averageGradePoint ?? ''))
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary())
          }
          if ((this.model.gradeSnapshot?.items.length ?? 0) === 0) {
            Text(this.model.text('所选学期暂无已公布成绩。'))
              .fontSize(15).fontColor(AppTheme.secondaryText()).id('query.grades.empty')
            if (this.model.gradeTermID.length > 0) {
              Button(this.model.text('查看全部学期'))
                .height(ControlMetrics.height)
                .onClick(() => this.model.selectGradeTerm(''))
            }
          } else {
            ForEach(this.model.gradeSnapshot?.items ?? [], (item: GradeItem) => {
              this.gradeCard(item)
            }, (item: GradeItem) => item.id)
          }
        } else if (this.model.gradeError.length === 0) {
          Text(this.model.text('点击刷新以查询，切换页面保留上次结果。'))
            .fontSize(14).fontColor(AppTheme.secondaryText())
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  gradeCard(item: GradeItem) {
    Column({ space: 8 }) {
      Text(item.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppTheme.text())
      if (item.semesterName.length > 0) {
        Text(item.semesterName).fontSize(13).fontColor(AppTheme.secondaryText())
      }
      Text(this.model.text('成绩：') + (item.score ?? this.model.text('未公布')))
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.primary())
      Text(this.model.text('学分：') + (item.credits ?? this.model.text('未公布')))
        .fontSize(14).fontColor(AppTheme.secondaryText())
      if (item.courseCode.length > 0) {
        Text(this.model.text('课程代码：') + item.courseCode).fontSize(13).fontColor(AppTheme.secondaryText())
      }
      if (item.gradeStatus.length > 0) {
        Text(this.model.text('成绩标识：') + item.gradeStatus).fontSize(13).fontColor(AppTheme.secondaryText())
      }
      if ([item.courseAttribute, item.courseNature, item.examNature].join('').length > 0) {
        Text([item.courseAttribute, item.courseNature, item.examNature].filter(
          (value: string) => value.length > 0).join(' · ')).fontSize(13).fontColor(AppTheme.secondaryText())
      }
    }.width('100%').padding(16).borderRadius(12).backgroundColor(AppTheme.surface())
      .alignItems(HorizontalAlign.Start)
  }
}
