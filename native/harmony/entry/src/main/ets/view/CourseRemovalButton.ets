import { Course } from '../common/Models';
import { DateParts, StrictDates } from '../common/StrictDates';
import { AppTheme } from '../common/AppTheme';
import { AppModel } from '../model/AppModel';

@ComponentV2
export struct CourseRemovalButton {
  @Consumer('appModel') model: AppModel = new AppModel();
  @Require @Param course: Course;
  @Require @Param date: DateParts;

  private confirmRemoval(wholeCourse: boolean): void {
    const course: Course = this.course;
    const date: DateParts = this.date;
    const termID: string = this.model.schedule?.termID ?? '';
    const account: string = this.model.account;
    this.getUIContext().showAlertDialog({
      title: this.model.text(wholeCourse ? '删除本学期整门课程？' : '仅删除本次课程？'),
      message: this.course.name + '\n' + (wholeCourse ? '' : StrictDates.formatDateParts(this.date) +
        ' · ' + this.course.timeRange + '\n') +
        this.model.text('仅修改本机个人课表，可在设置中恢复。不会修改教务数据、作业 DDL 或已导出的系统日历。'),
      primaryButton: { value: this.model.text('取消'), action: (): void => {} },
      secondaryButton: {
        value: this.model.text('确认删除'), fontColor: AppTheme.danger(),
        action: (): void => {
          this.model.removeCourse(course, date, wholeCourse, termID, account).then((saved: boolean): void => {
            this.getUIContext().getPromptAction().showToast({ message: this.model.text(saved ?
              '课程已从个人课表删除，可在设置中恢复。' : '课程修改未保存，请重试。') });
          }).catch((): void => {});
        }
      }
    });
  }

  build() {
    Button(this.model.text('删除'))
      .type(ButtonType.Normal)
      .fontSize(12)
      .fontColor(AppTheme.danger())
      .backgroundColor(Color.Transparent)
      .padding({ left: 8, right: 8 })
      .height(30)
      .enabled(!this.model.isSampleMode() && !this.model.isUpdatingCourseRemovals)
      .onClick(() => {
        this.getUIContext().showAlertDialog({
          title: this.course.name,
          message: this.model.text('选择删除范围'),
          buttons: [
            { value: this.model.text('仅删除本次'), action: (): void => this.confirmRemoval(false) },
            { value: this.model.text('删除本学期整门课程'), action: (): void => this.confirmRemoval(true) },
            { value: this.model.text('取消'), action: (): void => {} }
          ]
        });
      })
  }
}
