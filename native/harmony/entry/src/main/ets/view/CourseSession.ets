import { CoursePageTab } from '../common/CourseLogic';

// RootView 持有一级课程页面的栏目与滚动位置；不复制教务或 QMplus 凭据。
@ObservedV2
export class CourseSession {
  @Trace selectedTabRawValue: string = CoursePageTab.current;
  @Trace showsOtherQMplusTerms: boolean = false;
  @Trace visibleQMActivities: number = 40;
  @Trace visibleCloudAssignments: number = 40;
  @Trace selectedCourseSource: string = '';
  @Trace selectedCourseID: string = '';
  @Trace expandedCourseKeys: string[] = [];
  skipNextAutomaticCourseLoad: boolean = false;

  isExpanded(source: string, id: string): boolean { return this.expandedCourseKeys.includes(source + '.' + id); }
  toggleExpanded(source: string, id: string): void {
    const key: string = source + '.' + id;
    this.expandedCourseKeys = this.expandedCourseKeys.includes(key) ?
      this.expandedCourseKeys.filter((value: string): boolean => value !== key) : [...this.expandedCourseKeys, key];
  }
  detailScrollOffset: number = 0;
  readonly scrollOffsets: Map<string, number> = new Map<string, number>();

  openCourse(source: string, id: string): void {
    if ((source !== 'ucloud' && source !== 'qmplus') || id.length === 0) { return; }
    this.selectedCourseID = id;
    this.selectedCourseSource = source;
    this.detailScrollOffset = 0;
    this.visibleQMActivities = 40;
    this.visibleCloudAssignments = 40;
  }

  closeCourse(): void {
    this.selectedCourseSource = '';
    this.selectedCourseID = '';
    this.detailScrollOffset = 0;
  }
}
