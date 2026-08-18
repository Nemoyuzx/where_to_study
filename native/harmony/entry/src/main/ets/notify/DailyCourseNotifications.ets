// 每日课程摘要的鸿蒙调度器（reminderAgentManager 日历提醒）。
// 纯逻辑见 DailyCoursePlanning.ets。
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StrictDates, DateParts } from '../common/StrictDates';
import { AppContext } from '../store/AppContext';
import {
  DailyCourseNotificationAuthorization, DailyCourseNotificationPlanner,
  DailyCourseNotificationRequest, DailyCourseNotificationScheduling
} from './DailyCoursePlanning';

// 提醒代理超限（1700002：The number of reminders exceeds the limit）。
const REMINDER_LIMIT_EXCEEDED: number = 1700002;

export class HarmonyReminderScheduler implements DailyCourseNotificationScheduling {
  private currentRevision: number = 0;

  constructor() {
  }

  async authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization> {
    const enabled: boolean = await HarmonyReminderScheduler.withTimeout(
      timeoutMs, notificationManager.isNotificationEnabled());
    return enabled ? DailyCourseNotificationAuthorization.authorized :
      DailyCourseNotificationAuthorization.denied;
  }

  async requestAuthorization(timeoutMs: number): Promise<boolean> {
    const request: Promise<boolean> = (async (): Promise<boolean> => {
      await notificationManager.requestEnableNotification(AppContext.get());
      return await notificationManager.isNotificationEnabled();
    })();
    return await HarmonyReminderScheduler.withTimeout(timeoutMs, request);
  }

  async replacePending(
    requests: DailyCourseNotificationRequest[], revision: number
  ): Promise<void> {
    const batch: DailyCourseNotificationRequest[] = requests.slice(
      0, DailyCourseNotificationPlanner.maximumPendingRequestCount);
    if (!this.prepareRevision(revision)) {
      return;
    }
    // 先清空本应用全部提醒（含历史遗留），再发布新提醒。
    await HarmonyReminderScheduler.cancelAllQuietly();

    for (const request of batch) {
      if (!this.isCurrent(revision)) {
        await HarmonyReminderScheduler.cancelAllQuietly();
        return;
      }
      try {
        await this.publish(request);
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        if (err.code === REMINDER_LIMIT_EXCEEDED) {
          // 达到系统上限：保留已安排的提醒，不再继续。
          break;
        }
        throw new Error('课程摘要安排失败：' + err.message);
      }
    }
  }

  async cancelPending(revision: number): Promise<void> {
    if (!this.prepareRevision(revision)) {
      return;
    }
    await HarmonyReminderScheduler.cancelAllQuietly();
  }

  private prepareRevision(revision: number): boolean {
    if (revision < this.currentRevision) {
      return false;
    }
    this.currentRevision = revision;
    return true;
  }

  private isCurrent(revision: number): boolean {
    return revision === this.currentRevision;
  }

  private async publish(request: DailyCourseNotificationRequest): Promise<void> {
    const parts: DateParts | null = StrictDates.parseDateString(
      request.identifier.substring(DailyCourseNotificationPlanner.identifierPrefix.length));
    if (parts === null) {
      throw new Error('课程摘要安排失败：提醒日期不正确。');
    }
    const reminder: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: parts.year,
        month: parts.month,
        day: parts.day,
        hour: 7,
        minute: 30,
        second: 0
      },
      title: request.title,
      content: request.body,
      expiredContent: request.body,
      tapDismissed: true
    };
    await reminderAgentManager.publishReminder(reminder);
  }

  private static async cancelAllQuietly(): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (e) {
      // 无提醒或代理不可用时忽略；下次替换时再次清理。
    }
  }

  private static withTimeout<T>(timeoutMs: number, promise: Promise<T>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason?: Error) => void) => {
      let settled: boolean = false;
      const timer: number = setTimeout(() => {
        if (!settled) {
          settled = true;
          reject(new Error('通知权限状态读取超时，请在系统设置中确认通知权限。'));
        }
      }, timeoutMs);
      promise.then((value: T) => {
        if (settled) {
          // 超时后底层操作仍可能成功（BUG-051 修复：记录迟到结果便于对账）。
          hilog.warn(0x0000, 'DailyCourseNotifications',
            '提醒代理操作在超时后完成：%{public}s', JSON.stringify(value));
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(value);
      }).catch((error: Error) => {
        if (settled) {
          hilog.warn(0x0000, 'DailyCourseNotifications',
            '提醒代理操作在超时后失败：%{public}s', error.message);
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(error);
      });
    });
  }
}
