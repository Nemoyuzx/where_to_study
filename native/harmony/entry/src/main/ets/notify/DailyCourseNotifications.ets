// 每日课程摘要的鸿蒙调度器（reminderAgentManager 日历提醒）。
// 纯逻辑见 DailyCoursePlanning.ets。
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../store/AppContext';
import {
  DailyCourseNotificationAuthorization,
  DailyCourseNotificationRequest, DailyCourseNotificationScheduling,
  DailyCourseReminderOperations, DailyCourseReminderQueue
} from './DailyCoursePlanning';

// 提醒代理超限（1700002：The number of reminders exceeds the limit）。
const REMINDER_LIMIT_EXCEEDED: number = 1700002;

export class HarmonyReminderScheduler implements DailyCourseNotificationScheduling {
  private readonly queue: DailyCourseReminderQueue = new DailyCourseReminderQueue(
    new HarmonyReminderOperations());

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
    try {
      await this.queue.replace(requests, revision);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code !== REMINDER_LIMIT_EXCEEDED) {
        throw new Error('课程摘要安排失败：' + err.message);
      }
    }
  }

  async cancelPending(revision: number): Promise<void> {
    await this.queue.replace([], revision);
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

class HarmonyReminderOperations implements DailyCourseReminderOperations {
  async cancelAll(): Promise<void> {
    // 清除失败必须向上报告，避免在旧提醒仍存在时继续叠加新提醒。
    await reminderAgentManager.cancelAllReminders();
  }

  async publish(request: DailyCourseNotificationRequest): Promise<void> {
    await reminderAgentManager.publishReminder(HarmonyReminderSchedulerRequest.calendar(request));
  }
}

export class HarmonyReminderSchedulerRequest {
  static calendar(request: DailyCourseNotificationRequest): reminderAgentManager.ReminderRequestCalendar {
    const date: Date = new Date(request.fireEpochMs);
    if (!Number.isFinite(date.getTime())) {
      throw new Error('课程摘要安排失败：提醒日期不正确。');
    }
    // API 接受 LocalDateTime；将规划好的北京时间绝对时刻转换为设备本地日历字段。
    return {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(),
        hour: date.getHours(), minute: date.getMinutes(), second: date.getSeconds()
      },
      title: request.title, content: request.body, expiredContent: request.body,
      tapDismissed: true
    };
  }
}
