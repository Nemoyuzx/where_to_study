// 每日课程摘要规划与协调（与 iOS DailyCourseNotificationTests 对齐的关键断言）。
import { describe, it, expect } from '@ohos/hypium';
import { Course, ScheduleSnapshot } from '../main/ets/common/Models';
import { StrictDates, DateParts } from '../main/ets/common/StrictDates';
import {
  DailyCourseNotificationAuthorization, DailyCourseNotificationCoordinator,
  DailyCourseNotificationPlanner, DailyCourseNotificationReconcileOutcome,
  DailyCourseNotificationRequest, DailyCourseNotificationScheduling
} from '../main/ets/notify/DailyCoursePlanning';

class StubScheduler implements DailyCourseNotificationScheduling {
  authorization: DailyCourseNotificationAuthorization =
    DailyCourseNotificationAuthorization.authorized;
  requestResult: boolean = true;
  replaced: DailyCourseNotificationRequest[] = [];
  cancelled: boolean = false;

  async authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization> {
    return this.authorization;
  }

  async requestAuthorization(timeoutMs: number): Promise<boolean> {
    return this.requestResult;
  }

  async replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<void> {
    this.replaced = requests;
  }

  async cancelPending(revision: number): Promise<void> {
    this.cancelled = true;
  }
}

function demoSchedule(): ScheduleSnapshot {
  const monday: Course = new Course('morning', '早课', '', '教3-335', '1',
    [1], [], 1, 0, 1, '1-2节', '08:00-09:35');
  const monday2: Course = new Course('evening', '晚课', '', '教3-539', '2',
    [2], [], 1, 8, 9, '9-10节', '15:40-17:20');
  return new ScheduleSnapshot('demo', '2026-03-02', '2026-03-02T00:00:00+08:00',
    [monday, monday2]);
}

export default function dailyCoursePlanningTest() {
  describe('DailyCoursePlanningTest', () => {
    it('planner_schedules_only_future_course_days_at_0730', 0, () => {
      const schedule: ScheduleSnapshot = demoSchedule();
      // 2026-03-02 00:00（上海）对应的 UTC 毫秒
      const now: number = StrictDates.epochDay(2026, 3, 2) * 86400000 - 8 * 3600 * 1000;
      const requests: DailyCourseNotificationRequest[] =
        DailyCourseNotificationPlanner.requests(schedule, now);
      expect(requests.length).assertEqual(2);
      expect(requests[0].identifier).assertEqual('daily-course-summary.2026-03-02');
      expect(requests[0].title).assertEqual('今日课程 · 1 门');
      expect(requests[0].body.includes('早课')).assertTrue();
      expect(requests[1].identifier).assertEqual('daily-course-summary.2026-03-09');
      expect(requests[1].body.includes('晚课')).assertTrue();
    });

    it('planner_caps_pending_requests_at_platform_limit', 0, () => {
      const courses: Course[] = [];
      for (let week = 1; week <= 53; week++) {
        courses.push(new Course('w' + week.toString(), '课程' + week.toString(), '',
          '', week.toString(), [week], [], 1, 0, 1, '1-2节', '08:00-09:35'));
      }
      const schedule: ScheduleSnapshot = new ScheduleSnapshot(
        'demo', '2026-03-02', '2026-03-02T00:00:00+08:00', courses);
      const now: number = StrictDates.epochDay(2026, 3, 2) * 86400000 - 8 * 3600 * 1000;
      const requests: DailyCourseNotificationRequest[] =
        DailyCourseNotificationPlanner.requests(schedule, now);
      expect(requests.length).assertEqual(DailyCourseNotificationPlanner.maximumPendingRequestCount);
    });

    it('coordinator_returns_disabled_when_switch_off', 0, async () => {
      const scheduler: StubScheduler = new StubScheduler();
      const coordinator: DailyCourseNotificationCoordinator =
        new DailyCourseNotificationCoordinator(scheduler, 1000);
      const result = await coordinator.reconcile(false, false, false, null, 1);
      expect(result.outcome).assertEqual(DailyCourseNotificationReconcileOutcome.disabled);
      expect(scheduler.cancelled).assertTrue();
    });

    it('coordinator_returns_permission_denied_when_authorization_fails', 0, async () => {
      const scheduler: StubScheduler = new StubScheduler();
      scheduler.authorization = DailyCourseNotificationAuthorization.denied;
      const coordinator: DailyCourseNotificationCoordinator =
        new DailyCourseNotificationCoordinator(scheduler, 1000);
      const result = await coordinator.reconcile(true, false, true, demoSchedule(), 1);
      expect(result.outcome).assertEqual(DailyCourseNotificationReconcileOutcome.permissionDenied);
    });

    it('coordinator_waits_for_schedule_without_credentials', 0, async () => {
      const scheduler: StubScheduler = new StubScheduler();
      const coordinator: DailyCourseNotificationCoordinator =
        new DailyCourseNotificationCoordinator(scheduler, 1000);
      const result = await coordinator.reconcile(true, false, false, null, 1);
      expect(result.outcome).assertEqual(DailyCourseNotificationReconcileOutcome.waitingForSchedule);
    });

    it('coordinator_schedules_requests_when_everything_ready', 0, async () => {
      // 协调器使用真实“现在”，因此课表必须相对明天构造。
      const tomorrow: DateParts = StrictDates.addDays(StrictDates.todayParts(), 1);
      const weekday: number = StrictDates.weekdayMonday1(tomorrow);
      const termStart: DateParts = StrictDates.addDays(tomorrow, -(weekday - 1));
      const schedule: ScheduleSnapshot = new ScheduleSnapshot(
        'demo', StrictDates.formatDateParts(termStart), '2026-01-01T00:00:00+08:00',
        [
          new Course('morning', '早课', '', '教3-335', '1', [1], [], weekday, 0, 1, '1-2节',
            '08:00-09:35'),
          new Course('evening', '晚课', '', '教3-539', '2', [2], [], weekday, 8, 9, '9-10节',
            '15:40-17:20')
        ]);
      const scheduler: StubScheduler = new StubScheduler();
      const coordinator: DailyCourseNotificationCoordinator =
        new DailyCourseNotificationCoordinator(scheduler, 1000);
      const result = await coordinator.reconcile(true, false, true, schedule, 1);
      expect(result.outcome).assertEqual(DailyCourseNotificationReconcileOutcome.scheduled);
      expect(result.scheduledCount).assertEqual(2);
      expect(scheduler.replaced.length).assertEqual(2);
    });
  });
}
