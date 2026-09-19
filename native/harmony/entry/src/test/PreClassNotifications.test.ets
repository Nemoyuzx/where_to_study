// 合成课表和内存存储；不访问真实账户、设备通知或网络。
import { describe, it, expect } from '@ohos/hypium';
import { Course, ScheduleSnapshot, ClassroomsCache, HolidaysSnapshot } from '../main/ets/common/Models';
import { ExamArrangement, ExamSchedule } from '../main/ets/common/AcademicModels';
import { StrictDates, DateParts, SHANGHAI_OFFSET_MS } from '../main/ets/common/StrictDates';
import { CourseRemovalLogic, CourseRemovalRecord } from '../main/ets/common/CourseRemoval';
import { AppLanguage, AppLocalization } from '../main/ets/common/AppLocalization';
import { AppModel } from '../main/ets/model/AppModel';
import { AppRuntimeMode } from '../main/ets/model/AppRuntimeMode';
import { PreferencesStore } from '../main/ets/store/PreferencesStore';
import { Credentials, CredentialStoring } from '../main/ets/store/CredentialStore';
import { ScheduleStoring } from '../main/ets/store/ScheduleStore';
import { ClassroomStoring } from '../main/ets/store/ClassroomStore';
import { HolidayStoring } from '../main/ets/store/HolidayStore';
import { CourseRemovalStoring } from '../main/ets/store/CourseRemovalStore';
import { ScheduleFetching } from '../main/ets/net/SjdScheduleClient';
import { HolidayFetching } from '../main/ets/net/HolidayClient';
import { HarmonyReminderSchedulerRequest } from '../main/ets/notify/DailyCourseNotifications';
import {
  PreClassNotificationSettings, PreClassNotificationPlanner, CourseReminderPlanner, CourseReminderRefill,
  DailyCourseNotificationSettings, DailyCourseNotificationRequest, DailyCourseNotificationAuthorization,
  DailyCourseNotificationScheduling, DailyCourseReminderOperations, DailyCourseReminderQueue,
  DailyCourseNotificationCoordinator, DailyCourseReminderPermissionError
} from '../main/ets/notify/DailyCoursePlanning';

class ReminderGate {
  private release: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.release = resolve; });
  finish(): void { this.release(); }
}

class ReminderPreferences extends PreferencesStore {
  booleans: Map<string, boolean> = new Map<string, boolean>();
  strings: Map<string, string> = new Map<string, string>();
  numbers: Map<string, number> = new Map<string, number>();
  arrays: Map<string, number[]> = new Map<string, number[]>();
  writes: number = 0;
  async getBool(key: string, fallback: boolean): Promise<boolean> { return this.booleans.get(key) ?? fallback; }
  async getString(key: string): Promise<string | null> { return this.strings.get(key) ?? null; }
  async getNumber(key: string, fallback: number): Promise<number> { return this.numbers.get(key) ?? fallback; }
  async getNumberArray(key: string): Promise<number[]> { return (this.arrays.get(key) ?? []).slice(); }
  async setBool(key: string, value: boolean): Promise<void> { this.booleans.set(key, value); this.writes++; }
  async setString(key: string, value: string): Promise<void> { this.strings.set(key, value); this.writes++; }
  async setNumber(key: string, value: number): Promise<void> { this.numbers.set(key, value); this.writes++; }
  async setNumberArray(key: string, value: number[]): Promise<void> { this.arrays.set(key, value.slice()); this.writes++; }
  async remove(key: string): Promise<void> {
    this.booleans.delete(key); this.strings.delete(key); this.numbers.delete(key); this.arrays.delete(key);
  }
}

