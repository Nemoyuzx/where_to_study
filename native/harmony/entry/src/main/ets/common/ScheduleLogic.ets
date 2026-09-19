// 与 iOS 端 Models.swift 中 ScheduleLogic 对应的纯函数逻辑：
// 周次、某日课程与占用节次。全部基于上海时区日历日。

import { Course, ScheduleSnapshot, SlotMetadata } from './Models';
import { AcademicTime, ExamArrangement } from './AcademicModels';
import { DateParts, StrictDates } from './StrictDates';

export class ScheduleLogic {
  static startTime(course: Course, slots: SlotMetadata[] = SlotMetadata.defaults): string {
    return course.eventKind === 'exam' ? course.startTime : slots[course.startSlot]?.start ?? '';
  }

  static endTime(course: Course, slots: SlotMetadata[] = SlotMetadata.defaults): string {
    return course.eventKind === 'exam' ? course.endTime : slots[course.endSlot]?.end ?? '';
  }

  static startMinute(course: Course, slots: SlotMetadata[] = SlotMetadata.defaults): number | null {
    return AcademicTime.minute(ScheduleLogic.startTime(course, slots));
  }

  static endMinute(course: Course, slots: SlotMetadata[] = SlotMetadata.defaults): number | null {
    return AcademicTime.minute(ScheduleLogic.endTime(course, slots));
  }

  static hasTime(course: Course): boolean {
    const start: number | null = ScheduleLogic.startMinute(course);
    const end: number | null = ScheduleLogic.endMinute(course);
    return start !== null && end !== null && end > start;
  }

  static overlaps(left: Course, right: Course, slots: SlotMetadata[] = SlotMetadata.defaults): boolean {
    const ls: number | null = ScheduleLogic.startMinute(left, slots);
    const le: number | null = ScheduleLogic.endMinute(left, slots);
    const rs: number | null = ScheduleLogic.startMinute(right, slots);
    const re: number | null = ScheduleLogic.endMinute(right, slots);
    return ls !== null && le !== null && rs !== null && re !== null &&
      le > ls && re > rs && ls < re && rs < le;
  }

  static examCourse(exam: ExamArrangement, termStart: DateParts): Course | null {
    const date: DateParts | null = StrictDates.parseDateString(exam.date);
    if (date === null) { return null; }
    const timed: boolean = AcademicTime.validInterval(exam.startTime, exam.endTime);
    return new Course(exam.id, exam.name, '', exam.room, '', [], [],
      StrictDates.weekdayMonday1(date), -1, -1, '考试',
      timed ? exam.startTime + '-' + exam.endTime : '时间待定' +
        (exam.timeText.length > 0 ? ' · ' + exam.timeText : ''), '', 'exam', exam.date,
      timed ? exam.startTime : '', timed ? exam.endTime : '');
  }

  static effectiveCoursesOn(date: DateParts, schedule: ScheduleSnapshot,
    slots: SlotMetadata[] = SlotMetadata.defaults): Course[] {
    const termStart: DateParts | null = StrictDates.parseDateString(schedule.termStartDate);
    if (termStart === null) { return []; }
    const exams: Course[] = [];
    if (schedule.examSchedule !== null && schedule.examSchedule.status !== 'failed' &&
      schedule.examSchedule.termID === schedule.termID) {
      for (const item of schedule.examSchedule.items) {
        if (item.date === StrictDates.formatDateParts(date)) {
          const course: Course | null = ScheduleLogic.examCourse(item, termStart);
          if (course !== null) { exams.push(course); }
        }
      }
    }
    const courses: Course[] = ScheduleLogic.coursesOn(date, termStart, schedule.courses).filter(
      (course: Course) => !exams.some((exam: Course) => ScheduleLogic.overlaps(course, exam, slots)));
    const result: Course[] = courses.concat(exams);
    result.sort((lhs: Course, rhs: Course) => {
      const difference: number = (ScheduleLogic.startMinute(lhs, slots) ?? -1) -
        (ScheduleLogic.startMinute(rhs, slots) ?? -1);
      return difference !== 0 ? difference : lhs.id.localeCompare(rhs.id);
    });
    return result;
  }

  static effectiveBusySlots(date: DateParts, schedule: ScheduleSnapshot): Set<number> {
    const result: Set<number> = new Set<number>();
    for (const course of ScheduleLogic.effectiveCoursesOn(date, schedule)) {
      const start: number | null = ScheduleLogic.startMinute(course);
      const end: number | null = ScheduleLogic.endMinute(course);
      if (start === null || end === null || end <= start) { continue; }
      for (const slot of SlotMetadata.defaults) {
        const left: number = AcademicTime.minute(slot.start) ?? 0;
        const right: number = AcademicTime.minute(slot.end) ?? 0;
        if (start < right && left < end) { result.add(slot.index); }
      }
    }
    return result;
  }

  static latestExamDay(schedule: ScheduleSnapshot): DateParts | null {
    let latest: DateParts | null = null;
    if (schedule.examSchedule?.termID !== schedule.termID || schedule.examSchedule.status === 'failed') {
      return null;
    }
    for (const exam of schedule.examSchedule.items) {
      const day: DateParts | null = StrictDates.parseDateString(exam.date);
      if (day !== null && (latest === null || exam.date > StrictDates.formatDateParts(latest))) { latest = day; }
    }
    return latest;
  }

  static weekNumber(date: DateParts, termStart: DateParts): number {
    const days: number = StrictDates.epochDay(date.year, date.month, date.day) -
      StrictDates.epochDay(termStart.year, termStart.month, termStart.day);
    if (days < 0) {
      return 0;
    }
    return Math.floor(days / 7) + 1;
  }

  static coursesOn(date: DateParts, termStart: DateParts, courses: Course[]): Course[] {
    const week: number = ScheduleLogic.weekNumber(date, termStart);
    const weekday: number = StrictDates.weekdayMonday1(date);
    const result: Course[] = [];
    for (const course of courses) {
      if (course.weekday === weekday && course.weekNumbers.includes(week)) {
        result.push(course);
      }
    }
    result.sort((lhs: Course, rhs: Course) => {
      if (lhs.startSlot === rhs.startSlot) {
        return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
      }
      return lhs.startSlot - rhs.startSlot;
    });
    return result;
  }

  static busySlots(date: DateParts, termStart: DateParts, courses: Course[]): Set<number> {
    const result: Set<number> = new Set<number>();
    const dayCourses: Course[] = ScheduleLogic.coursesOn(date, termStart, courses);
    for (const course of dayCourses) {
      for (let slot = course.startSlot; slot <= course.endSlot; slot++) {
        if (slot >= 0 && slot < SlotMetadata.defaults.length) {
          result.add(slot);
        }
      }
    }
    return result;
  }
}
