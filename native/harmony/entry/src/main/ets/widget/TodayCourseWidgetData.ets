// 今日课程卡片的数据层，对应 iOS 端 TodayCourseWidgetData.swift 与
// Android 端 TodayCourseWidget.kt（课程状态/高亮/上下文/预览增强版）。
// 应用侧写入精简归档 widget-schedule.json（与沙箱课表同目录），
// 卡片侧（FormExtensionAbility）从同一沙箱读取，无需跨进程通道。
import { ScheduleSnapshot } from '../common/Models';
import { ScheduleLogic } from '../common/ScheduleLogic';
import { StrictDates, DateParts } from '../common/StrictDates';
import { AppLanguage } from '../common/AppLocalization';

export class WidgetArchiveCourse {
  readonly id: string;
  readonly name: string;
  readonly teacher: string;
  readonly room: string;
  readonly sectionText: string;
  readonly timeRange: string;
  readonly weekday: number;
  readonly weekNumbers: number[];
  readonly examWeekNumbers: number[];
  readonly startSlot: number;

  constructor(id: string, name: string, teacher: string, room: string, sectionText: string,
    timeRange: string, weekday: number, weekNumbers: number[], examWeekNumbers: number[],
    startSlot: number) {
    this.id = id;
    this.name = name;
    this.teacher = teacher;
    this.room = room;
    this.sectionText = sectionText;
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
  readonly preferences: WidgetCoursePreferences;

  constructor(termStartDate: string, fetchedAt: string, courses: WidgetArchiveCourse[],
    preferences: WidgetCoursePreferences = new WidgetCoursePreferences()) {
    this.termStartDate = termStartDate;
    this.fetchedAt = fetchedAt;
    this.courses = courses;
    this.preferences = preferences;
  }
}

// 卡片显示偏好（对应 Android widgetShowsLocation/widgetShowsTeacher/widgetCourseLimit）。
export class WidgetCoursePreferences {
  static readonly defaultLimit: number = 4;
  static readonly maximumLimit: number = 6;

  readonly showsLocation: boolean;
  readonly showsTeacher: boolean;
  readonly courseLimit: number;
  readonly language: string;

  constructor(showsLocation: boolean = true, showsTeacher: boolean = true,
    courseLimit: number = WidgetCoursePreferences.defaultLimit,
    language: string = AppLanguage.simplifiedChinese) {
    this.showsLocation = showsLocation;
    this.showsTeacher = showsTeacher;
    this.courseLimit = Number.isInteger(courseLimit) ?
      Math.min(Math.max(courseLimit, 1), WidgetCoursePreferences.maximumLimit) :
      WidgetCoursePreferences.defaultLimit;
    this.language = language === AppLanguage.english ? AppLanguage.english :
      AppLanguage.simplifiedChinese;
  }

  static fromJson(raw: Record<string, Object>): WidgetCoursePreferences {
    return new WidgetCoursePreferences(
      typeof raw['shows_location'] === 'boolean' ? raw['shows_location'] as boolean : true,
      typeof raw['shows_teacher'] === 'boolean' ? raw['shows_teacher'] as boolean : true,
      typeof raw['course_limit'] === 'number' ? raw['course_limit'] as number :
      WidgetCoursePreferences.defaultLimit,
      typeof raw['language'] === 'string' ? raw['language'] as string :
      AppLanguage.simplifiedChinese);
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['shows_location'] = this.showsLocation;
    out['shows_teacher'] = this.showsTeacher;
    out['course_limit'] = this.courseLimit;
    out['language'] = this.language;
    return out;
  }
}

// 课程在当前时刻的阶段（对应 Android WidgetCoursePhase）。
export enum CoursePhase {
  upcoming = 0,
  inProgress = 1,
  finished = 2
}

export class TodayCourseWidgetData {
  static readonly archiveFileName: string = 'widget-schedule.json';

  static archiveFilePath(filesDir: string): string {
    return filesDir + '/WhereToStudyNative/' + TodayCourseWidgetData.archiveFileName;
  }

