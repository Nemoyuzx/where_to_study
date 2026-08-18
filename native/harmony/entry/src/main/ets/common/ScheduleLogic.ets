// 与 iOS 端 Models.swift 中 ScheduleLogic 对应的纯函数逻辑：
// 考试周、周次、某日课程与占用节次。全部基于上海时区日历日。

import { Course, SlotMetadata } from './Models';
import { DateParts, StrictDates } from './StrictDates';

export class ScheduleLogic {
  // 课表实际存在周正序计数后的第 17、18 周对应周号。
  static examWeeks(courses: Course[]): Set<number> {
    const seen: Set<number> = new Set<number>();
    const weeks: number[] = [];
    for (const course of courses) {
      for (const week of course.weekNumbers) {
        if (week > 0 && !seen.has(week)) {
          seen.add(week);
          weeks.push(week);
        }
      }
    }
    weeks.sort((a: number, b: number) => a - b);
    const result: Set<number> = new Set<number>();
    if (weeks.length >= 17) {
      result.add(weeks[16]);
    }
    if (weeks.length >= 18) {
      result.add(weeks[17]);
    }
    return result;
  }

  static weekNumber(date: DateParts, termStart: DateParts): number {
    const days: number = StrictDates.epochDay(date.year, date.month, date.day) -
      StrictDates.epochDay(termStart.year, termStart.month, termStart.day);
    if (days < 0) {
      return 0;
    }
    return Math.floor(days / 7) + 1;
  }

  static applyingExamWeeks(courses: Course[]): Course[] {
    const examWeeks: Set<number> = ScheduleLogic.examWeeks(courses);
    const result: Course[] = [];
    for (const course of courses) {
      const courseExamWeeks: number[] = [];
      for (const week of course.weekNumbers) {
        if (examWeeks.has(week)) {
          courseExamWeeks.push(week);
        }
      }
      result.push(new Course(
        course.id, course.name, course.teacher, course.room, course.weekText,
        course.weekNumbers, courseExamWeeks, course.weekday, course.startSlot,
        course.endSlot, course.sectionText, course.timeRange
      ));
    }
    return result;
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
