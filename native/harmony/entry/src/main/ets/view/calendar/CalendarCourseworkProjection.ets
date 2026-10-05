import { AssignmentDeadlineItem } from '../../net/CalendarDailyInfoClient';
import { UCloudCourse } from '../../net/UCloudAssignmentClient';
import { QMPlusSnapshot } from '../../net/QMPlusSnapshot';
import { CourseQMPlusScope } from '../../common/CourseLogic';
import { SHANGHAI_OFFSET_MS, StrictDates } from '../../common/StrictDates';

export class CalendarCourseworkItem {
  readonly key: string;
  readonly title: string;
  readonly deadline: string;
  readonly source: string;
  readonly courseID: string | null;
  readonly kind: string;
  constructor(key: string, title: string, deadline: string, source: string, courseID: string | null, kind: string = 'assignment') {
    this.key = key; this.title = title; this.deadline = deadline; this.source = source; this.courseID = courseID;
    this.kind = kind;
  }
}

// Cached projection only. Never fetch/guess a course or substitute cutoff/open.
export class CalendarCourseworkProjection {
  static cloud(item: AssignmentDeadlineItem, courses: UCloudCourse[]): CalendarCourseworkItem {
    const matches: UCloudCourse[] = courses.filter((course: UCloudCourse): boolean => item.courseID !== null ?
      course.id === item.courseID : item.courseName !== null && item.courseName.trim().length > 0 &&
        course.name?.trim() === item.courseName.trim());
    return new CalendarCourseworkItem('ucloud.' + item.id, item.title, item.deadline, 'ucloud',
      matches.length === 1 ? matches[0].id : null);
  }

  static qm(date: string, snapshot: QMPlusSnapshot | null): CalendarCourseworkItem[] {
    const result: CalendarCourseworkItem[] = [];
    for (const item of CourseQMPlusScope.currentActivities(snapshot)) {
      const raw: string | null = item.kind === 'quiz' ? item.closesAt : item.dueAt;
      if (raw === null) { continue; }
      const epoch: number | null = StrictDates.parseFetchedAt(raw);
      if (epoch === null) { continue; }
      const parts = StrictDates.partsFromEpochDay(Math.floor((epoch + SHANGHAI_OFFSET_MS) / 86400000));
      if (StrictDates.formatDateParts(parts) !== date) { continue; }
      const clock: Date = new Date(epoch + SHANGHAI_OFFSET_MS);
      const deadline: string = date + ' ' + clock.getUTCHours().toString().padStart(2, '0') + ':' +
        clock.getUTCMinutes().toString().padStart(2, '0');
      result.push(new CalendarCourseworkItem('qmplus.' + item.kind + '.' + item.id, item.title, deadline, 'qmplus', item.courseID, item.kind));
    }
    return result;
  }
}
