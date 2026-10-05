import { QMPlusActivity, QMPlusCourse, QMPlusSnapshot, QMPlusCourseworkPolicy } from '../net/QMPlusSnapshot';
import { UCloudCourse } from '../net/UCloudAssignmentClient';
import { AssignmentDeadlineItem } from '../net/CalendarDailyInfoClient';

export enum CoursePageTab {
  current = 'current',
  grades = 'grades',
  exams = 'exams',
  assignments = 'assignments'
}

export class CoursePageContract {
  static readonly tabs: CoursePageTab[] = [CoursePageTab.current, CoursePageTab.grades,
    CoursePageTab.exams, CoursePageTab.assignments];

  static title(tab: CoursePageTab): string {
    if (tab === CoursePageTab.current) { return '当前课程'; }
    if (tab === CoursePageTab.grades) { return '成绩查询'; }
    if (tab === CoursePageTab.exams) { return '考试查询'; }
    return '作业 DDL';
  }

  static compactTitle(tab: CoursePageTab): string {
    if (tab === CoursePageTab.current) { return '课程'; }
    if (tab === CoursePageTab.grades) { return '成绩'; }
    if (tab === CoursePageTab.exams) { return '考试'; }
    return '作业';
  }

  static symbol(tab: CoursePageTab): Resource {
    if (tab === CoursePageTab.current) { return $r('sys.symbol.graduationcap'); }
    if (tab === CoursePageTab.grades) { return $r('sys.symbol.graduationcap'); }
    if (tab === CoursePageTab.exams) { return $r('sys.symbol.doc_text'); }
    return $r('sys.symbol.list_bullet');
  }

  static accessibilityID(tab: CoursePageTab): string {
    return 'courses.tab.' + tab;
  }

  static iconOnlyTabs(pickerWidth: number, maximumLabelWidth: number, includesIcons: boolean): boolean {
    if (!Number.isFinite(pickerWidth) || pickerWidth <= 0 ||
      !Number.isFinite(maximumLabelWidth) || maximumLabelWidth <= 0) {
      return true;
    }
    const segmentWidth: number = Math.max(0, pickerWidth - 6) / CoursePageContract.tabs.length;
    return Math.ceil(maximumLabelWidth) + 12 + (includesIcons ? 24 : 0) > segmentWidth;
  }
}

// 对旧的本地快照也应用同一展示范围；不以“当前”状态替代 EBU 名称过滤。
export class CourseQMPlusScope {
  static shanghaiTime(utc: string): string {
    const epoch: number = new Date(utc).getTime();
    if (!Number.isFinite(epoch)) { return utc; }
    // QMplus snapshot times are validated UTC; Shanghai has a fixed UTC+08 offset.
    // Use UTC getters after the offset, never the device's local timezone.
    const local: Date = new Date(epoch + 8 * 60 * 60 * 1000);
    const pad: (value: number) => string = (value: number): string => value < 10 ? '0' + value.toString() :
      value.toString();
    return local.getUTCFullYear().toString() + '-' + pad(local.getUTCMonth() + 1) + '-' +
      pad(local.getUTCDate()) + ' ' + pad(local.getUTCHours()) + ':' + pad(local.getUTCMinutes());
  }

  static isEBUName(name: string): boolean {
    return /^EBU/i.test(name.trim());
  }

  static courses(snapshot: QMPlusSnapshot | null): QMPlusCourse[] {
    return (snapshot?.courses ?? []).filter((course: QMPlusCourse): boolean =>
      CourseQMPlusScope.isEBUName(course.name));
  }

  static currentCourses(snapshot: QMPlusSnapshot | null): QMPlusCourse[] {
    return CourseQMPlusScope.courses(snapshot).filter((course: QMPlusCourse): boolean =>
      course.currentTermStatus === 'current');
  }

  static otherCourses(snapshot: QMPlusSnapshot | null): QMPlusCourse[] {
    return CourseQMPlusScope.courses(snapshot).filter((course: QMPlusCourse): boolean =>
      course.currentTermStatus !== 'current');
  }

  static currentActivities(snapshot: QMPlusSnapshot | null): QMPlusActivity[] {
    if (snapshot === null) { return []; }
    const currentIDs: Set<string> = new Set<string>(CourseQMPlusScope.currentCourses(snapshot)
      .map((course: QMPlusCourse): string => course.id));
    return QMPlusCourseworkPolicy.activities(snapshot.activities).filter((item: QMPlusActivity): boolean =>
      currentIDs.has(item.courseID) && (item.kind === 'assignment' || item.kind === 'quiz'));
  }
}