class ReminderOperations implements DailyCourseReminderOperations {
  requests: DailyCourseNotificationRequest[] = [];
  cancels: number = 0;
  publishGate: ReminderGate | null = null;
  readonly publishStarted: ReminderGate = new ReminderGate();
  failCancel: boolean = false;
  failures: Map<string, number> = new Map<string, number>();
  attempts: Map<string, number> = new Map<string, number>();
  permissionFailure: boolean = false;
  cancelledSuccessfulRequests: boolean = false;
  async cancelAll(): Promise<void> {
    this.cancels++;
    if (this.failCancel) { throw new Error('synthetic cancellation failure'); }
    if (this.requests.length > 0) { this.cancelledSuccessfulRequests = true; }
    this.requests = [];
  }
  async publish(request: DailyCourseNotificationRequest): Promise<boolean> {
    this.attempts.set(request.identifier, (this.attempts.get(request.identifier) ?? 0) + 1);
    this.publishStarted.finish();
    if (this.publishGate !== null) { await this.publishGate.promise; }
    if (this.permissionFailure) { throw new DailyCourseReminderPermissionError('synthetic permission denial'); }
    const failures: number = this.failures.get(request.identifier) ?? 0;
    if (failures > 0) {
      this.failures.set(request.identifier, failures - 1);
      throw new Error('synthetic transient publish failure');
    }
    this.requests.push(request);
    return true;
  }
}

class ReminderScheduler implements DailyCourseNotificationScheduling {
  readonly operations: ReminderOperations = new ReminderOperations();
  readonly queue: DailyCourseReminderQueue = new DailyCourseReminderQueue(this.operations, () => Date.now(),
    async (): Promise<void> => {});
  authorization: DailyCourseNotificationAuthorization = DailyCourseNotificationAuthorization.authorized;
  authorizationGate: ReminderGate | null = null;
  prompts: number = 0;
  authorizationFailures: number = 0;
  authorizationReads: number = 0;
  async authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization> {
    this.authorizationReads++;
    if (this.authorizationFailures > 0) {
      this.authorizationFailures--;
      throw new Error('synthetic temporary permission query failure');
    }
    if (this.authorizationGate !== null) { await this.authorizationGate.promise; }
    return this.authorization;
  }
  async requestAuthorization(timeoutMs: number): Promise<boolean> { this.prompts++; return false; }
  async replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<number> {
    return await this.queue.replace(requests, revision);
  }
  async cancelPending(revision: number): Promise<void> { await this.queue.replace([], revision); }
}

class ReminderCredentials implements CredentialStoring {
  value: Credentials | null = new Credentials('synthetic-account', 'fixture-only');
  async load(): Promise<Credentials | null> { return this.value; }
  async save(value: Credentials): Promise<void> { this.value = value; }
  async clear(): Promise<void> { this.value = null; }
}
class ReminderScheduleStore implements ScheduleStoring {
  value: ScheduleSnapshot | null = null;
  async load(): Promise<ScheduleSnapshot | null> { return this.value; }
  async save(value: ScheduleSnapshot): Promise<void> { this.value = value; }
  async clear(): Promise<void> { this.value = null; }
}
class ReminderClassroomStore implements ClassroomStoring {
  async load(): Promise<ClassroomsCache | null> { return null; }
  async save(value: ClassroomsCache): Promise<void> {}
  async clear(): Promise<void> {}
}
class ReminderHolidayStore implements HolidayStoring {
  async load(year: number): Promise<HolidaysSnapshot | null> { return null; }
  async save(value: HolidaysSnapshot): Promise<void> {}
  async clear(): Promise<void> {}
}
class ReminderHolidayClient implements HolidayFetching {
  async fetch(year: number): Promise<HolidaysSnapshot> {
    return new HolidaysSnapshot(year, 'synthetic', StrictDates.formatFetchedAt(Date.now()), []);
  }
}
class ReminderRemovalStore implements CourseRemovalStoring {
  values: CourseRemovalRecord[] = [];
  async load(): Promise<CourseRemovalRecord[]> { return this.values.slice(); }
  async save(values: CourseRemovalRecord[]): Promise<void> { this.values = values.slice(); }
  async clear(): Promise<void> { this.values = []; }
}
class ReminderScheduleClient implements ScheduleFetching {
  value: ScheduleSnapshot = upcomingSchedule();
  gate: ReminderGate | null = null;
  readonly started: ReminderGate = new ReminderGate();
  async fetch(credentials: Credentials, termID: string, termStart: string): Promise<ScheduleSnapshot> {
    this.started.finish();
    if (this.gate !== null) { await this.gate.promise; }
    return this.value;
  }
}

