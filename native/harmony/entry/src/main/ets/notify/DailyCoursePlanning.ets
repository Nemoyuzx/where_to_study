// 每日课程摘要的纯逻辑（请求规划 + 协调器），对应 iOS 端
// DailyCourseNotificationPlanner / DailyCourseNotificationCoordinator。
// 无平台依赖，可被主机侧单元测试引用。

import { Course, ScheduleSnapshot } from '../common/Models';
import { ScheduleLogic } from '../common/ScheduleLogic';
import { StrictDates, DateParts, SHANGHAI_OFFSET_MS } from '../common/StrictDates';

export class PreClassNotificationSettings {
  static readonly enabledKey: string = 'preClassNotificationsEnabled';
  static readonly minutesKey: string = 'preClassNotificationLeadMinutes';
  static readonly maximumCount: number = 5;

  static valid(values: number[]): boolean {
    return values.length >= 1 && values.length <= PreClassNotificationSettings.maximumCount &&
      values.every((value: number) => Number.isInteger(value) && value >= 1 && value <= 1440) &&
      new Set<number>(values).size === values.length;
  }

  static normalized(values: number[]): number[] {
    return PreClassNotificationSettings.valid(values) ? values.slice() : [10];
  }

  static parseDrafts(values: string[]): number[] | null {
    if (!values.every((value: string) => /^\d+$/.test(value.trim()))) { return null; }
    const minutes: number[] = values.map((value: string) => Number(value.trim()));
    return PreClassNotificationSettings.valid(minutes) ? minutes : null;
  }
}

export class DailyCourseNotificationSettings {
  static readonly enabledKey: string = 'dailyCourseNotificationsEnabled';
  static readonly minutesKey: string = 'dailyCourseNotificationMinutes';
  static readonly defaultMinutes: number = 450;

  static normalizeMinutes(value: number): number {
    return Number.isInteger(value) && value >= 0 && value <= 1439 ? value :
      DailyCourseNotificationSettings.defaultMinutes;
  }

  static timeText(value: number): string {
    const minutes: number = DailyCourseNotificationSettings.normalizeMinutes(value);
    const hour: number = Math.floor(minutes / 60);
    const minute: number = minutes % 60;
    return (hour < 10 ? '0' : '') + hour.toString() + ':' +
      (minute < 10 ? '0' : '') + minute.toString();
  }
}

export enum DailyCourseNotificationAuthorization {
  notDetermined = 0,
  denied = 1,
  authorized = 2
}

export class DailyCourseNotificationRequest {
  readonly identifier: string;
  readonly fireEpochMs: number;
  readonly title: string;
  readonly body: string;
  readonly notificationId: number;

  constructor(identifier: string, fireEpochMs: number, title: string, body: string, notificationId: number = 0) {
    this.identifier = identifier;
    this.fireEpochMs = fireEpochMs;
    this.title = title;
    this.body = body;
    this.notificationId = notificationId;
  }
}

export class DailyCourseNotificationPlanner {
  static readonly identifierPrefix: string = 'daily-course-summary.';
  // API 24 普通应用最多30条有效提醒（并非整个系统的全局上限）。
  static readonly maximumPendingRequestCount: number = 30;
  static readonly maximumScheduleWeek: number = 53;
  static readonly maximumScanDayCount: number = 400;

  static requests(
    schedule: ScheduleSnapshot, nowEpochMs: number, scanDayLimit?: number,
    english: boolean = false,
    reminderMinutes: number = DailyCourseNotificationSettings.defaultMinutes
  ): DailyCourseNotificationRequest[] {
    const days: DateParts[] = DailyCourseNotificationPlanner.scheduleDays(schedule, nowEpochMs, scanDayLimit);
    const requests: DailyCourseNotificationRequest[] = [];
    for (const day of days) {
      if (requests.length >= DailyCourseNotificationPlanner.maximumPendingRequestCount) { break; }
      const dayEpoch: number = StrictDates.epochDay(day.year, day.month, day.day);
      // 所选北京时间转换为绝对时刻；与设备当前时区无关。
      const fireEpochMs: number = dayEpoch * 86400000 +
        DailyCourseNotificationSettings.normalizeMinutes(reminderMinutes) * 60000 - SHANGHAI_OFFSET_MS;
      if (fireEpochMs <= nowEpochMs) { continue; }
      const courses: Course[] = ScheduleLogic.effectiveCoursesOn(day, schedule);
      if (courses.length === 0) { continue; }
      const entries: string[] = [];
      for (const course of courses) {
        const location: string = course.room.length === 0 ? '' : ' @ ' + course.room;
        const kind: string = course.eventKind === 'exam' ? (english ? 'Exam · ' : '考试 · ') : '';
        const time: string = course.eventKind === 'exam' && !ScheduleLogic.hasTime(course) ?
          (english ? 'Time pending' : '时间待定') : course.timeRange;
        entries.push(kind + time + ' ' + course.name + location);
      }
      const date: string = StrictDates.formatDateParts(day);
      const includesExams: boolean = courses.some((course: Course) => course.eventKind === 'exam');
      requests.push(new DailyCourseNotificationRequest(
        DailyCourseNotificationPlanner.identifierPrefix + date, fireEpochMs,
        includesExams ? (english ? 'Today\'s Schedule · ' + courses.length.toString() :
          '今日安排 · ' + courses.length.toString() + ' 项') :
          (english ? 'Today\'s Courses · ' + courses.length.toString() :
          '今日课程 · ' + courses.length.toString() + ' 门'), entries.join(english ? '; ' : '；')));
    }
    return requests;
  }