export class CourseSubmissionCounts {
  readonly pending: number;
  readonly submitted: number;

  constructor(pending: number, submitted: number) {
    this.pending = pending;
    this.submitted = submitted;
  }
}

export class UCloudCourseGroup {
  readonly id: string;
  readonly name: string | null;
  readonly teacherNames: string[];
  readonly courseIDs: string[];

  constructor(members: UCloudCourse[]) {
    this.courseIDs = Array.from(new Set<string>(members.map((course: UCloudCourse): string => course.id))).sort();
    this.id = this.courseIDs[0];
    const name: string = members[0].name?.trim() ?? '';
    this.name = name.length > 0 ? name : null;
    const teachers: Set<string> = new Set<string>();
    members.forEach((course: UCloudCourse): void => course.teacherNames.forEach((teacher: string): void => {
      const teacherName: string = teacher.trim();
      if (teacherName.length > 0) { teachers.add(teacherName); }
    }));
    this.teacherNames = Array.from(teachers);
  }
}

export class CourseCloudScope {
  // The caller supplies only the current-term directory; source DTOs stay unchanged.
  static groups(courses: UCloudCourse[]): UCloudCourseGroup[] {
    const groups: Map<string, UCloudCourse[]> = new Map<string, UCloudCourse[]>();
    courses.forEach((course: UCloudCourse): void => {
      const name: string = course.name?.trim() ?? '';
      const key: string = name.length > 0 ? 'name:' + name : 'id:' + course.id;
      const members: UCloudCourse[] = groups.get(key) ?? [];
      members.push(course);
      groups.set(key, members);
    });
    return Array.from(groups.values()).map((members: UCloudCourse[]): UCloudCourseGroup => new UCloudCourseGroup(members));
  }

  static groupAssignmentsFor(course: UCloudCourseGroup, directory: UCloudCourse[],
    catalog: AssignmentDeadlineItem[], catalogLoaded: boolean): AssignmentDeadlineItem[] {
    if (!catalogLoaded) { return []; }
    const name: string = course.name ?? '';
    const uniqueLegacyName: boolean = name.length > 0 && directory.filter((candidate: UCloudCourse): boolean =>
      candidate.name?.trim() === name).length === 1;
    return catalog.filter((item: AssignmentDeadlineItem): boolean =>
      (item.courseID !== null && course.courseIDs.includes(item.courseID)) ||
      (item.courseID === null && uniqueLegacyName && item.courseName?.trim() === name));
  }

  static assignmentKey(item: AssignmentDeadlineItem): string {
    return (item.courseID === null ? 'missing' : 'id:' + item.courseID.length.toString() + ':' + item.courseID) + ':' + item.id;
  }

  static assignmentsFor(course: UCloudCourse, directory: UCloudCourse[],
    catalog: AssignmentDeadlineItem[], catalogLoaded: boolean): AssignmentDeadlineItem[] {
    if (!catalogLoaded) { return []; }
    const name: string = course.name?.trim() ?? '';
    const uniqueName: boolean = name.length > 0 && directory.filter((candidate: UCloudCourse): boolean =>
      candidate.name?.trim() === name).length === 1;
    return catalog.filter((item: AssignmentDeadlineItem): boolean =>
      item.courseID === course.id || (item.courseID === null && uniqueName && item.courseName?.trim() === name));
  }

  static submissionCounts(items: AssignmentDeadlineItem[]): CourseSubmissionCounts {
    let pending: number = 0;
    let submitted: number = 0;
    const evidence: Map<string, Set<string>> = new Map<string, Set<string>>();
    for (const item of items) {
      const status: string = item.status?.trim().toLowerCase() ?? '';
      const key: string = CourseCloudScope.assignmentKey(item);
      const states: Set<string> = evidence.get(key) ?? new Set<string>();
      if (status === '未提交' || status === 'not submitted' || status === 'nothing submitted' ||
        status === 'no submissions have been made yet') { states.add('pending'); }
      else if (status === '已提交' || status === 'submitted' || status === 'submitted for grading') {
        states.add('submitted');
      }
      evidence.set(key, states);
    }
    evidence.forEach((states: Set<string>): void => {
      if (states.size !== 1) { return; }
      if (states.has('pending')) { pending++; } else { submitted++; }
    });
    return new CourseSubmissionCounts(pending, submitted);
  }
}
