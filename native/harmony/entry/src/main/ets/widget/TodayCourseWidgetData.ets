// 今日课程卡片的数据层，对应 iOS 端 TodayCourseWidgetData.swift。
// 应用侧写入精简归档 widget-schedule.json（与沙箱课表同目录），
// 卡片侧（FormExtensionAbility）从同一沙箱读取，无需跨进程通道。
import { ScheduleSnapshot } from '../common/Models';
import { ScheduleLogic } from '../common/ScheduleLogic';
import { StrictDates, DateParts } from '../common/StrictDates';

export class WidgetArchiveCourse {
  readonly id: string;
  readonly name: string;
  readonly room: string;
  readonly timeRange: string;
  readonly weekday: number;
  readonly weekNumbers: number[];
  readonly examWeekNumbers: number[];
  readonly startSlot: number;

  constructor(id: string, name: string, room: string, timeRange: string, weekday: number,
    weekNumbers: number[], examWeekNumbers: number[], startSlot: number) {
    this.id = id;
    this.name = name;
    this.room = room;
    this.timeRange = timeRange;
    this.weekday = weekday;
    this.weekNumbers = weekNumbers;
    this.examWeekNumbers = examWeekNumbers;
    this.startSlot = startSlot;
  }
}

export class WidgetArchive {
  readonly termStartDate: string;
  readonly fetchedAt: string;
  readonly courses: WidgetArchiveCourse[];

  constructor(termStartDate: string, fetchedAt: string, courses: WidgetArchiveCourse[]) {
    this.termStartDate = termStartDate;
    this.fetchedAt = fetchedAt;
    this.courses = courses;
  }
}

export class TodayCourseWidgetData {
  static readonly archiveFileName: string = 'widget-schedule.json';

  static archiveFilePath(filesDir: string): string {
    return filesDir + '/WhereToStudyNative/' + TodayCourseWidgetData.archiveFileName;
  }

  static scheduleToArchive(schedule: ScheduleSnapshot): WidgetArchive {
    const courses: WidgetArchiveCourse[] = [];
    for (const course of schedule.courses) {
      courses.push(new WidgetArchiveCourse(
        course.id, course.name, course.room, course.timeRange, course.weekday,
        course.weekNumbers, course.examWeekNumbers, course.startSlot));
    }
    return new WidgetArchive(schedule.termStartDate, schedule.fetchedAt, courses);
  }

  static coursesOn(date: DateParts, archive: WidgetArchive | null): WidgetArchiveCourse[] {
    if (archive === null) {
      return [];
    }
    const termStart: DateParts | null = StrictDates.parseDateString(archive.termStartDate);
    if (termStart === null) {
      return [];
    }
    const week: number = ScheduleLogic.weekNumber(date, termStart);
    const weekday: number = StrictDates.weekdayMonday1(date);
    const result: WidgetArchiveCourse[] = [];
    for (const course of archive.courses) {
      if (course.weekday === weekday && course.weekNumbers.includes(week)) {
        result.push(course);
      }
    }
    result.sort((lhs: WidgetArchiveCourse, rhs: WidgetArchiveCourse) => {
      if (lhs.startSlot !== rhs.startSlot) {
        return lhs.startSlot - rhs.startSlot;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    return result;
  }

  // 卡片绑定数据：今天课程条目 + 明日提示 + 空态文案。
  // courseLimit 按卡片尺寸传入（2*2 两行，其余三行），BUG-040 修复。
  // today 可注入便于测试（默认取上海时区当天）。
  static binding(archive: WidgetArchive | null, courseLimit: number = 3,
    today: DateParts = StrictDates.todayParts()): Record<string, Object> {
    const todayCourses: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(today, archive);
    const tomorrowCourses: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(
      StrictDates.addDays(today, 1), archive);
    const limit: number = Math.max(1, courseLimit);
    // 逐行课程数据：对应 Android 卡片的 WidgetCourseName/WidgetCourseDetails，
    // 详情为 "时间 · 教室"（无教室则仅时间），最多 3 行由卡片渲染。
    const rows: string[][] = [];
    for (let i = 0; i < Math.min(todayCourses.length, limit); i++) {
      const course: WidgetArchiveCourse = todayCourses[i];
      const details: string[] = [course.timeRange];
      if (course.room.length > 0) {
        details.push(course.room);
      }
      rows.push([course.name, details.join(' · ')]);
    }
    const out: Record<string, Object> = {};
    out['todayTitle'] = '今日课程';
    out['todayCountText'] = todayCourses.length === 0 ? '' : todayCourses.length.toString() + ' 门';
    out['course1Name'] = rows.length > 0 ? rows[0][0] : '';
    out['course1Details'] = rows.length > 0 ? rows[0][1] : '';
    out['course2Name'] = rows.length > 1 ? rows[1][0] : '';
    out['course2Details'] = rows.length > 1 ? rows[1][1] : '';
    out['course3Name'] = rows.length > 2 ? rows[2][0] : '';
    out['course3Details'] = rows.length > 2 ? rows[2][1] : '';
    out['moreHint'] = todayCourses.length > limit ?
      '另有 ' + (todayCourses.length - limit).toString() + ' 门课程' : '';
    out['tomorrowHint'] = tomorrowCourses.length === 0 ?
      '明天暂无课程' : '明天 ' + tomorrowCourses.length.toString() + ' 门课';
    if (archive === null) {
      out['emptyGlyph'] = '↻';
      out['emptyText'] = '打开应用获取个人课表';
    } else if (todayCourses.length === 0) {
      out['emptyGlyph'] = '✓';
      out['emptyText'] = '今天没有课程';
    } else {
      out['emptyGlyph'] = '';
      out['emptyText'] = '';
    }
    return out;
  }
}
