// 与 iOS 端 Models.swift 中 ScheduleLogic 对应的纯函数逻辑：
// 周次、某日课程与占用节次。全部基于上海时区日历日。

import { Course, SlotMetadata } from './Models';
import { DateParts, StrictDates } from './StrictDates';

export class ScheduleLogic {
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