  static scheduleDays(schedule: ScheduleSnapshot, nowEpochMs: number, scanDayLimit?: number): DateParts[] {
    const termStart: DateParts | null = StrictDates.parseDateString(schedule.termStartDate);
    if (termStart === null) {
      return [];
    }
    let lastCourseWeek: number = -1;
    for (const course of schedule.courses) {
      for (const week of course.weekNumbers) {
        if (week > 0 && week > lastCourseWeek) {
          lastCourseWeek = week;
        }
      }
    }
    const lastExamDay: DateParts | null = ScheduleLogic.latestExamDay(schedule);
    if (lastCourseWeek < 0 && lastExamDay === null) {
      return [];
    }

    // “今天”由传入的 now 推导（上海时区），保证测试与运行时使用同一时刻。
    const startOfToday: DateParts = StrictDates.partsFromEpochDay(
      Math.floor((nowEpochMs + 8 * 3600 * 1000) / 86400000));
    const boundedLastWeek: number = Math.min(lastCourseWeek, DailyCourseNotificationPlanner.maximumScheduleWeek);
    let termLastDay: DateParts = StrictDates.addDays(termStart, boundedLastWeek * 7 - 1);
    if (lastExamDay !== null && StrictDates.formatDateParts(lastExamDay) >
      StrictDates.formatDateParts(termLastDay)) { termLastDay = lastExamDay; }
    const todayEpochDay: number = StrictDates.epochDay(startOfToday.year, startOfToday.month, startOfToday.day);
    const remainingTermDays: number =
      StrictDates.epochDay(termLastDay.year, termLastDay.month, termLastDay.day) - todayEpochDay + 1;
    if (remainingTermDays <= 0) {
      return [];
    }

    const requestedScanDays: number = scanDayLimit === undefined ? remainingTermDays : Math.max(0, scanDayLimit);
    const scanDayCount: number = Math.min(
      requestedScanDays, remainingTermDays, DailyCourseNotificationPlanner.maximumScanDayCount);
    const days: DateParts[] = [];
    for (let dayOffset = 0; dayOffset < scanDayCount; dayOffset++) {
      days.push(StrictDates.addDays(startOfToday, dayOffset));
    }
    return days;
  }
}

export class PreClassNotificationPlanner {
  static readonly identifierPrefix: string = 'pre-class.';

  static requests(schedule: ScheduleSnapshot, nowEpochMs: number, leadMinutes: number[] = [10],
    english: boolean = false): DailyCourseNotificationRequest[] {
    const requests: DailyCourseNotificationRequest[] = [];
    const seen: Set<string> = new Set<string>();
    const offsets: number[] = PreClassNotificationSettings.normalized(leadMinutes);
    for (const day of DailyCourseNotificationPlanner.scheduleDays(schedule, nowEpochMs)) {
      const date: string = StrictDates.formatDateParts(day);
      const midnight: number = StrictDates.epochDay(day.year, day.month, day.day) * 86400000 - SHANGHAI_OFFSET_MS;
      for (const course of ScheduleLogic.effectiveCoursesOn(day, schedule)) {
        const start: number | null = ScheduleLogic.startMinute(course);
        if (start === null || !ScheduleLogic.hasTime(course)) { continue; }
        // 同一课程发生日期/开始时刻只产生一组提醒，不按节次重复。
        const occurrence: string = JSON.stringify([
          schedule.termID, date, course.eventKind, course.sourceCourseID || course.id, start.toString()
        ]);
        for (const offset of offsets) {
          const fire: number = midnight + (start - offset) * 60000;
          const identifier: string = PreClassNotificationPlanner.identifierPrefix + occurrence + '.' + offset.toString();
          if (fire <= nowEpochMs || seen.has(identifier)) { continue; }
          seen.add(identifier);
          const kind: string = course.eventKind === 'exam' ? (english ? 'Exam' : '考试') : (english ? 'Class' : '课程');
          const title: string = english ? kind + ' starts in ' + offset.toString() + ' min' :
            kind + '将在 ' + offset.toString() + ' 分钟后开始';
          requests.push(new DailyCourseNotificationRequest(identifier, fire, title,
            course.name + ' · ' + ScheduleLogic.startTime(course) +
            (course.room.length > 0 ? ' @ ' + course.room : '')));
        }
      }
    }
    return requests;
  }
}