function at(day: DateParts, minute: number = 0): number {
  return StrictDates.epochDay(day.year, day.month, day.day) * 86400000 - SHANGHAI_OFFSET_MS + minute * 60000;
}
function oneCourse(id: string, weekday: number = 1, weeks: number[] = [1, 2]): Course {
  return new Course(id, 'Synthetic Course', 'Teacher', 'Room', '', weeks, [], weekday, 0, 1,
    '1-2节', '08:00-09:35', id);
}
function upcomingSchedule(): ScheduleSnapshot {
  const tomorrow: DateParts = StrictDates.addDays(StrictDates.todayParts(), 1);
  const weekday: number = StrictDates.weekdayMonday1(tomorrow);
  return new ScheduleSnapshot('2026-2027-1', StrictDates.formatDateParts(StrictDates.addDays(tomorrow, 1 - weekday)),
    'synthetic', [oneCourse('upcoming', weekday)]);
}
function reminderModel(scheduler: ReminderScheduler, preferences: ReminderPreferences = new ReminderPreferences(),
  client: ReminderScheduleClient = new ReminderScheduleClient(),
  credentials: ReminderCredentials = new ReminderCredentials()): AppModel {
  const model = new AppModel(AppRuntimeMode.live(), credentials, new ReminderScheduleStore(), client,
    new ReminderClassroomStore(), undefined, new ReminderHolidayStore(), new ReminderHolidayClient(), undefined, scheduler,
    'pre-class-unit-tests', undefined, undefined, preferences, new ReminderRemovalStore());
  model.account = 'synthetic-account';
  model.hasSavedPassword = true;
  model.automaticTermDetection = false;
  model.schedule = client.value;
  model.termID = client.value.termID;
  model.termStartDate = client.value.termStartDate;
  return model;
}
async function settle(): Promise<void> {
  // 所有桩都只等待 Promise，不用真实计时/网络；排空有界的模型/偏好串行链。
  for (let i = 0; i < 80; i++) { await Promise.resolve(); }
}

