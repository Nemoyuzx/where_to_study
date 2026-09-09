// 每日课程摘要的纯逻辑（请求规划 + 协调器），对应 iOS 端
// DailyCourseNotificationPlanner / DailyCourseNotificationCoordinator。
// 无平台依赖，可被主机侧单元测试引用。

import { Course, ScheduleSnapshot } from '../common/Models';
import { ScheduleLogic } from '../common/ScheduleLogic';
import { StrictDates, DateParts } from '../common/StrictDates';

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

  constructor(identifier: string, fireEpochMs: number, title: string, body: string) {
    this.identifier = identifier;
    this.fireEpochMs = fireEpochMs;
    this.title = title;
    this.body = body;
  }
}

export class DailyCourseNotificationPlanner {
  static readonly identifierPrefix: string = 'daily-course-summary.';
  // 鸿蒙提醒代理全局上限 30 条；与 iOS 的 63 条对应但受平台能力约束。
  static readonly maximumPendingRequestCount: number = 30;
  static readonly maximumScheduleWeek: number = 53;
  static readonly maximumScanDayCount: number = 400;

  static requests(
    schedule: ScheduleSnapshot, nowEpochMs: number, scanDayLimit?: number,
    english: boolean = false,
    reminderMinutes: number = DailyCourseNotificationSettings.defaultMinutes
  ): DailyCourseNotificationRequest[] {
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
    if (lastCourseWeek < 0) {
      return [];
    }

    // “今天”由传入的 now 推导（上海时区），保证测试与运行时使用同一时刻。
    const startOfToday: DateParts = StrictDates.partsFromEpochDay(
      Math.floor((nowEpochMs + 8 * 3600 * 1000) / 86400000));
    const boundedLastWeek: number = Math.min(lastCourseWeek, DailyCourseNotificationPlanner.maximumScheduleWeek);
    const termLastDay: DateParts = StrictDates.addDays(termStart, boundedLastWeek * 7 - 1);
    const todayEpochDay: number = StrictDates.epochDay(startOfToday.year, startOfToday.month, startOfToday.day);
    const remainingTermDays: number =
      StrictDates.epochDay(termLastDay.year, termLastDay.month, termLastDay.day) - todayEpochDay + 1;
    if (remainingTermDays <= 0) {
      return [];
    }

    const requestedScanDays: number = scanDayLimit === undefined ? remainingTermDays : Math.max(0, scanDayLimit);
    const scanDayCount: number = Math.min(
      requestedScanDays, remainingTermDays, DailyCourseNotificationPlanner.maximumScanDayCount);
    const requests: DailyCourseNotificationRequest[] = [];

    for (let dayOffset = 0; dayOffset < scanDayCount; dayOffset++) {
      if (requests.length >= DailyCourseNotificationPlanner.maximumPendingRequestCount) {
        break;
      }
      const day: DateParts = StrictDates.addDays(startOfToday, dayOffset);
      const dayEpoch: number = StrictDates.epochDay(day.year, day.month, day.day);
      // 所选北京时间转换为绝对时刻；与设备当前时区无关。
      const fireEpochMs: number = dayEpoch * 86400000 +
        DailyCourseNotificationSettings.normalizeMinutes(reminderMinutes) * 60000 - 8 * 3600 * 1000;
      if (fireEpochMs <= nowEpochMs) {
        continue;
      }
      const courses: Course[] = ScheduleLogic.coursesOn(day, termStart, schedule.courses);
      if (courses.length === 0) {
        continue;
      }
      const entries: string[] = [];
      for (const course of courses) {
        const location: string = course.room.length === 0 ? '' : ' @ ' + course.room;
        entries.push(course.timeRange + ' ' + course.name + location);
      }
      const date: string = StrictDates.formatDateParts(day);
      requests.push(new DailyCourseNotificationRequest(
        DailyCourseNotificationPlanner.identifierPrefix + date,
        fireEpochMs,
        english ? 'Today\'s Courses · ' + courses.length.toString() :
          '今日课程 · ' + courses.length.toString() + ' 门',
        entries.join(english ? '; ' : '；')
      ));
    }
    return requests;
  }
}

export interface DailyCourseNotificationScheduling {
  authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization>;

  requestAuthorization(timeoutMs: number): Promise<boolean>;

  replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<void>;

  cancelPending(revision: number): Promise<void>;
}

export interface DailyCourseReminderOperations {
  cancelAll(): Promise<void>;
  publish(request: DailyCourseNotificationRequest): Promise<void>;
}

// 系统的 cancelAll / publish 是异步操作；串行执行，旧批次不能清除新批次。
export class DailyCourseReminderQueue {
  private revision: number = 0;
  private pending: Promise<void> = Promise.resolve();
  private readonly operations: DailyCourseReminderOperations;

  constructor(operations: DailyCourseReminderOperations) {
    this.operations = operations;
  }

  replace(requests: DailyCourseNotificationRequest[], revision: number): Promise<void> {
    if (revision < this.revision) {
      return Promise.resolve();
    }
    this.revision = revision;
    const batch: DailyCourseNotificationRequest[] = requests.slice(
      0, DailyCourseNotificationPlanner.maximumPendingRequestCount);
    const work: Promise<void> = this.pending.catch(() => {}).then(async (): Promise<void> => {
      if (revision !== this.revision) {
        return;
      }
      await this.operations.cancelAll();
      for (const request of batch) {
        if (revision !== this.revision) {
          return;
        }
        await this.operations.publish(request);
      }
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

  constructor(outcome: DailyCourseNotificationReconcileOutcome, scheduledCount: number) {
    this.outcome = outcome;
    this.scheduledCount = scheduledCount;
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
    reminderMinutes: number = DailyCourseNotificationSettings.defaultMinutes
  ): Promise<DailyCourseNotificationReconcileResult> {
    if (!enabled) {
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
      DailyCourseNotificationPlanner.requests(schedule, Date.now(), undefined, this.english, reminderMinutes);
    await this.scheduler.replacePending(requests, revision);
    return new DailyCourseNotificationReconcileResult(
      DailyCourseNotificationReconcileOutcome.scheduled, requests.length);
  }
}