// 两类提醒共享系统配额和取消队列；先按真实触发时间合并，再截取最近的30条。
export class CourseReminderPlanner {
  static requests(schedule: ScheduleSnapshot, nowEpochMs: number, dailyEnabled: boolean,
    preClassEnabled: boolean, dailyMinutes: number = DailyCourseNotificationSettings.defaultMinutes,
    leadMinutes: number[] = [10], english: boolean = false): DailyCourseNotificationRequest[] {
    const daily: DailyCourseNotificationRequest[] = dailyEnabled ?
      DailyCourseNotificationPlanner.requests(schedule, nowEpochMs, undefined, english, dailyMinutes) : [];
    const requests: DailyCourseNotificationRequest[] = daily.concat(preClassEnabled ?
      PreClassNotificationPlanner.requests(schedule, nowEpochMs, leadMinutes, english) : []);
    requests.sort((left: DailyCourseNotificationRequest, right: DailyCourseNotificationRequest): number =>
      left.fireEpochMs - right.fireEpochMs || left.identifier.localeCompare(right.identifier));
    return requests.slice(0, DailyCourseNotificationPlanner.maximumPendingRequestCount).map(
      (request: DailyCourseNotificationRequest, index: number): DailyCourseNotificationRequest =>
        new DailyCourseNotificationRequest(request.identifier, request.fireEpochMs, request.title, request.body, index + 1));
  }
}

// 仅跨过已安排提醒的触发时刻才补排；反复进入前台不反复取消/发布。
export class CourseReminderRefill {
  static needed(nextFireEpochMs: number | null, nowEpochMs: number): boolean {
    return nextFireEpochMs !== null && nextFireEpochMs <= nowEpochMs;
  }
}

export interface DailyCourseNotificationScheduling {
  authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization>;

  requestAuthorization(timeoutMs: number): Promise<boolean>;

  replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<number>;

  cancelPending(revision: number): Promise<void>;
}

export interface DailyCourseReminderOperations {
  cancelAll(): Promise<void>;
  publish(request: DailyCourseNotificationRequest): Promise<boolean>;
}

export class DailyCourseReminderLimitError extends Error {}
export class DailyCourseReminderPermissionError extends Error {}

// 发布部分成功时把实际数量交给协调器；不能因一条失败清掉已成功的独立提醒。
export class DailyCourseReminderPartialFailure extends Error {
  readonly published: number;
  constructor(published: number) {
    super('部分课程提醒暂时未能安排');
    this.published = published;
  }
}

// 系统的 cancelAll / publish 是异步操作；串行执行，旧批次不能清除新批次。
export class DailyCourseReminderQueue {
  private revision: number = 0;
  private pending: Promise<number> = Promise.resolve(0);
  private readonly operations: DailyCourseReminderOperations;
  private readonly now: () => number;
  private readonly retryDelay: () => Promise<void>;

  constructor(operations: DailyCourseReminderOperations, now: () => number = () => Date.now(),
    retryDelay: () => Promise<void> = () => new Promise<void>((resolve) => { setTimeout(resolve, 500); })) {
    this.operations = operations;
    this.now = now;
    this.retryDelay = retryDelay;
  }

  replace(requests: DailyCourseNotificationRequest[], revision: number): Promise<number> {
    if (revision < this.revision) {
      return Promise.resolve(0);
    }
    this.revision = revision;
    const batch: DailyCourseNotificationRequest[] = requests.slice(
      0, DailyCourseNotificationPlanner.maximumPendingRequestCount).map(
      (request: DailyCourseNotificationRequest, index: number): DailyCourseNotificationRequest =>
        new DailyCourseNotificationRequest(request.identifier, request.fireEpochMs, request.title, request.body, index + 1));
    const work: Promise<number> = this.pending.catch(() => 0).then(async (): Promise<number> => {
      if (revision !== this.revision) {
        return 0;
      }
      await this.operations.cancelAll();
      let published: number = 0;
      let remaining: DailyCourseNotificationRequest[] = batch;
      // 每条最多三次；先完成其余独立请求，再只重试明确返回失败的请求。
      // 已成功/已过期的请求绝不重新发布，重试期间也不再次取消整批。
      for (let attempt = 0; attempt < 3 && remaining.length > 0; attempt++) {
        if (attempt > 0) { await this.retryDelay(); }
        const failed: DailyCourseNotificationRequest[] = [];
        for (const request of remaining) {
          if (revision !== this.revision) { return 0; }
          if (request.fireEpochMs <= this.now()) { continue; }
          try {
            if (await this.operations.publish(request)) { published++; }
          } catch (error) {
            if (error instanceof DailyCourseReminderPermissionError) { throw error; }
            if (error instanceof DailyCourseReminderLimitError) { return published; }
            failed.push(request);
          }
        }
        remaining = failed;
      }
      if (revision !== this.revision) { return 0; }
      if (remaining.length > 0) { throw new DailyCourseReminderPartialFailure(published); }
      return published;
    });
    this.pending = work;
    return work;
  }
}

