// 每日课程摘要规划与协调（与 iOS DailyCourseNotificationTests 对齐的关键断言）。
import { describe, it, expect } from '@ohos/hypium';
import { Course, ScheduleSnapshot } from '../main/ets/common/Models';
import { StrictDates, DateParts } from '../main/ets/common/StrictDates';
import {
  DailyCourseNotificationAuthorization, DailyCourseNotificationCoordinator,
  DailyCourseNotificationPlanner, DailyCourseNotificationReconcileOutcome,
  DailyCourseNotificationRequest, DailyCourseNotificationScheduling,
  DailyCourseNotificationSettings, DailyCourseReminderOperations, DailyCourseReminderQueue,
  DailyCourseReminderLimitError
} from '../main/ets/notify/DailyCoursePlanning';
import { HarmonyReminderSchedulerRequest } from '../main/ets/notify/DailyCourseNotifications';
import { AppModel } from '../main/ets/model/AppModel';
import { AppRuntimeMode } from '../main/ets/model/AppRuntimeMode';
import { FileScheduleStore } from '../main/ets/store/ScheduleStore';
import { FileClassroomStore } from '../main/ets/store/ClassroomStore';
import { FileHolidayStore } from '../main/ets/store/HolidayStore';
import { PreferencesStore } from '../main/ets/store/PreferencesStore';

class RetimingPreferences extends PreferencesStore {
  minutes: number = 450;
  enabled: boolean = true;
  async setNumber(key: string, value: number): Promise<void> { this.minutes = value; }
  async setBool(key: string, value: boolean): Promise<void> { this.enabled = value; }
}

class RecordingReminderOperations implements DailyCourseReminderOperations {
  requests: DailyCourseNotificationRequest[] = [];
  async cancelAll(): Promise<void> { this.requests = []; }
  async publish(request: DailyCourseNotificationRequest): Promise<boolean> { this.requests.push(request); return true; }
}

class SlowAuthorizationScheduler implements DailyCourseNotificationScheduling {
  readonly operations: RecordingReminderOperations = new RecordingReminderOperations();
  readonly events: string[] = [];
  readonly cancelled: Promise<void>;
  readonly published: Promise<void>;
  private readonly queue: DailyCourseReminderQueue = new DailyCourseReminderQueue(this.operations);
  private readonly authorization: Promise<DailyCourseNotificationAuthorization>;
  private releaseAuthorization: (value: DailyCourseNotificationAuthorization) => void = () => {};
  private didCancel: () => void = () => {};
  private didPublish: () => void = () => {};

  constructor() {
    this.authorization = new Promise<DailyCourseNotificationAuthorization>((resolve) => {
      this.releaseAuthorization = resolve;
    });
    this.cancelled = new Promise<void>((resolve) => { this.didCancel = resolve; });
    this.published = new Promise<void>((resolve) => { this.didPublish = resolve; });
  }

  authorize(): void { this.releaseAuthorization(DailyCourseNotificationAuthorization.authorized); }
  async authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization> {
    this.events.push('authorization');
    return await this.authorization;
  }
  async requestAuthorization(timeoutMs: number): Promise<boolean> {
    this.events.push('permissionPrompt');
    return false;
  }
  async cancelPending(revision: number): Promise<void> {
    this.events.push('cancel');
    await this.queue.replace([], revision);
    this.didCancel();
  }
  async replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<number> {
    this.events.push('replace');
    const count: number = await this.queue.replace(requests, revision);
    this.didPublish();
    return count;
  }
}

class BlockingReminderOperations implements DailyCourseReminderOperations {
  requests: DailyCourseNotificationRequest[] = [];
  started: Promise<void>;
  private unblock: () => void = () => {};
  private didStart: () => void = () => {};
  private hold: Promise<void>;
  private first: boolean = true;