export default function preClassNotificationsTest() {
  describe('PreClassNotificationsTest', () => {
    it('settings_default_validation_and_corrupt_storage_fallback', 0, () => {
      expect(PreClassNotificationSettings.normalized([]).join(',')).assertEqual('10');
      for (const values of [[0], [-1], [1441], [1.5], [Number.NaN], [Number.POSITIVE_INFINITY],
        [10, 10], [1, 2, 3, 4, 5, 6]]) {
        expect(PreClassNotificationSettings.valid(values)).assertFalse();
        expect(PreClassNotificationSettings.normalized(values).join(',')).assertEqual('10');
      }
      expect(PreClassNotificationSettings.normalized([1440, 60, 10, 5, 1]).length).assertEqual(5);
      for (const drafts of [[''], ['1.5'], ['-1'], ['1e2'], ['10', '10']]) {
        expect(PreClassNotificationSettings.parseDrafts(drafts) === null).assertTrue();
      }
      expect(PreClassNotificationSettings.parseDrafts(['10', '5'])?.join(',')).assertEqual('10,5');
    });

    it('default_ten_custom_five_and_two_offsets_use_one_true_occurrence', 0, () => {
      const day = new DateParts(2026, 3, 2);
      const course = oneCourse('one', 1, [1]);
      const schedule = new ScheduleSnapshot('term', '2026-03-02', '', [course, course]);
      const defaults = PreClassNotificationPlanner.requests(schedule, at(day));
      expect(defaults.length).assertEqual(1);
      expect(defaults[0].fireEpochMs).assertEqual(at(day, 470));
      const custom = PreClassNotificationPlanner.requests(schedule, at(day), [5]);
      expect(custom[0].fireEpochMs).assertEqual(at(day, 475));
      const both = CourseReminderPlanner.requests(schedule, at(day), false, true, 450, [5, 10]);
      expect(both.length).assertEqual(2);
      expect(both[0].fireEpochMs).assertEqual(at(day, 470));
      expect(both[1].fireEpochMs).assertEqual(at(day, 475));
      expect(both[0].identifier !== both[1].identifier).assertTrue();
      expect(HarmonyReminderSchedulerRequest.calendar(both[0]).notificationId !==
        HarmonyReminderSchedulerRequest.calendar(both[1]).notificationId).assertTrue();
    });

    it('elapsed_boundaries_and_cross_year_lead_keep_beijing_absolute_time', 0, () => {
      const day = new DateParts(2027, 1, 1);
      const termStart = StrictDates.addDays(day, 1 - StrictDates.weekdayMonday1(day));
      const schedule = new ScheduleSnapshot('term', StrictDates.formatDateParts(termStart), '',
        [oneCourse('newyear', StrictDates.weekdayMonday1(day), [1])]);
      const yesterday = StrictDates.addDays(day, -1);
      const requests = PreClassNotificationPlanner.requests(schedule, at(yesterday), [1440]);
      expect(requests.length).assertEqual(1);
      expect(requests[0].fireEpochMs).assertEqual(at(yesterday, 480));
      const local = HarmonyReminderSchedulerRequest.calendar(requests[0]).dateTime;
      expect(new Date(local.year, local.month - 1, local.day, local.hour, local.minute, local.second ?? 0).getTime())
        .assertEqual(at(yesterday, 480));
      expect(PreClassNotificationPlanner.requests(schedule, at(yesterday, 480), [1440]).length).assertEqual(0);
      expect(PreClassNotificationPlanner.requests(schedule, at(day, 476), [10, 5]).length).assertEqual(0);
    });

    it('timed_exams_override_overlapping_course_and_unknown_times_are_skipped', 0, () => {
      const day = new DateParts(2026, 3, 2);
      const schedule = new ScheduleSnapshot('term', '2026-03-02', '', [oneCourse('ordinary', 1, [1])],
        new ExamSchedule('term', '', '', 'fresh', '', [
          new ExamArrangement('exam', 'Synthetic Exam', '2026-03-02', '08:10', '09:00', 'Exam Room', '', ''),
          new ExamArrangement('unknown', 'Pending Exam', '2026-03-02', '', '', '', '', '')
        ]));
      const requests = PreClassNotificationPlanner.requests(schedule, at(day), [10, 5], true);
      expect(requests.length).assertEqual(2);
      expect(requests[0].title).assertEqual('Exam starts in 10 min');
      expect(requests[0].body).assertEqual('Synthetic Exam · 08:10 @ Exam Room');
      expect(requests[0].fireEpochMs).assertEqual(at(day, 480));
    });

    it('combined_capacity_is_earliest_first_and_daily_summary_is_preserved', 0, () => {
      const courses: Course[] = [];
      const weeks: number[] = [];
      for (let week = 1; week <= 20; week++) { weeks.push(week); }
      for (let weekday = 1; weekday <= 7; weekday++) { courses.push(oneCourse('day-' + weekday, weekday, weeks)); }
      const schedule = new ScheduleSnapshot('term', '2026-03-02', '', courses);
      const now = at(new DateParts(2026, 3, 2));
      const requests = CourseReminderPlanner.requests(schedule, now, true, true, 450, [10, 5]);
      expect(requests.length).assertEqual(30);
      expect(requests[0].identifier).assertEqual('daily-course-summary.2026-03-02');
      expect(new Set<number>(requests.map((request: DailyCourseNotificationRequest) => request.notificationId)).size)
        .assertEqual(30);
      for (let index = 1; index < requests.length; index++) {
        expect(requests[index].fireEpochMs >= requests[index - 1].fireEpochMs).assertTrue();
      }
      expect(CourseReminderPlanner.requests(schedule, now, true, false).length).assertEqual(30);
      expect(CourseReminderPlanner.requests(schedule, now, false, false).length).assertEqual(0);
    });

    it('course_deletion_refresh_and_restore_change_only_effective_occurrences', 0, () => {
      const course = oneCourse('one');
      const raw = new ScheduleSnapshot('term', '2026-03-02', '', [course]);
      const day = new DateParts(2026, 3, 2);
      const removal = CourseRemovalLogic.create('synthetic', raw, course, day, false);
      const filtered = CourseRemovalLogic.apply(raw, 'synthetic', [removal]);
      expect(PreClassNotificationPlanner.requests(raw, at(day), [10, 5]).length).assertEqual(4);
      const remaining = PreClassNotificationPlanner.requests(filtered, at(day), [10, 5]);
      expect(remaining.length).assertEqual(2);
      expect(remaining.every((request: DailyCourseNotificationRequest) => request.identifier.includes('2026-03-09')))
        .assertTrue();
      const refreshed = CourseRemovalLogic.apply(new ScheduleSnapshot('term', '2026-03-02', '', [course]),
        'synthetic', [removal]);
      expect(PreClassNotificationPlanner.requests(refreshed, at(day)).length).assertEqual(1);
      expect(PreClassNotificationPlanner.requests(CourseRemovalLogic.apply(raw, 'synthetic', []), at(day)).length)
        .assertEqual(2);
    });

    it('model_offsets_persist_and_invalid_edits_do_not_change_or_request_permission', 0, async () => {
      const scheduler = new ReminderScheduler();
      const preferences = new ReminderPreferences();
      const model = reminderModel(scheduler, preferences);
      expect(model.preClassNotificationsEnabled).assertFalse();
      expect(model.preClassNotificationLeadMinutes.join(',')).assertEqual('10');
      expect(model.setPreClassNotificationLeadMinutes([10, 5])).assertTrue();
      expect(model.setPreClassNotificationLeadMinutes([5, 5])).assertFalse();
      await settle();
      expect(model.preClassNotificationLeadMinutes.join(',')).assertEqual('10,5');
      expect(PreClassNotificationSettings.normalized(await preferences.getNumberArray(
        PreClassNotificationSettings.minutesKey)).join(',')).assertEqual('10,5');
      expect(scheduler.prompts).assertEqual(0);
      expect(scheduler.operations.requests.length).assertEqual(0);
    });

    it('switching_one_feature_off_preserves_other_and_both_off_clears', 0, async () => {
      const scheduler = new ReminderScheduler();
      const model = reminderModel(scheduler);
      model.setDailyCourseNotificationsEnabled(true);
      model.setPreClassNotificationsEnabled(true);
      await settle();
      expect(scheduler.operations.requests.some((request: DailyCourseNotificationRequest) =>
        request.identifier.startsWith('daily-course-summary.'))).assertTrue();
      expect(scheduler.operations.requests.some((request: DailyCourseNotificationRequest) =>
        request.identifier.startsWith('pre-class.'))).assertTrue();
      model.setDailyCourseNotificationsEnabled(false);
      await settle();
      expect(scheduler.operations.requests.length > 0).assertTrue();
      expect(scheduler.operations.requests.every((request: DailyCourseNotificationRequest) =>
        request.identifier.startsWith('pre-class.'))).assertTrue();
      model.setDailyCourseNotificationsEnabled(true);
      model.setPreClassNotificationsEnabled(false);
      await settle();
      expect(scheduler.operations.requests.every((request: DailyCourseNotificationRequest) =>
        request.identifier.startsWith('daily-course-summary.'))).assertTrue();
      model.setDailyCourseNotificationsEnabled(false);
      await settle();
      expect(scheduler.operations.requests.length).assertEqual(0);
    });

    it('cold_launch_restores_offsets_and_independent_switches_without_permission_prompt', 0, async () => {
      const preferences = new ReminderPreferences();
      for (const key of ['automaticTermDetection', 'weatherEnabled', 'almanacEnabled',
        'competitionDeadlinesEnabled', 'conferenceDeadlinesEnabled', 'schoolContestNoticesEnabled',
        'summerCampDeadlinesEnabled', 'hackathonDeadlinesEnabled', 'customDeadlinesEnabled']) {
        preferences.booleans.set(key, false);
      }
      preferences.booleans.set(DailyCourseNotificationSettings.enabledKey, true);
      preferences.booleans.set(PreClassNotificationSettings.enabledKey, true);
      preferences.arrays.set(PreClassNotificationSettings.minutesKey, [10, 5]);
      preferences.numbers.set(DailyCourseNotificationSettings.minutesKey, 555);
      const credentials = new ReminderCredentials();
      credentials.value = null;
      const scheduler = new ReminderScheduler();
      const model = reminderModel(scheduler, preferences, new ReminderScheduleClient(), credentials);
      await model.launch();
      await settle();
      expect(model.preClassNotificationLeadMinutes.join(',')).assertEqual('10,5');
      expect(model.preClassNotificationsEnabled).assertTrue();
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
      expect(model.dailyCourseNotificationMinutes).assertEqual(555);
      expect(scheduler.prompts).assertEqual(0);
      expect(scheduler.operations.requests.length).assertEqual(0);
      preferences.arrays.set(PreClassNotificationSettings.minutesKey, [10, 10]);
      const restored = reminderModel(new ReminderScheduler(), preferences, new ReminderScheduleClient(), credentials);
      await restored.launch();
      await settle();
      expect(restored.preClassNotificationLeadMinutes.join(',')).assertEqual('10');
      expect(restored.dailyCourseNotificationMinutes).assertEqual(555);
    });

    it('offset_edit_and_disable_win_over_delayed_permission_callback', 0, async () => {
      const scheduler = new ReminderScheduler();
      const gate = new ReminderGate();
      scheduler.authorizationGate = gate;
      const model = reminderModel(scheduler);
      model.setPreClassNotificationsEnabled(true);
      model.setPreClassNotificationLeadMinutes([10, 5]);
      model.setPreClassNotificationsEnabled(false);
      gate.finish();
      await settle();
      expect(model.preClassNotificationsEnabled).assertFalse();
      expect(scheduler.operations.requests.length).assertEqual(0);
    });

    it('mixed_batch_replacement_wins_over_in_flight_publish_and_cancellation_failure_stops_publish', 0, async () => {
      const operations = new ReminderOperations();
      const gate = new ReminderGate();
      operations.publishGate = gate;
      const queue = new DailyCourseReminderQueue(operations, () => 0);
      const old = queue.replace([new DailyCourseNotificationRequest('daily-old', 100, '', ''),
        new DailyCourseNotificationRequest('pre-old', 200, '', '')], 1);
      await operations.publishStarted.promise;
      const newer = queue.replace([new DailyCourseNotificationRequest('pre-new', 300, '', '')], 2);
      gate.finish();
      await old; await newer;
      expect(operations.requests.map((request: DailyCourseNotificationRequest) => request.identifier).join(','))
        .assertEqual('pre-new');
      operations.failCancel = true;
      let failed: boolean = false;
      try { await queue.replace([new DailyCourseNotificationRequest('must-not-publish', 400, '', '')], 3); }
      catch (e) { failed = true; }
      expect(failed).assertTrue();
      expect(operations.requests.length).assertEqual(1);
    });

    it('permission_revoked_in_foreground_cancels_both_without_new_prompt', 0, async () => {
      const scheduler = new ReminderScheduler();
      const model = reminderModel(scheduler);
      model.setDailyCourseNotificationsEnabled(true);
      model.setPreClassNotificationsEnabled(true);
      await settle();
      const count = scheduler.operations.cancels;
      model.refreshDailyCourseNotificationAuthorization();
      await settle();
      expect(scheduler.operations.cancels).assertEqual(count);
      scheduler.authorization = DailyCourseNotificationAuthorization.denied;
      model.refreshDailyCourseNotificationAuthorization();
      await settle();
      expect(model.preClassNotificationsEnabled).assertFalse();
      expect(model.dailyCourseNotificationsEnabled).assertFalse();
      expect(scheduler.operations.requests.length).assertEqual(0);
      expect(scheduler.prompts).assertEqual(0);
    });

    it('failed_publish_retries_only_failed_request_and_keeps_daily_and_later_preclass', 0, async () => {
      const operations = new ReminderOperations();
      operations.failures.set('pre-fails-twice', 2);
      const queue = new DailyCourseReminderQueue(operations, () => 0, async (): Promise<void> => {});
      expect(await queue.replace([
        new DailyCourseNotificationRequest('daily-success', 100, '', ''),
        new DailyCourseNotificationRequest('pre-fails-twice', 200, '', ''),
        new DailyCourseNotificationRequest('pre-later', 300, '', '')
      ], 1)).assertEqual(3);
      expect(operations.cancels).assertEqual(1);
      expect(operations.cancelledSuccessfulRequests).assertFalse();
      expect(operations.attempts.get('daily-success')).assertEqual(1);
      expect(operations.attempts.get('pre-later')).assertEqual(1);
      expect(operations.attempts.get('pre-fails-twice')).assertEqual(3);
      expect(new Set<string>(operations.requests.map((request: DailyCourseNotificationRequest) => request.identifier)).size)
        .assertEqual(3);
    });

    it('exhausted_publish_failure_keeps_user_switches_and_partial_success', 0, async () => {
      const scheduler = new ReminderScheduler();
      const preferences = new ReminderPreferences();
      const model = reminderModel(scheduler, preferences);
      const all = CourseReminderPlanner.requests(model.schedule!, Date.now(), true, true);
      const failed = all.find((request: DailyCourseNotificationRequest) => request.identifier.startsWith('pre-class.'))!;
      scheduler.operations.failures.set(failed.identifier, 100);
      model.dailyCourseNotificationsEnabled = true;
      model.setPreClassNotificationsEnabled(true);
      await settle();
      expect(scheduler.operations.requests.length).assertEqual(all.length - 1);
      expect(scheduler.operations.requests.some((request: DailyCourseNotificationRequest) =>
        request.identifier.startsWith('daily-course-summary.'))).assertTrue();
      expect(scheduler.operations.requests.some((request: DailyCourseNotificationRequest) =>
        request.identifier.startsWith('pre-class.'))).assertTrue();
      expect(scheduler.operations.attempts.get(failed.identifier)).assertEqual(3);
      expect(scheduler.operations.cancelledSuccessfulRequests).assertFalse();
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
      expect(model.preClassNotificationsEnabled).assertTrue();
      expect(preferences.booleans.get(DailyCourseNotificationSettings.enabledKey)).assertTrue();
      expect(preferences.booleans.get(PreClassNotificationSettings.enabledKey)).assertTrue();
      expect(model.dailyCourseNotificationStatusMessage.includes('部分提醒暂时未能安排')).assertTrue();
    });

    it('cancel_during_publish_retry_invalidates_retry_without_replaying_success', 0, async () => {
      const operations = new ReminderOperations();
      const retry = new ReminderGate();
      operations.failures.set('pre', 10);
      const queue = new DailyCourseReminderQueue(operations, () => 0, () => retry.promise);
      const publishing = queue.replace([new DailyCourseNotificationRequest('daily', 100, '', ''),
        new DailyCourseNotificationRequest('pre', 200, '', '')], 1);
      await settle();
      const cancel = queue.replace([], 2);
      retry.finish();
      await publishing; await cancel;
      expect(operations.requests.length).assertEqual(0);
      expect(operations.attempts.get('daily')).assertEqual(1);
      expect(operations.attempts.get('pre')).assertEqual(1);
    });

    it('temporary_permission_query_error_keeps_switches_and_recovers_without_prompt', 0, async () => {
      const scheduler = new ReminderScheduler();
      scheduler.authorizationFailures = 1;
      const preferences = new ReminderPreferences();
      const model = reminderModel(scheduler, preferences);
      model.dailyCourseNotificationsEnabled = true;
      model.setPreClassNotificationsEnabled(true);
      await settle();
      expect(model.preClassNotificationsEnabled).assertTrue();
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
      expect(preferences.booleans.get(PreClassNotificationSettings.enabledKey)).assertTrue();
      await new Promise<void>((resolve) => { setTimeout(resolve, 1100); });
      await settle();
      expect(scheduler.operations.requests.length > 0).assertTrue();
      expect(scheduler.authorizationReads).assertEqual(2);
      expect(scheduler.prompts).assertEqual(0);
      expect(model.preClassNotificationsEnabled).assertTrue();
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
    });

    it('temporary_permission_failures_are_bounded_and_foreground_respects_cooldown', 0, async () => {
      const scheduler = new ReminderScheduler();
      scheduler.authorizationFailures = 100;
      const model = reminderModel(scheduler);
      model.setPreClassNotificationsEnabled(true);
      await new Promise<void>((resolve) => { setTimeout(resolve, 2300); });
      await settle();
      expect(scheduler.authorizationReads).assertEqual(3);
      model.refreshDailyCourseNotificationAuthorization();
      await settle();
      expect(scheduler.authorizationReads).assertEqual(3);
      expect(model.preClassNotificationsEnabled).assertTrue();
      model.setPreClassNotificationsEnabled(false);
      await settle();
    });

    it('explicit_native_permission_denial_cancels_requests_and_switches', 0, async () => {
      const scheduler = new ReminderScheduler();
      scheduler.operations.permissionFailure = true;
      const model = reminderModel(scheduler);
      model.dailyCourseNotificationsEnabled = true;
      model.setPreClassNotificationsEnabled(true);
      await settle();
      expect(model.dailyCourseNotificationsEnabled).assertFalse();
      expect(model.preClassNotificationsEnabled).assertFalse();
      expect(scheduler.operations.requests.length).assertEqual(0);
      expect(scheduler.operations.attempts.size).assertEqual(1);
      expect(scheduler.authorizationReads).assertEqual(1);
    });

    it('refill_requires_a_consumed_fire_time_not_every_foreground_visit', 0, () => {
      expect(CourseReminderRefill.needed(null, 100)).assertFalse();
      expect(CourseReminderRefill.needed(101, 100)).assertFalse();
      expect(CourseReminderRefill.needed(100, 100)).assertTrue();
      expect(CourseReminderRefill.needed(99, 100)).assertTrue();
    });

    it('missing_credentials_cancel_combined_reminders', 0, async () => {
      const scheduler = new ReminderScheduler();
      const coordinator = new DailyCourseNotificationCoordinator(scheduler);
      await coordinator.reconcile(true, false, true, upcomingSchedule(), 1, 450, true, [10, 5]);
      expect(scheduler.operations.requests.length > 0).assertTrue();
      await coordinator.reconcile(true, false, false, upcomingSchedule(), 2, 450, true, [10, 5]);
      expect(scheduler.operations.requests.length).assertEqual(0);
    });

    it('refresh_delete_and_clear_invalidate_pending_schedule_and_notification_work', 0, async () => {
      const scheduler = new ReminderScheduler();
      const client = new ReminderScheduleClient();
      const preferences = new ReminderPreferences();
      const model = reminderModel(scheduler, preferences, client);
      expect(await model.saveSettings()).assertTrue();
      model.setPreClassNotificationsEnabled(true);
      await model.refreshSchedule();
      await settle();
      const tomorrow = StrictDates.addDays(StrictDates.todayParts(), 1);
      expect(await model.removeCourse(client.value.courses[0], tomorrow, true,
        client.value.termID, 'synthetic-account')).assertTrue();
      await settle();
      expect(scheduler.operations.requests.length).assertEqual(0);
      const record = model.courseRemovals[0];
      expect(await model.restoreCourse(record)).assertTrue();
      await settle();
      expect(scheduler.operations.requests.length > 0).assertTrue();
      const gate = new ReminderGate();
      client.gate = gate;
      await model.refreshSchedule();
      await settle();
      // 无设备 AppContext 的主题/卡片清理可抛错，但凭据/课表/提醒清理在此前已完成。
      await model.clearLocalData().catch(() => {});
      gate.finish();
      await settle();
      expect(model.schedule === null).assertTrue();
      expect(model.preClassNotificationsEnabled).assertFalse();
      expect(model.preClassNotificationLeadMinutes.join(',')).assertEqual('10');
      expect(scheduler.operations.requests.length).assertEqual(0);
      expect(preferences.arrays.has(PreClassNotificationSettings.minutesKey)).assertFalse();
    });

    it('logout_blocks_delayed_authorization_and_keeps_both_preferences_for_next_account', 0, async () => {
      const scheduler = new ReminderScheduler();
      const gate = new ReminderGate();
      scheduler.authorizationGate = gate;
      const model = reminderModel(scheduler);
      model.setDailyCourseNotificationsEnabled(true);
      model.setPreClassNotificationsEnabled(true);
      model.account = '';
      model.password = '';
      await model.saveSettings();
      gate.finish();
      await settle();
      expect(model.schedule === null).assertTrue();
      expect(scheduler.operations.requests.length).assertEqual(0);
      expect(model.preClassNotificationsEnabled).assertTrue();
      expect(model.dailyCourseNotificationsEnabled).assertTrue();
    });

    it('reminder_ui_strings_have_english_copy', 0, () => {
      for (const text of ['课前提醒', '提前分钟', '提醒次数', '保存提醒',
        '请输入 1–5 个不重复的整数，每个为 1–1440 分钟。', '已安排 3 条课程提醒']) {
        expect(AppLocalization.text(text, AppLanguage.english, 'en-US') !== text).assertTrue();
      }
    });
  });
}
