import { Course, ScheduleSnapshot } from './Models';
import { JsonUtil } from './JsonUtil';
import { Sha1 } from './Sha1';
import { ScheduleLogic } from './ScheduleLogic';
import { DateParts, StrictDates } from './StrictDates';

// 删除规则与原始课表分开保存；date 为空表示本学期整门课程。
export class CourseRemovalRecord {
  readonly id: string;
  readonly accountScope: string;
  readonly termID: string;
  readonly sourceCourseID: string;
  readonly name: string;
  readonly teacher: string;
  readonly date: string;
  readonly startSlot: number;
  readonly endSlot: number;

  constructor(accountScope: string, termID: string, sourceCourseID: string, name: string,
    teacher: string, date: string, startSlot: number, endSlot: number) {
    this.accountScope = accountScope;
    this.termID = termID;
    this.sourceCourseID = sourceCourseID.trim();
    this.name = name.trim();
    this.teacher = teacher.trim();
    this.date = date;
    this.startSlot = startSlot;
    this.endSlot = endSlot;
    this.id = Sha1.hexOfUtf8(JSON.stringify([
      accountScope, termID, this.sourceCourseID, this.name, this.teacher, date,
      startSlot.toString(), endSlot.toString()
    ]));
  }

  matchesCourse(course: Course): boolean {
    if (this.sourceCourseID.length > 0 && course.sourceCourseID.trim().length > 0) {
      return this.sourceCourseID === course.sourceCourseID.trim();
    }
    return this.name === course.name.trim() && this.teacher === course.teacher.trim();
  }

  toJson(): Record<string, Object> {
    return {
      'account_scope': this.accountScope, 'term_id': this.termID,
      'source_course_id': this.sourceCourseID, 'name': this.name, 'teacher': this.teacher,
      'date': this.date, 'start_slot': this.startSlot, 'end_slot': this.endSlot
    };
  }

  static fromJson(raw: Record<string, Object>): CourseRemovalRecord {
    const date: string = JsonUtil.string(raw['date']);
    const accountScope: string = JsonUtil.string(raw['account_scope']);
    const termID: string = JsonUtil.string(raw['term_id']);
    const name: string = JsonUtil.string(raw['name']);
    const startSlot: number = JsonUtil.number(raw['start_slot'], -1);
    const endSlot: number = JsonUtil.number(raw['end_slot'], -1);
    if (accountScope.length === 0 || termID.length === 0 || name.trim().length === 0 ||
      (date.length > 0 && (StrictDates.parseDateString(date) === null ||
        startSlot < 0 || endSlot < startSlot || endSlot > 13))) {
      throw new Error('本地课程删除记录格式不正确。');
    }
    return new CourseRemovalRecord(accountScope, termID, JsonUtil.string(raw['source_course_id']),
      name, JsonUtil.string(raw['teacher']), date, startSlot, endSlot);
  }
}

export class CourseRemovalLogic {
  static accountScope(account: string): string {
    return Sha1.hexOfUtf8(account.trim());
  }

  static create(account: string, schedule: ScheduleSnapshot, course: Course,
    date: DateParts, wholeCourse: boolean): CourseRemovalRecord {
    return new CourseRemovalRecord(CourseRemovalLogic.accountScope(account), schedule.termID,
      course.sourceCourseID, course.name, course.teacher,
      wholeCourse ? '' : StrictDates.formatDateParts(date),
      wholeCourse ? -1 : course.startSlot, wholeCourse ? -1 : course.endSlot);
  }

  static apply(schedule: ScheduleSnapshot, account: string,
    records: CourseRemovalRecord[]): ScheduleSnapshot {
    const scope: string = CourseRemovalLogic.accountScope(account);
    const active: CourseRemovalRecord[] = records.filter((record: CourseRemovalRecord): boolean =>
      record.accountScope === scope && record.termID === schedule.termID);
    const termStart: DateParts | null = StrictDates.parseDateString(schedule.termStartDate);
    if (active.length === 0 || termStart === null) {
      return schedule;
    }
    const courses: Course[] = [];
    for (const course of schedule.courses) {
      const matched: CourseRemovalRecord[] = active.filter((record: CourseRemovalRecord): boolean =>
        record.matchesCourse(course));
      if (matched.some((record: CourseRemovalRecord): boolean => record.date.length === 0)) {
        continue;
      }
      const removedWeeks: Set<number> = new Set<number>();
      for (const record of matched) {
        const date: DateParts | null = StrictDates.parseDateString(record.date);
        if (date !== null && StrictDates.weekdayMonday1(date) === course.weekday &&
          record.startSlot === course.startSlot && record.endSlot === course.endSlot) {
          removedWeeks.add(ScheduleLogic.weekNumber(date, termStart));
        }
      }
      const weeks: number[] = course.weekNumbers.filter((week: number): boolean => !removedWeeks.has(week));
      if (weeks.length === 0 && course.weekNumbers.length > 0) {
        continue;
      }
      courses.push(new Course(course.id, course.name, course.teacher, course.room, course.weekText,
        weeks, course.examWeekNumbers, course.weekday, course.startSlot, course.endSlot,
        course.sectionText, course.timeRange, course.sourceCourseID));
    }
    return new ScheduleSnapshot(schedule.termID, schedule.termStartDate, schedule.fetchedAt, courses);
  }
}