  static scheduleToArchive(schedule: ScheduleSnapshot,
    preferences: WidgetCoursePreferences = new WidgetCoursePreferences()): WidgetArchive {
    const courses: WidgetArchiveCourse[] = [];
    for (const course of schedule.courses) {
      courses.push(new WidgetArchiveCourse(
        course.id, course.name, course.teacher, course.room, course.sectionText,
        course.timeRange, course.weekday, course.weekNumbers, course.examWeekNumbers,
        course.startSlot));
    }
    return new WidgetArchive(schedule.termStartDate, schedule.fetchedAt, courses, preferences);
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

  // 课程阶段：未来 / 进行中 / 已结束（按上海时区当前时刻判断）。
  static coursePhase(course: WidgetArchiveCourse, at: DateParts, minute: number): CoursePhase {
    const start: number | null = TodayCourseWidgetData.minuteOf(course.timeRange, true);
    const end: number | null = TodayCourseWidgetData.minuteOf(course.timeRange, false);
    if (start === null || end === null || end < start) {
      return CoursePhase.finished;
    }
    if (minute < start) {
      return CoursePhase.upcoming;
    }
    if (minute <= end) {
      return CoursePhase.inProgress;
    }
    return CoursePhase.finished;
  }

  static minuteOf(value: string, start: boolean): number | null {
    const normalized: string = value.replace(/[–—]/g, '-');
    const parts: string[] = normalized.split('-');
    const target: string = start ? (parts[0] ?? '') : (parts[1] ?? '');
    const nums: string[] = target.split(':');
    if (nums.length !== 2) {
      return null;
    }
    const h: number = Number(nums[0]);
    const m: number = Number(nums[1]);
    if (!Number.isFinite(h) || !Number.isFinite(m) || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }

  // 高亮课程：优先进行中，其次下一节（对应 Android highlightedCourse）。
  static highlightedCourse(
    courses: WidgetArchiveCourse[], minute: number
  ): WidgetArchiveCourse | null {
    for (const course of courses) {
      if (TodayCourseWidgetData.coursePhase(course, StrictDates.todayParts(), minute) ===
        CoursePhase.inProgress) {
        return course;
      }
    }
    for (const course of courses) {
      if (TodayCourseWidgetData.coursePhase(course, StrictDates.todayParts(), minute) ===
        CoursePhase.upcoming) {
        return course;
      }
    }
    return null;
  }

  // 日期上下文："8月21日 · 周五 · 第34周"。
  static dayContext(date: DateParts, weekNumber: number | null,
    english: boolean = false): string {
    if (english) {
      const weekdays: string[] = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const parts: string[] = [
        date.month.toString() + '/' + date.day.toString(),
        weekdays[StrictDates.weekdayMonday1(date) - 1]
      ];
      if (weekNumber !== null) {
        parts.push('Week ' + weekNumber.toString());
      }
      return parts.join(' · ');
    }
    const weekdays: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const parts: string[] = [
      date.month.toString() + '月' + date.day.toString() + '日',
      weekdays[StrictDates.weekdayMonday1(date) - 1]
    ];
    if (weekNumber !== null) {
      parts.push('第' + weekNumber.toString() + '周');
    }
    return parts.join(' · ');
  }

  // 状态摘要：进行中·几点下课 / 下一节·几点 / 今日课程已结束 / 今天可以自由安排。
  static statusSummary(courses: WidgetArchiveCourse[], minute: number,
    english: boolean = false): string {
    if (courses.length === 0) {
      return english ? 'No classes today' : '今天可以自由安排';
    }
    for (const course of courses) {
      if (TodayCourseWidgetData.coursePhase(course, StrictDates.todayParts(), minute) ===
        CoursePhase.inProgress) {
        const end: string = TodayCourseWidgetData.endTimeOf(course.timeRange);
        return english ? (end.length === 0 ? 'In progress' : 'In progress · Ends ' + end) :
          (end.length === 0 ? '课程进行中' : '进行中 · ' + end + ' 下课');
      }
    }
    for (const course of courses) {
      if (TodayCourseWidgetData.coursePhase(course, StrictDates.todayParts(), minute) ===
        CoursePhase.upcoming) {
        const start: string = TodayCourseWidgetData.startTimeOf(course.timeRange);
        return english ? (start.length === 0 ? 'Upcoming class' : 'Next · ' + start) :
          (start.length === 0 ? '还有待上课程' : '下一节 · ' + start);
      }
    }
    return english ? 'Classes finished for today' : '今日课程已结束';
  }

  static startTimeOf(value: string): string {
    const parts: string[] = value.split('-');
    return parts.length > 0 ? (parts[0] ?? '').trim() : '';
  }

  static endTimeOf(value: string): string {
    const parts: string[] = value.split('-');
    return parts.length > 1 ? (parts[1] ?? '').trim() : '';
  }

  // 课程标题：高亮时加前缀（进行中 · X / 下一节 · X）。
  static courseTitle(course: WidgetArchiveCourse, minute: number,
    english: boolean = false): string {
    const phase: CoursePhase = TodayCourseWidgetData.coursePhase(
      course, StrictDates.todayParts(), minute);
    if (phase === CoursePhase.inProgress) {
      return (english ? 'In progress' : '进行中') + ' · ' + course.name;
    }
    if (phase === CoursePhase.upcoming) {
      return (english ? 'Next' : '下一节') + ' · ' + course.name;
    }
    return course.name;
  }

  // 详情："时间 · 节次 · 教室 · 教师"（按偏好裁剪）。
  static courseDetails(course: WidgetArchiveCourse, prefs: WidgetCoursePreferences): string {
    const parts: string[] = [];
    if (course.timeRange.length > 0) {
      parts.push(course.timeRange);
    }
    if (course.sectionText.length > 0) {
      parts.push(course.sectionText);
    }
    if (prefs.showsLocation && course.room.length > 0) {
      parts.push(course.room);
    }
    if (prefs.showsTeacher && course.teacher.length > 0) {
      parts.push(course.teacher);
    }
    return parts.join(' · ');
  }

  // SDK FormDimension: 2=2×2, 3=2×4, 4=4×4。两种矮卡片等高。
  // 每行 34vp，预留标题、上下文、明日分组和溢出提示所需高度。
  static capacityForDimension(dimension: number): number {
    return dimension === 4 ? 6 : 2;
  }

  static bindingAtEpoch(archive: WidgetArchive | null, prefs: WidgetCoursePreferences,
    dimension: number, nowEpochMs: number = Date.now()): Record<string, Object> {
    const shifted: Date = new Date(nowEpochMs + 8 * 3600000);
    return TodayCourseWidgetData.binding(archive, prefs,
      new DateParts(shifted.getUTCFullYear(), shifted.getUTCMonth() + 1, shifted.getUTCDate()),
      shifted.getUTCHours() * 60 + shifted.getUTCMinutes(), dimension);
  }

  static minutesUntilBeijingMidnight(nowEpochMs: number = Date.now()): number {
    const shifted: number = nowEpochMs + 8 * 3600000;
    return Math.ceil((86400000 - ((shifted % 86400000 + 86400000) % 86400000)) / 60000);
  }

  static nextRefreshMinutes(nowEpochMs: number = Date.now()): number {
    // 常规每天48次，跨日额外对齐最多1次，低于系统每日50次的定时刷新配额。
    return Math.max(5, Math.min(30, TodayCourseWidgetData.minutesUntilBeijingMidnight(nowEpochMs)));
  }

  // 今日优先；明日只补剩余容量，课程数量限制同时约束两日总行数。
  static binding(archive: WidgetArchive | null, prefs: WidgetCoursePreferences,
    today: DateParts = StrictDates.todayParts(), minute: number = TodayCourseWidgetData.nowMinute(),
    dimension: number = 4
  ): Record<string, Object> {
    const todayCourses: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(today, archive);
    const tomorrow: DateParts = StrictDates.addDays(today, 1);
    const tomorrowCourses: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(tomorrow, archive);
    const week: number | null = archive === null ? null :
      (ScheduleLogic.weekNumber(today, StrictDates.parseDateString(archive.termStartDate) ?? today));
    const limit: number = Math.min(prefs.courseLimit,
      TodayCourseWidgetData.capacityForDimension(dimension));
    const shownToday: number = Math.min(todayCourses.length, limit);
    const shownTomorrow: number = Math.min(tomorrowCourses.length, limit - shownToday);
    const tomorrowWeek: number | null = archive === null ? null : ScheduleLogic.weekNumber(
      tomorrow, StrictDates.parseDateString(archive.termStartDate) ?? tomorrow);
    const highlighted: WidgetArchiveCourse | null = TodayCourseWidgetData.highlightedCourse(
      todayCourses, minute);
    const english: boolean = prefs.language === AppLanguage.english;
    const out: Record<string, Object> = {};
    out['todayTitle'] = english ? 'Today\'s Courses' : '今日课程';
    out['todayCountText'] = todayCourses.length === 0 ? '' : todayCourses.length.toString() +
      (english ? ' courses' : ' 门');
    out['dateContext'] = TodayCourseWidgetData.dayContext(today, week, english);
    out['statusText'] = TodayCourseWidgetData.statusSummary(todayCourses, minute, english);
    out['tomorrowTitle'] = shownTomorrow > 0 ? (english ? 'Tomorrow' : '明日') + ' · ' +
      tomorrow.month.toString() + '/' + tomorrow.day.toString() +
      (tomorrowWeek === null ? '' : (english ? ' · W' : ' · 第') + tomorrowWeek.toString() +
        (english ? '' : '周')) +
      (tomorrowCourses.length > shownTomorrow ? ' · +' +
        (tomorrowCourses.length - shownTomorrow).toString() : '') : '';
    out['todayShownCount'] = shownToday;
    out['tomorrowShownCount'] = shownTomorrow;
    for (let i = 0; i < 6; i++) {
      const isTomorrow: boolean = i >= shownToday;
      const course: WidgetArchiveCourse | undefined = isTomorrow ?
        tomorrowCourses[i - shownToday] : todayCourses[i];
      const key: string = (i + 1).toString();
      out['course' + key + 'Group'] = i === shownToday && shownTomorrow > 0 ? out['tomorrowTitle'] : '';
      if (course === undefined || i >= shownToday + shownTomorrow) {
        out['course' + key + 'Name'] = '';
        out['course' + key + 'Details'] = '';
        out['course' + key + 'Highlighted'] = false;
      } else {
        out['course' + key + 'Name'] = isTomorrow ? course.name :
          TodayCourseWidgetData.courseTitle(course, minute, english);
        out['course' + key + 'Details'] = TodayCourseWidgetData.courseDetails(course, prefs);
        out['course' + key + 'Highlighted'] = !isTomorrow && course.id === (highlighted?.id ?? '');
      }
    }
    out['moreHint'] = todayCourses.length > shownToday ?
      (english ? (todayCourses.length - shownToday).toString() + ' more courses today' :
        '今日另有 ' + (todayCourses.length - shownToday).toString() + ' 门课程') : '';
    if (archive === null) {
      out['emptyGlyph'] = '↻';
      out['emptyText'] = english ? 'Open the app to fetch your schedule' :
        '打开应用获取个人课表';
    } else if (todayCourses.length === 0 && shownTomorrow === 0) {
      out['emptyGlyph'] = '✓';
      out['emptyText'] = english ? 'No classes today' : '今日无课';
    } else {
      out['emptyGlyph'] = '';
      out['emptyText'] = '';
    }
    return out;
  }

  static nowMinute(): number {
    const shifted: Date = new Date(Date.now() + 8 * 3600000);
    return shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  }

  static previewBinding(prefs: WidgetCoursePreferences, dimension: number,
    nowEpochMs: number = Date.now()): Record<string, Object> {
    const shifted: Date = new Date(nowEpochMs + 8 * 3600000);
    const today: DateParts = new DateParts(shifted.getUTCFullYear(), shifted.getUTCMonth() + 1,
      shifted.getUTCDate());
    return TodayCourseWidgetData.bindingAtEpoch(TodayCourseWidgetData.previewArchive(today), prefs,
      dimension, nowEpochMs);
  }

  // 设置页样式预览用示例归档（对应 Android previewContent / Apple previewArchive）。
  static previewArchive(today: DateParts = StrictDates.todayParts()): WidgetArchive {
    const weekday: number = StrictDates.weekdayMonday1(today);
    const courses: WidgetArchiveCourse[] = [];
    const items: [string, string, string, string, string, number, number][] = [
      ['高等数学', '示例教师', '教2-101', '1-2节', '08:00-09:35', 0, 1],
      ['数据挖掘', '示例教师', '教3-335', '3-5节', '09:50-12:15', 2, 4],
      ['计算机网络', '示例教师', '教4-201', '6-7节', '13:00-14:35', 5, 6],
      ['神经网络与深度学习', '示例教师', '教3-539', '8-9节', '14:45-16:25', 7, 8],
      ['体育', '示例教师', '体育馆', '10-11节', '16:35-18:10', 9, 10],
      ['学术英语', '示例教师', '主楼-201', '12-13节', '18:30-20:05', 11, 12],
    ];
    const termStart: DateParts = StrictDates.addDays(today, 1 - weekday);
    const tomorrow: DateParts = StrictDates.addDays(today, 1);
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const day: DateParts = i === 0 ? today : tomorrow;
      courses.push(new WidgetArchiveCourse(
        'preview-' + i.toString(), item[0], item[1], item[2], item[3], item[4],
        StrictDates.weekdayMonday1(day), [ScheduleLogic.weekNumber(day, termStart)], [], item[5]));
    }
    return new WidgetArchive(StrictDates.formatDateParts(termStart),
      'widget-preview', courses);
  }
}
