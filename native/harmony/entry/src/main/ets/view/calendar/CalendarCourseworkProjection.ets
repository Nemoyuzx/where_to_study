import { AssignmentDeadlineItem } from '../../net/CalendarDailyInfoClient';
import { UCloudCourse } from '../../net/UCloudAssignmentClient';
import { QMPlusSnapshot } from '../../net/QMPlusSnapshot';
import { CourseQMPlusScope, CourseCloudScope } from '../../common/CourseLogic';
import { SHANGHAI_OFFSET_MS, StrictDates } from '../../common/StrictDates';

export class CalendarCourseworkItem {
  readonly key: string;
  readonly title: string;
  readonly deadline: string;
  readonly source: string;
  readonly courseID: string | null;
  readonly kind: string;
  readonly pending: boolean;
  constructor(key: string, title: string, deadline: string, source: string, courseID: string | null, kind: string = 'assignment', pending: boolean = false) {
    this.key = key; this.title = title; this.deadline = deadline; this.source = source; this.courseID = courseID;
    this.kind = kind;
    this.pending = pending;
  }
}

// Cached projection only. Never fetch/guess a course or substitute cutoff/open.
export class CalendarCourseworkProjection {
  static cloud(item: AssignmentDeadlineItem, courses: UCloudCourse[]): CalendarCourseworkItem {
    const matches: UCloudCourse[] = courses.filter((course: UCloudCourse): boolean => item.courseID !== null ?
      course.id === item.courseID : item.courseName !== null && item.courseName.trim().length > 0 &&
        course.name?.trim() === item.courseName.trim());
    return new CalendarCourseworkItem('ucloud.' + item.id, item.title, item.deadline, 'ucloud',
      matches.length === 1 ? matches[0].id : null, 'assignment', CourseCloudScope.submissionCounts([item]).pending > 0);
  }

  static qm(date: string, snapshot: QMPlusSnapshot | null): CalendarCourseworkItem[] {
    const result: CalendarCourseworkItem[] = [];
    for (const item of CourseQMPlusScope.currentActivities(snapshot)) {
      const raw: string | null = item.kind === 'quiz' ? item.closesAt : item.dueAt;
      if (raw === null) { continue; }
      const epoch: number | null = CalendarDeadlineMoments.timestamp(raw);
      if (epoch === null) { continue; }
      const parts = StrictDates.partsFromEpochDay(Math.floor((epoch + SHANGHAI_OFFSET_MS) / 86400000));
      if (StrictDates.formatDateParts(parts) !== date) { continue; }
      const clock: Date = new Date(epoch + SHANGHAI_OFFSET_MS);
      const deadline: string = date + ' ' + clock.getUTCHours().toString().padStart(2, '0') + ':' +
        clock.getUTCMinutes().toString().padStart(2, '0');
      const pending: boolean = item.kind === 'assignment' && CourseCloudScope.submissionCounts([
        new AssignmentDeadlineItem(item.id, item.title, null, deadline, item.status, item.courseID)]).pending > 0;
      result.push(new CalendarCourseworkItem('qmplus.' + item.kind + '.' + item.id, item.title, deadline, 'qmplus', item.courseID, item.kind, pending));
    }
    return result;
  }
}

export class CalendarDeadlineMoment {
  readonly minute: number;
  readonly items: CalendarCourseworkItem[];
  constructor(minute: number, items: CalendarCourseworkItem[]) { this.minute = minute; this.items = items; }
  clock(): string { return Math.floor(this.minute / 60).toString().padStart(2, '0') + ':' +
    (this.minute % 60).toString().padStart(2, '0'); }
}

export class CalendarDeadlineBadge extends CalendarDeadlineMoment {
  readonly top: number;
  readonly minutes: number[];
  constructor(minute: number, items: CalendarCourseworkItem[], top: number, minutes: number[]) {
    super(minute, items); this.top = top; this.minutes = minutes;
  }
}