  constructor() {
    this.started = new Promise<void>((resolve) => { this.didStart = resolve; });
    this.hold = new Promise<void>((resolve) => { this.unblock = resolve; });
  }

  release(): void { this.unblock(); }
  async cancelAll(): Promise<void> { this.requests = []; }
  async publish(request: DailyCourseNotificationRequest): Promise<boolean> {
    if (this.first) {
      this.first = false;
      this.didStart();
      await this.hold;
    }
    this.requests.push(request);
    return true;
  }
}

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

  async replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<number> {
    this.replaced = requests;
    return requests.length;
  }

  async cancelPending(revision: number): Promise<void> {
    this.cancelled = true;
  }
}

class BoundaryReminderOperations extends RecordingReminderOperations {
  now: number = 100;
  cancelled: Promise<void>;
  private didCancel: () => void = () => {};
  private releaseCancel: () => void = () => {};
  private gate: Promise<void>;
  constructor() {
    super();
    this.cancelled = new Promise<void>((resolve) => { this.didCancel = resolve; });
    this.gate = new Promise<void>((resolve) => { this.releaseCancel = resolve; });
  }
  async cancelAll(): Promise<void> {
    this.didCancel();
    await this.gate;
    await super.cancelAll();
  }
  resume(): void { this.releaseCancel(); }
  async publish(request: DailyCourseNotificationRequest): Promise<boolean> {
    if (request.identifier === 'expired-in-native') { return false; }
    if (request.identifier === 'limit') { throw new DailyCourseReminderLimitError('limit'); }
    return await super.publish(request);
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
    it('slow_cancel_skips_requests_at_or_before_publish_time_and_counts_only_success', 0, async () => {
      const operations = new BoundaryReminderOperations();
      const queue = new DailyCourseReminderQueue(operations, () => operations.now);
      const work = queue.replace([
        new DailyCourseNotificationRequest('elapsed', 150, '', ''),
        new DailyCourseNotificationRequest('boundary', 200, '', ''),
        new DailyCourseNotificationRequest('expired-in-native', 250, '', ''),
        new DailyCourseNotificationRequest('future', 300, '', '')
      ], 1);
      await operations.cancelled;
      operations.now = 200;
      operations.resume();
      expect(await work).assertEqual(1);
      expect(operations.requests.length).assertEqual(1);
      expect(operations.requests[0].identifier).assertEqual('future');
    });

    it('quota_limit_keeps_successful_reminders_and_reports_actual_count', 0, async () => {
      const operations = new BoundaryReminderOperations();
      operations.resume();
      const queue = new DailyCourseReminderQueue(operations, () => 0);
      const count = await queue.replace([
        new DailyCourseNotificationRequest('first', 100, '', ''),
        new DailyCourseNotificationRequest('limit', 200, '', ''),
        new DailyCourseNotificationRequest('not-published', 300, '', '')
      ], 1);
      expect(count).assertEqual(1);
      expect(operations.requests.length).assertEqual(1);
    });

    it('model_rejects_invalid_time_edits_without_changing_current_value_or_scheduling', 0, () => {
      const scheduler = new SlowAuthorizationScheduler();
      const preferences = new RetimingPreferences();
      preferences.minutes = 555;
      const model = new AppModel(AppRuntimeMode.live(), undefined, new FileScheduleStore('unused-schedule'),
        undefined, new FileClassroomStore('unused-classrooms'), undefined, new FileHolidayStore('unused-holidays'),
        undefined, undefined, scheduler, 'daily-course-retiming-unit-tests', undefined, undefined, preferences);
      model.dailyCourseNotificationMinutes = 555;
      model.dailyCourseNotificationsEnabled = true;
      for (const value of [-1, 1440, 555.5, Number.NaN, Number.POSITIVE_INFINITY]) {
        model.setDailyCourseNotificationMinutes(value);
      }
      expect(model.dailyCourseNotificationMinutes).assertEqual(555);
      expect(preferences.minutes).assertEqual(555);
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
      expect(scheduler.events.length).assertEqual(0);
    });

    it('model_retiming_cancels_old_pending_before_slow_authorization_then_publishes_new_time', 0, async () => {
      const tomorrow: DateParts = StrictDates.addDays(StrictDates.todayParts(), 1);
      const weekday: number = StrictDates.weekdayMonday1(tomorrow);
      const termStart: DateParts = StrictDates.addDays(tomorrow, 1 - weekday);
      const scheduler = new SlowAuthorizationScheduler();
      scheduler.operations.requests = [new DailyCourseNotificationRequest('old-0730', 450 * 60000, '', '')];
      const preferences = new RetimingPreferences();
      // 不执行 launch，文件存储不参与此用例；显式路径避免依赖设备 AppContext。
      const model = new AppModel(AppRuntimeMode.live(), undefined, new FileScheduleStore('unused-schedule'),
        undefined, new FileClassroomStore('unused-classrooms'), undefined, new FileHolidayStore('unused-holidays'),
        undefined, undefined, scheduler, 'daily-course-retiming-unit-tests', undefined, undefined, preferences);
      model.dailyCourseNotificationsEnabled = true;
      model.hasSavedPassword = true;
      model.schedule = new ScheduleSnapshot('retime', StrictDates.formatDateParts(termStart), 'cached', [
        new Course('nextday', '测试课程', '', '教一', '1', [1], [], weekday, 0, 1, '1-2节', '08:00-09:35')
      ]);
      model.setDailyCourseNotificationMinutes(555);
      expect(scheduler.events[0]).assertEqual('cancel');
      expect(scheduler.events[1]).assertEqual('authorization');
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
      await scheduler.cancelled;
      // 权限 Promise 仍未完成，但真实调度队列已移除旧的07:30请求。
      expect(scheduler.operations.requests.length).assertEqual(0);
      expect(scheduler.events.includes('replace')).assertFalse();
      scheduler.authorize();
      await scheduler.published;
      expect(scheduler.operations.requests.length).assertEqual(1);
      const shifted = new Date(scheduler.operations.requests[0].fireEpochMs + 8 * 3600000);
      expect(shifted.getUTCHours()).assertEqual(9);
      expect(shifted.getUTCMinutes()).assertEqual(15);
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
      expect(scheduler.events.includes('permissionPrompt')).assertFalse();
      expect(preferences.minutes).assertEqual(555);
    });
    it('minutes_validate_persisted_values_without_clamping_or_rounding', 0, () => {
      for (const value of [-1, 1440, 90.5, Number.NaN, Number.POSITIVE_INFINITY]) {
        expect(DailyCourseNotificationSettings.normalizeMinutes(value)).assertEqual(450);
      }
      expect(DailyCourseNotificationSettings.normalizeMinutes(0)).assertEqual(0);
      expect(DailyCourseNotificationSettings.normalizeMinutes(1439)).assertEqual(1439);
      expect(DailyCourseNotificationSettings.timeText(0)).assertEqual('00:00');
      expect(DailyCourseNotificationSettings.timeText(1439)).assertEqual('23:59');
      expect(DailyCourseNotificationSettings.timeText(Number.NaN)).assertEqual('07:30');
    });

    it('custom_time_skips_elapsed_today_and_replans_a_later_time', 0, () => {
      const midnight: number = Date.UTC(2026, 2, 1, 16);
      const now: number = midnight + 12 * 3600000;
      const morning = DailyCourseNotificationPlanner.requests(demoSchedule(), now, undefined, false, 450);
      const evening = DailyCourseNotificationPlanner.requests(demoSchedule(), now, undefined, false, 1439);
      expect(morning[0].identifier).assertEqual('daily-course-summary.2026-03-09');
      expect(evening[0].identifier).assertEqual('daily-course-summary.2026-03-02');
      expect(evening[0].fireEpochMs).assertEqual(midnight + 1439 * 60000);
      const atFire = DailyCourseNotificationPlanner.requests(demoSchedule(), evening[0].fireEpochMs,
        undefined, false, 1439);
      expect(atFire[0].identifier).assertEqual('daily-course-summary.2026-03-09');
    });

    it('midnight_request_crosses_year_and_uses_selected_instant_in_system_request', 0, () => {
      const schedule = new ScheduleSnapshot('year', '2026-12-28', '2026-12-28T00:00:00+08:00',
        [new Course('newyear', '元旦课程', '', '教一', '1', [1], [], 5, 0, 1, '1-2节', '08:00-09:35')]);
      const midnight: number = Date.UTC(2026, 11, 31, 16);
      const requests = DailyCourseNotificationPlanner.requests(schedule, midnight - 1,
        undefined, false, 0);
      expect(requests.length).assertEqual(1);
      expect(requests[0].identifier).assertEqual('daily-course-summary.2027-01-01');
      expect(requests[0].fireEpochMs).assertEqual(midnight);
      const nativeRequest = HarmonyReminderSchedulerRequest.calendar(requests[0]);
      const dt = nativeRequest.dateTime;
      expect(new Date(dt.year, dt.month - 1, dt.day, dt.hour, dt.minute, dt.second ?? 0).getTime())
        .assertEqual(midnight);
      expect(DailyCourseNotificationPlanner.requests(schedule, midnight, undefined, false, 0).length)
        .assertEqual(0);
    });

    it('latest_time_wins_when_previous_system_publish_is_in_flight', 0, async () => {
      const operations = new BlockingReminderOperations();
      const queue = new DailyCourseReminderQueue(operations, () => 0);
      const old = new DailyCourseNotificationRequest('old', 450 * 60000, '', '');
      const updated = new DailyCourseNotificationRequest('new', 900 * 60000, '', '');
      const first = queue.replace([old, old], 1);
      await operations.started;
      const second = queue.replace([updated], 2);
      operations.release();
      await first;
      await second;
      await queue.replace([], 1);
      expect(operations.requests.length).assertEqual(1);
      expect(operations.requests[0].identifier).assertEqual('new');
      expect(operations.requests[0].fireEpochMs).assertEqual(900 * 60000);
    });

    it('disable_clears_an_in_flight_old_publish_and_blocks_stale_replacement', 0, async () => {
      const operations = new BlockingReminderOperations();
      const queue = new DailyCourseReminderQueue(operations, () => 0);
      const request = new DailyCourseNotificationRequest('old', 1, '', '');
      const first = queue.replace([request], 1);
      await operations.started;
      const cancellation = queue.replace([], 3);
      const stale = queue.replace([request], 2);
      operations.release();
      await first;
      await cancellation;
      await stale;
      expect(operations.requests.length).assertEqual(0);
    });
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

    it('planner_localizes_static_notification_copy_only', 0, () => {
      const schedule: ScheduleSnapshot = demoSchedule();
      const now: number = StrictDates.epochDay(2026, 3, 2) * 86400000 - 8 * 3600 * 1000;
      const requests: DailyCourseNotificationRequest[] =
        DailyCourseNotificationPlanner.requests(schedule, now, undefined, true);
      expect(requests[0].title).assertEqual('Today\'s Courses · 1');
      expect(requests[0].body.includes('早课')).assertTrue();
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
      const result = await coordinator.reconcile(true, false, true, schedule, 1, 1439);
      expect(result.outcome).assertEqual(DailyCourseNotificationReconcileOutcome.scheduled);
      expect(result.scheduledCount).assertEqual(2);
      expect(scheduler.replaced.length).assertEqual(2);
      const shifted = new Date(scheduler.replaced[0].fireEpochMs + 8 * 3600000);
      expect(shifted.getUTCHours()).assertEqual(23);
      expect(shifted.getUTCMinutes()).assertEqual(59);
    });
  });
}