export enum DailyCourseNotificationReconcileOutcome {
  disabled = 0,
  permissionDenied = 1,
  waitingForSchedule = 2,
  scheduled = 3
}

export class DailyCourseNotificationReconcileResult {
  readonly outcome: DailyCourseNotificationReconcileOutcome;
  readonly scheduledCount: number;
  readonly nextFireEpochMs: number | null;
  readonly partiallyScheduled: boolean;

  constructor(outcome: DailyCourseNotificationReconcileOutcome, scheduledCount: number,
    nextFireEpochMs: number | null = null, partiallyScheduled: boolean = false) {
    this.outcome = outcome;
    this.scheduledCount = scheduledCount;
    this.nextFireEpochMs = nextFireEpochMs;
    this.partiallyScheduled = partiallyScheduled;
  }
}

export class DailyCourseNotificationCoordinator {
  private readonly scheduler: DailyCourseNotificationScheduling;
  private readonly authorizationTimeoutMs: number;
  private readonly english: boolean;

  constructor(scheduler: DailyCourseNotificationScheduling, authorizationTimeoutMs: number = 8000,
    english: boolean = false) {
    this.scheduler = scheduler;
    this.authorizationTimeoutMs = authorizationTimeoutMs;
    this.english = english;
  }

  async reconcile(
    enabled: boolean, requestPermissionIfNeeded: boolean, hasCredentials: boolean,
    schedule: ScheduleSnapshot | null, revision: number,
    reminderMinutes: number = DailyCourseNotificationSettings.defaultMinutes,
    preClassEnabled: boolean = false, leadMinutes: number[] = [10]
  ): Promise<DailyCourseNotificationReconcileResult> {
    if (!enabled && !preClassEnabled) {
      await this.scheduler.cancelPending(revision);
      return new DailyCourseNotificationReconcileResult(
        DailyCourseNotificationReconcileOutcome.disabled, 0);
    }
    const status: DailyCourseNotificationAuthorization =
      await this.scheduler.authorizationStatus(this.authorizationTimeoutMs);
    let authorized: boolean = false;
    if (status === DailyCourseNotificationAuthorization.authorized) {
      authorized = true;
    } else if (requestPermissionIfNeeded) {
      // 鸿蒙无 notDetermined 状态：未开启且允许请求时调用系统授权流程，
      // 已拒绝的用户不会被重复打扰（系统不再弹窗）。
      authorized = await this.scheduler.requestAuthorization(this.authorizationTimeoutMs);
    }
    if (!authorized) {
      await this.scheduler.cancelPending(revision);
      return new DailyCourseNotificationReconcileResult(
        DailyCourseNotificationReconcileOutcome.permissionDenied, 0);
    }
    if (!hasCredentials || schedule === null) {
      await this.scheduler.cancelPending(revision);
      return new DailyCourseNotificationReconcileResult(
        DailyCourseNotificationReconcileOutcome.waitingForSchedule, 0);
    }
    const requests: DailyCourseNotificationRequest[] =
      CourseReminderPlanner.requests(schedule, Date.now(), enabled, preClassEnabled, reminderMinutes, leadMinutes, this.english);
    const nextFire: number | null = requests.length > 0 ? requests[0].fireEpochMs : null;
    try {
      const published: number = await this.scheduler.replacePending(requests, revision);
      return new DailyCourseNotificationReconcileResult(
        DailyCourseNotificationReconcileOutcome.scheduled, published, nextFire);
    } catch (error) {
      if (error instanceof DailyCourseReminderPartialFailure) {
        return new DailyCourseNotificationReconcileResult(
          DailyCourseNotificationReconcileOutcome.scheduled, error.published, nextFire, true);
      }
      if (error instanceof DailyCourseReminderPermissionError) {
        await this.scheduler.cancelPending(revision);
        return new DailyCourseNotificationReconcileResult(
          DailyCourseNotificationReconcileOutcome.permissionDenied, 0);
      }
      throw error as Error;
    }
  }
}