export class CalendarDeadlineMoments {
  static timestamp(value: string): number | null {
    // The official bridge emits toISOString() with milliseconds. A minute
    // marker does not use sub-second precision; keep strict civil validation.
    return StrictDates.parseFetchedAt(value.replace(/(\d{2})\.\d{1,3}(Z|[+-]\d{2}:\d{2})$/, '$1$2'));
  }
  static barWidth(dayWidth: number): number { return Math.max(dayWidth - 8, 0); }
  static barX(dayWidth: number, index: number): number { return dayWidth * index + 4; }
  static showsPending(items: CalendarCourseworkItem[]): boolean {
    return items.some((item: CalendarCourseworkItem): boolean => item.kind === 'assignment' && item.pending);
  }
  static cloudOn(date: string, catalog: AssignmentDeadlineItem[], courses: UCloudCourse[]): CalendarCourseworkItem[] {
    const result: CalendarCourseworkItem[] = [];
    for (const item of catalog) {
      const minute: number | null = CalendarDeadlineMoments.minute(date, item.deadline);
      if (minute === null) { continue; }
      const projection: CalendarCourseworkItem = CalendarCourseworkProjection.cloud(item, courses);
      const clock: string = Math.floor(minute / 60).toString().padStart(2, '0') + ':' +
        (minute % 60).toString().padStart(2, '0');
      result.push(new CalendarCourseworkItem(projection.key, projection.title, date + ' ' + clock,
        projection.source, projection.courseID, projection.kind, projection.pending));
    }
    return result;
  }

  static badges(groups: CalendarDeadlineMoment[], start: number, height: number, hourHeight: number,
    headers: number[]): CalendarDeadlineBadge[] {
    const result: CalendarDeadlineBadge[] = [];
    for (const group of groups) {
      const top: number = CalendarDeadlineMoments.labelY((group.minute - start) / 60 * hourHeight, height, headers);
      const previous: CalendarDeadlineBadge | undefined = result[result.length - 1];
      if (previous !== undefined && top < previous.top + 20) {
        result[result.length - 1] = new CalendarDeadlineBadge(previous.minute, previous.items.concat(group.items),
          previous.top, previous.minutes.concat([group.minute]));
      } else { result.push(new CalendarDeadlineBadge(group.minute, group.items, top, [group.minute])); }
    }
    return result;
  }
  static minute(date: string, deadline: string): number | null {
    const local: RegExpMatchArray | null = deadline.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$/);
    if (local !== null) {
      const hour: number = Number(local[2]); const minute: number = Number(local[3]);
      return local[1] === date && StrictDates.parseDateString(date) !== null && hour < 24 && minute < 60 &&
        (local[4] === undefined || Number(local[4]) < 60) ? hour * 60 + minute : null;
    }
    const epoch: number | null = CalendarDeadlineMoments.timestamp(deadline);
    if (epoch === null) { return null; }
    const clock: Date = new Date(epoch + SHANGHAI_OFFSET_MS);
    const shanghaiDate: string = StrictDates.formatDateParts(StrictDates.partsFromEpochDay(
      Math.floor((epoch + SHANGHAI_OFFSET_MS) / 86400000)));
    return shanghaiDate === date ? clock.getUTCHours() * 60 + clock.getUTCMinutes() : null;
  }

  static groups(date: string, items: CalendarCourseworkItem[]): CalendarDeadlineMoment[] {
    const grouped: Map<number, CalendarCourseworkItem[]> = new Map<number, CalendarCourseworkItem[]>();
    const seen: Set<string> = new Set<string>();
    for (const item of items) {
      const minute: number | null = CalendarDeadlineMoments.minute(date, item.deadline);
      if (minute === null || seen.has(item.key)) { continue; }
      seen.add(item.key);
      const values: CalendarCourseworkItem[] = grouped.get(minute) ?? [];
      values.push(item); grouped.set(minute, values);
    }
    return Array.from(grouped.keys()).sort((a: number, b: number): number => a - b)
      .map((minute: number): CalendarDeadlineMoment => new CalendarDeadlineMoment(minute, grouped.get(minute) ?? []));
  }

  static bounds(original: number[], groups: CalendarDeadlineMoment[]): number[] {
    let start: number = original[0]; let end: number = original[1];
    for (const group of groups) {
      start = Math.min(start, Math.floor(group.minute / 60) * 60);
      end = Math.max(end, Math.ceil((group.minute + 1) / 60) * 60);
    }
    return [start, end];
  }

  static labelY(anchor: number, bodyHeight: number, courseHeaders: number[]): number {
    let top: number = Math.max(0, Math.min(anchor - 9, bodyHeight - 18));
    for (const header of courseHeaders) {
      if (top < header + 24 && top + 18 > header) { top = header + 24; }
    }
    return Math.max(0, Math.min(top, bodyHeight - 18));
  }
}
