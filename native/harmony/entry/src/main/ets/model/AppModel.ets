// 与 iOS 端 AppModel.swift 对应的应用状态机（ArkTS 版）。
// 状态使用 V2 的 @ObservedV2/@Trace 装饰，由 Index 根组件通过 @Provider 注入。
// 账号密码只进 ASSET 安全存储；课表/空教室/节假日缓存只进沙箱 JSON 文件。
import { AppSection } from '../common/AppSection';
import { Classroom, ClassroomDefaults, ClassroomsCache, Course, HolidayItem,
  HolidaysSnapshot, ScheduleDefaults, ScheduleSnapshot, SlotMetadata } from '../common/Models';
import { ScheduleLogic } from '../common/ScheduleLogic';
import { StrictDates, DateParts } from '../common/StrictDates';
import { Credentials, AssetCredentialStore, CredentialStoring } from '../store/CredentialStore';
import { FileScheduleStore, ScheduleStoring } from '../store/ScheduleStore';
import { FileClassroomStore, ClassroomStoring } from '../store/ClassroomStore';
import { FileHolidayStore, HolidayStoring } from '../store/HolidayStore';
import { PreferencesStore } from '../store/PreferencesStore';
import { ScheduleFetching, SJDScheduleClient } from '../net/SjdScheduleClient';
import { ClassroomFetching, SJDClassroomClient } from '../net/SjdClassroomClient';
import { HolidayFetching, HolidayClient } from '../net/HolidayClient';
import { CampusWeather, WeatherFetching, UAPIWeatherClient } from '../net/DailyInfoClient';
import {
  AlmanacInfo, AssignmentDeadlineItem, CalendarDailyInfoClient, CalendarDailyInfoFetching,
  PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineSnapshot, PublicDeadlineSource
} from '../net/CalendarDailyInfoClient';
import {
  AssignmentDeadlineFetching, UCloudAssignmentClient
} from '../net/UCloudAssignmentClient';
import { HolidayOfflineFallback } from '../net/parsers/HolidaySourceParser';
import { CalendarImporting, HarmonyCalendarImporter } from '../calendar/CalendarImporter';
import { CalendarImportError, CalendarImportLogic, CalendarImportResult } from '../calendar/CalendarImportLogic';
import { HarmonyReminderScheduler } from '../notify/DailyCourseNotifications';
import {
  DailyCourseNotificationCoordinator, DailyCourseNotificationReconcileOutcome,
  DailyCourseNotificationScheduling, DailyCourseNotificationSettings
} from '../notify/DailyCoursePlanning';
import { AppRuntimeMode } from './AppRuntimeMode';
import { SampleData } from './SampleData';
import { WidgetSync } from '../widget/WidgetSync';
import { WidgetCoursePreferences } from '../widget/TodayCourseWidgetData';
import {
  AppLanguage, AppLanguageInfo, AppLocalization
} from '../common/AppLocalization';

export class CredentialSettingsError extends Error {
  constructor(message: string) {
    super(message);
  }

  static accountRequired(): CredentialSettingsError {
    return new CredentialSettingsError('请输入教务账号。');
  }

  static passwordRequiredForChangedAccount(): CredentialSettingsError {
    return new CredentialSettingsError('更换教务账号时必须输入新密码。');
  }

  static accountDataResetFailed(): CredentialSettingsError {
    return new CredentialSettingsError('无法清除原账号的课表与空教室缓存，账号未更改。');
  }

  static calendarImportInProgress(): CredentialSettingsError {
    return new CredentialSettingsError('系统日历正在同步，请完成后再更换账号。');
  }

  static invalidTermStartDate(): CredentialSettingsError {
    return new CredentialSettingsError('第一周周一日期格式不正确，请使用 yyyy-MM-dd。');
  }
}

enum CredentialSaveActionKind {
  preserve = 0,
  replace = 1,
  clear = 2
}

class CredentialSaveAction {
  readonly kind: CredentialSaveActionKind;
  readonly credentials: Credentials | null;

  private constructor(kind: CredentialSaveActionKind, credentials: Credentials | null) {
    this.kind = kind;
    this.credentials = credentials;
  }

  static preserve(): CredentialSaveAction {
    return new CredentialSaveAction(CredentialSaveActionKind.preserve, null);
  }

  static replace(credentials: Credentials): CredentialSaveAction {
    return new CredentialSaveAction(CredentialSaveActionKind.replace, credentials);
  }

  static clear(): CredentialSaveAction {
    return new CredentialSaveAction(CredentialSaveActionKind.clear, null);
  }
}

export class CredentialSettingsLogic {
  static saveAction(
    inputAccount: string, inputPassword: string, storedAccount: string | null,
    hasStoredPassword: boolean
  ): CredentialSaveAction {
    const account: string = CredentialSettingsLogic.normalizedAccount(inputAccount);
    if (account.length === 0) {
      if (inputPassword.length === 0) {
        return CredentialSaveAction.clear();
      }
      throw CredentialSettingsError.accountRequired();
    }
    if (inputPassword.length > 0) {
      return CredentialSaveAction.replace(new Credentials(account, inputPassword));
    }
    if (hasStoredPassword && CredentialSettingsLogic.normalizedAccount(storedAccount ?? '') === account) {
      return CredentialSaveAction.preserve();
    }
    throw CredentialSettingsError.passwordRequiredForChangedAccount();
  }

  static credentialsForRequest(
    inputAccount: string, inputPassword: string, storedCredentials: Credentials | null
  ): Credentials {
    const action: CredentialSaveAction = CredentialSettingsLogic.saveAction(
      inputAccount, inputPassword, storedCredentials?.account ?? null,
      storedCredentials !== null && storedCredentials.password.length > 0);
    if (action.kind === CredentialSaveActionKind.replace && action.credentials !== null) {
      return action.credentials;
    }
    if (action.kind === CredentialSaveActionKind.preserve) {
      if (storedCredentials === null) {
        throw CredentialSettingsError.passwordRequiredForChangedAccount();
      }
      return new Credentials(
        CredentialSettingsLogic.normalizedAccount(inputAccount), storedCredentials.password);
    }
    throw CredentialSettingsError.accountRequired();
  }

  static normalizedAccount(account: string): string {
    return account.trim();
  }
}

class HolidayLoadState {
  private tokensByYear: Map<number, number> = new Map<number, number>();

  begin(year: number): number | null {
    if (this.tokensByYear.has(year)) {
      return null;
    }
    const token: number = Date.now();
    this.tokensByYear.set(year, token);
    return token;
  }

  finish(year: number, token: number): void {
    const current: number | undefined = this.tokensByYear.get(year);
    if (current === undefined || current !== token) {
      return;
    }
    this.tokensByYear.delete(year);
  }

  reset(): void {
    this.tokensByYear.clear();
  }
}

@ObservedV2
export class AppModel {
  @Trace selectedSection: AppSection = AppSection.planner;
  @Trace account: string = '';
  @Trace password: string = '';
  @Trace hasSavedPassword: boolean = false;
  @Trace termID: string = ScheduleDefaults.termID;
  @Trace termStartDate: string = ScheduleDefaults.termStartDate;
  // 自动检测当前学期（对应 Android automaticTermDetectionEnabled）：
  // 开启时获取/刷新课表后用教务返回的学期覆盖本地，关闭时保留手动填写值。
  @Trace automaticTermDetection: boolean = true;
  // 桌面小组件显示偏好（对应 Android widgetShowsLocation/widgetShowsTeacher/widgetCourseLimit）。
  @Trace widgetShowsLocation: boolean = true;
  @Trace widgetShowsTeacher: boolean = true;
  @Trace widgetCourseLimit: number = WidgetCoursePreferences.defaultLimit;
  // 日期详情与生活信息开关：与 Apple/Android/Tauri 默认值保持一致。
  @Trace weatherEnabled: boolean = true;
  @Trace almanacEnabled: boolean = true;
  @Trace competitionDeadlinesEnabled: boolean = true;
  @Trace schoolContestNoticesEnabled: boolean = true;
  @Trace summerCampDeadlinesEnabled: boolean = true;
  @Trace hackathonDeadlinesEnabled: boolean = true;
  @Trace campusID: string = '01';
  @Trace queryCampusID: string = '01';
  @Trace selectedSlots: Set<number> = new Set<number>();
  @Trace selectedBuildings: Set<string> = new Set<string>();
  @Trace usePersonalSchedule: boolean = true;
  @Trace schedule: ScheduleSnapshot | null = null;
  @Trace classroomsCache: ClassroomsCache | null = null;
  @Trace holidaysByYear: Map<number, HolidaysSnapshot> = new Map<number, HolidaysSnapshot>();
  @Trace weatherByCampus: Map<string, CampusWeather> = new Map<string, CampusWeather>();
  @Trace weatherErrors: Map<string, string> = new Map<string, string>();
  @Trace loadingWeatherCampuses: Set<string> = new Set<string>();
  @Trace almanacByDate: Map<string, AlmanacInfo> = new Map<string, AlmanacInfo>();
  @Trace almanacErrors: Map<string, string> = new Map<string, string>();
  @Trace loadingAlmanacDates: Set<string> = new Set<string>();
  @Trace publicDeadlinesByDate: Map<string, PublicDeadlineSnapshot> =
    new Map<string, PublicDeadlineSnapshot>();
  @Trace publicDeadlineErrors: Map<string, string> = new Map<string, string>();
  @Trace loadingPublicDeadlineDates: Set<string> = new Set<string>();
  @Trace assignmentDeadlinesByDate: Map<string, AssignmentDeadlineItem[]> =
    new Map<string, AssignmentDeadlineItem[]>();
  @Trace assignmentUnavailableByDate: Map<string, string> = new Map<string, string>();
  @Trace loadingAssignmentDates: Set<string> = new Set<string>();
  @Trace statusMessage: string = '';
  @Trace classroomStatusMessage: string = '';
  @Trace calendarImportStatusMessage: string = '';
  @Trace isRefreshingSchedule: boolean = false;
  @Trace isRefreshingClassrooms: boolean = false;
  @Trace isImportingCalendar: boolean = false;
  @Trace holidayStatusByYear: Map<number, string> = new Map<number, string>();
  @Trace dailyCourseNotificationsEnabled: boolean = false;
  @Trace dailyCourseNotificationStatusMessage: string = '';
  @Trace languageSettingRawValue: string = AppLanguage.system;
  @Trace systemLanguageID: string = AppLanguageInfo.systemLanguage();
  @Trace runtimeMode: AppRuntimeMode;

  readonly slots: SlotMetadata[] = SlotMetadata.defaults;

  private readonly credentialStore: CredentialStoring;
  private readonly scheduleStore: ScheduleStoring;
  private readonly scheduleClient: ScheduleFetching;
  private readonly classroomStore: ClassroomStoring;
  private readonly classroomClient: ClassroomFetching;
  private readonly holidayStore: HolidayStoring;
  private readonly holidayClient: HolidayFetching;
  private readonly weatherClient: WeatherFetching;
  private readonly calendarDailyInfoClient: CalendarDailyInfoFetching = new CalendarDailyInfoClient();
  private readonly assignmentClient: AssignmentDeadlineFetching;
  private readonly calendarImporter: CalendarImporting;
  private readonly dailyCourseNotificationScheduler: DailyCourseNotificationScheduling;
  private readonly dailyCourseNotificationAuthorizationTimeoutMs: number;
  private readonly statusMessageAutoDismissMs: number;
  private readonly preferences: PreferencesStore;
  private readonly supportsRuntimeModeSwitching: boolean;
  private readonly holidayLoads: HolidayLoadState = new HolidayLoadState();
  private localDataGeneration: number = 0;
  private scheduleRefreshToken: number = 0;
  private classroomRefreshToken: number = 0;
  private calendarImportToken: number = 0;
  private dailyCourseNotificationRevision: number = 0;
  private statusMessageRevision: number = 0;
  private statusMessageDismissTimer: number | null = null;
  private savedCredentialAccount: string | null = null;
  private launched: boolean = false;
  private launchPromise: Promise<void> | null = null;
  private readonly preferencesName: string;
  private classroomRefreshInFlight: boolean = false;
  private weatherRevision: number = 0;
  private calendarDailyInfoRevision: number = 0;
  private calendarMarkerLoadingDates: Set<string> = new Set<string>();
  // 每日课程摘要对账门控（BUG-050 修复）：当日已对账且无变化时不再全量重排提醒。
  private dailyCourseNotificationReconciledDay: string = '';
  private dailyCourseNotificationDirty: boolean = true;

  constructor(
    runtimeMode: AppRuntimeMode = AppRuntimeMode.live(),
    credentialStore: CredentialStoring = new AssetCredentialStore(),
    scheduleStore: ScheduleStoring = new FileScheduleStore(),
    scheduleClient: ScheduleFetching = new SJDScheduleClient(),
    classroomStore: ClassroomStoring = new FileClassroomStore(),
    classroomClient: ClassroomFetching = new SJDClassroomClient(),
    holidayStore: HolidayStoring = new FileHolidayStore(),
    holidayClient: HolidayFetching = new HolidayClient(),
    calendarImporter: CalendarImporting = new HarmonyCalendarImporter(),
    dailyCourseNotificationScheduler: DailyCourseNotificationScheduling = new HarmonyReminderScheduler(),
    preferencesName: string = 'where-to-study',
    weatherClient: WeatherFetching = new UAPIWeatherClient(),
    assignmentClient: AssignmentDeadlineFetching = new UCloudAssignmentClient()
  ) {
    this.runtimeMode = runtimeMode;
    this.supportsRuntimeModeSwitching = !runtimeMode.isSample;
    this.credentialStore = credentialStore;
    this.scheduleStore = scheduleStore;
    this.scheduleClient = scheduleClient;
    this.classroomStore = classroomStore;
    this.classroomClient = classroomClient;
    this.holidayStore = holidayStore;
    this.holidayClient = holidayClient;
    this.weatherClient = weatherClient;
    this.assignmentClient = assignmentClient;
    this.calendarImporter = calendarImporter;
    this.dailyCourseNotificationScheduler = dailyCourseNotificationScheduler;
    this.dailyCourseNotificationAuthorizationTimeoutMs = 8000;
    this.statusMessageAutoDismissMs = 4000;
    this.preferencesName = preferencesName;
    this.preferences = new PreferencesStore(preferencesName);
  }

  // 与 iOS 端 AppModel.init 对应的冷启动引导（RootView.aboutToAppear 调用一次）。
  // iOS 端为同步加载，鸿蒙端存储均为异步，因此集中在 launch() 串行完成。
  async launch(): Promise<void> {
    if (this.launchPromise !== null) {
      return this.launchPromise;
    }
    this.launchPromise = this.performLaunch();
    return this.launchPromise;
  }

  private async performLaunch(): Promise<void> {
    if (this.launched) {
      return;
    }
    this.launched = true;
    // BUG-039 修复：UI 测试偏好域每次启动清空，避免跨测试残留状态。
    await this.prepareForLaunch();
    const savedTermID: string | null = await this.preferences.getString('termID');
    const savedTermStart: string | null = await this.preferences.getString('termStartDate');
    const savedCampusID: string | null = await this.preferences.getString('campusID');
    const savedLanguage: string | null = await this.preferences.getString('appLanguage');
    const notificationsEnabled: boolean = await this.preferences.getBool(
      DailyCourseNotificationSettings.enabledKey, false);
    this.automaticTermDetection = await this.preferences.getBool('automaticTermDetection', true);
    this.widgetShowsLocation = await this.preferences.getBool('widgetShowsLocation', true);
    this.widgetShowsTeacher = await this.preferences.getBool('widgetShowsTeacher', true);
    this.widgetCourseLimit = Math.min(Math.max(
      await this.preferences.getNumber('widgetCourseLimit', WidgetCoursePreferences.defaultLimit),
      1), WidgetCoursePreferences.maximumLimit);
    this.weatherEnabled = await this.preferences.getBool('weatherEnabled', true);
    this.almanacEnabled = await this.preferences.getBool('almanacEnabled', true);
    this.competitionDeadlinesEnabled = await this.preferences.getBool(
      'competitionDeadlinesEnabled', true);
    this.schoolContestNoticesEnabled = await this.preferences.getBool(
      'schoolContestNoticesEnabled', true);
    this.summerCampDeadlinesEnabled = await this.preferences.getBool(
      'summerCampDeadlinesEnabled', true);
    this.hackathonDeadlinesEnabled = await this.preferences.getBool(
      'hackathonDeadlinesEnabled', true);
    this.languageSettingRawValue = AppLanguageInfo.normalize(savedLanguage);
    this.systemLanguageID = AppLanguageInfo.systemLanguage();
    this.termID = savedTermID !== null && savedTermID.length > 0 ? savedTermID : ScheduleDefaults.termID;
    this.termStartDate = savedTermStart !== null && savedTermStart.length > 0 ?
      savedTermStart : ScheduleDefaults.termStartDate;
    this.campusID = savedCampusID !== null && savedCampusID.length > 0 ? savedCampusID : '01';
    this.queryCampusID = this.campusID;
    this.dailyCourseNotificationsEnabled = notificationsEnabled;
    await this.loadCredentials();
    await this.loadSchedule();
    await this.loadClassrooms();
    this.synchronizeSelectedSlots();
    this.ensureHolidays(StrictDates.todayParts().year, false);
    // 冷启动总是对账一次，即使开关已关闭也能移除旧批次。
    this.reconcileDailyCourseNotifications(false);
  }

  private async prepareForLaunch(): Promise<void> {
    if (this.preferencesName.startsWith('ui-tests')) {
      try {
        await this.preferences.clearAll();
      } catch (e) {
        // 清空失败不阻断启动。
      }
    }
  }

  // ---------- 派生状态 ----------

  isSampleMode(): boolean {
    return this.runtimeMode.isSample;
  }

  isReviewDemo(): boolean {
    return this.runtimeMode.isReviewDemo;
  }

  canExitSampleMode(): boolean {
    return this.isSampleMode() && this.supportsRuntimeModeSwitching;
  }

  canEnterReviewDemo(): boolean {
    return this.supportsRuntimeModeSwitching && !this.isSampleMode() && !this.isImportingCalendar;
  }

  canPreserveSavedPassword(): boolean {
    return this.hasSavedPassword &&
      CredentialSettingsLogic.normalizedAccount(this.account) ===
      CredentialSettingsLogic.normalizedAccount(this.savedCredentialAccount ?? '');
  }

  selectedCampusName(): string {
    return this.queryCampusID === '04' ? '沙河' : '西土城';
  }

  languageSetting(): AppLanguage {
    return AppLanguageInfo.normalize(this.languageSettingRawValue);
  }

  resolvedLanguage(): AppLanguage {
    return AppLanguageInfo.resolved(this.languageSetting(), this.systemLanguageID);
  }

  text(source: string): string {
    return AppLocalization.text(source, this.languageSetting(), this.systemLanguageID);
  }

  refreshSystemLanguage(): void {
    const current: string = AppLanguageInfo.systemLanguage();
    if (current !== this.systemLanguageID) {
      this.systemLanguageID = current;
      this.synchronizeWidgetSchedule();
    }
  }

  todayCourses(): Course[] {
    return this.coursesOn(StrictDates.todayParts());
  }

  tomorrowCourses(): Course[] {
    return this.coursesOn(StrictDates.addDays(StrictDates.todayParts(), 1));
  }

  coursesOn(date: DateParts): Course[] {
    if (this.schedule === null) {
      return [];
    }
    const termStart: DateParts | null = StrictDates.parseDateString(this.schedule.termStartDate);
    if (termStart === null) {
      return [];
    }
    return ScheduleLogic.coursesOn(date, termStart, this.schedule.courses);
  }

  weekNumberOn(date: DateParts): number | null {
    if (this.schedule === null) {
      return null;
    }
    const termStart: DateParts | null = StrictDates.parseDateString(this.schedule.termStartDate);
    if (termStart === null) {
      return null;
    }
    return ScheduleLogic.weekNumber(date, termStart);
  }

  personalBusySlots(): Set<number> {
    if (this.schedule === null) {
      return new Set<number>();
    }
    const termStart: DateParts | null = StrictDates.parseDateString(this.schedule.termStartDate);
    if (termStart === null) {
      return new Set<number>();
    }
    return ScheduleLogic.busySlots(StrictDates.todayParts(), termStart, this.schedule.courses);
  }

  campusRooms(): Classroom[] {
    if (this.classroomsCache === null) {
      return [];
    }
    for (const campus of this.classroomsCache.campuses) {
      if (campus.campusID === this.queryCampusID) {
        return campus.rooms;
      }
    }
    return [];
  }

  campusBuildings(): string[] {
    const configured: string[] = ClassroomDefaults.buildings(this.queryCampusID);
    if (configured.length > 0) {
      return configured;
    }
    const seen: Set<string> = new Set<string>();
    for (const room of this.campusRooms()) {
      seen.add(room.building);
    }
    const result: string[] = [];
    for (const building of seen) {
      result.push(building);
    }
    result.sort();
    return result;
  }

  matchingRooms(): Classroom[] {
    if (this.selectedBuildings.size === 0 || this.selectedSlots.size === 0) {
      return [];
    }
    const result: Classroom[] = [];
    for (const room of this.campusRooms()) {
      let allSlotsAvailable: boolean = true;
      for (const slot of this.selectedSlots) {
        if (!room.availableSlots.includes(slot)) {
          allSlotsAvailable = false;
          break;
        }
      }
      if (this.selectedBuildings.has(room.building) && allSlotsAvailable) {
        result.push(room);
      }
    }
    result.sort((lhs: Classroom, rhs: Classroom) => {
      if (lhs.building !== rhs.building) {
        return lhs.building < rhs.building ? -1 : 1;
      }
      return lhs.room < rhs.room ? -1 : (lhs.room > rhs.room ? 1 : 0);
    });
    return result;
  }

  // ---------- 筛选交互 ----------

  toggleSlot(slot: number): void {
    if (this.usePersonalSchedule && this.personalBusySlots().has(slot)) {
      return;
    }
    if (this.selectedSlots.has(slot)) {
      this.selectedSlots.delete(slot);
    } else {
      this.selectedSlots.add(slot);
    }
  }

  setUsePersonalSchedule(enabled: boolean): void {
    this.usePersonalSchedule = enabled;
    const busy: Set<number> = this.personalBusySlots();
    for (const slot of busy) {
      if (enabled) {
        this.selectedSlots.delete(slot);
      } else {
        this.selectedSlots.add(slot);
      }
    }
  }

  selectFreeSlots(): void {
    const all: Set<number> = new Set<number>();
    for (const slot of this.slots) {
      all.add(slot.index);
    }
    if (this.usePersonalSchedule) {
      const busy: Set<number> = this.personalBusySlots();
      for (const slot of busy) {
        all.delete(slot);
      }
    }
    this.selectedSlots = all;
  }

  clearSelectedSlots(): void {
    this.selectedSlots.clear();
  }

  toggleBuilding(building: string): void {
    if (this.selectedBuildings.has(building)) {
      this.selectedBuildings.delete(building);
    } else {
      this.selectedBuildings.add(building);
    }
  }

  selectQueryCampus(id: string): void {
    if (this.queryCampusID === id) {
      return;
    }
    this.queryCampusID = id;
    this.selectedBuildings.clear();
  }

  // ---------- 示例模式 ----------

  enterReviewDemo(): void {
    if (!this.canEnterReviewDemo()) {
      return;
    }
    this.invalidatePendingOperations();
    this.dailyCourseNotificationRevision++;
    this.runtimeMode = AppRuntimeMode.sample(true);

    this.account = '';
    this.password = '';
    this.updateSavedCredentialState(null);
    const sampleSchedule: ScheduleSnapshot = SampleData.schedule();
    this.schedule = sampleSchedule;
    this.synchronizeWidgetSchedule();
    this.classroomsCache = SampleData.classrooms();
    this.termID = sampleSchedule.termID;
    this.termStartDate = sampleSchedule.termStartDate;
    this.campusID = '01';
    this.queryCampusID = '01';
    this.selectedBuildings.clear();
    this.usePersonalSchedule = true;
    this.synchronizeSelectedSlots();
    this.resetWeatherState();
    this.resetCalendarDailyInfoState();
    this.loadWeather(this.queryCampusID);
    this.holidaysByYear.clear();
    this.holidayStatusByYear.clear();
    this.holidayLoads.reset();
    const year: number = StrictDates.todayParts().year;
    const sampleHolidays: HolidaysSnapshot | null = SampleData.holidaysOrNull(year);
    if (sampleHolidays !== null) {
      this.holidaysByYear.set(year, sampleHolidays);
    }
    this.dailyCourseNotificationsEnabled = false;
    this.statusMessage = '正在展示内置示例课表，未连接北邮服务';
    this.classroomStatusMessage = '正在展示内置示例空教室，未连接北邮服务';
    this.calendarImportStatusMessage = '';
    this.dailyCourseNotificationStatusMessage = '';
  }

  exitReviewDemo(): void {
    if (!this.canExitSampleMode()) {
      return;
    }
    this.invalidatePendingOperations();
    this.runtimeMode = AppRuntimeMode.live();
    this.account = '';
    this.password = '';
    this.schedule = null;
    this.classroomsCache = null;
    this.resetWeatherState();
    this.resetCalendarDailyInfoState();
    this.holidaysByYear.clear();
    this.holidayStatusByYear.clear();
    this.holidayLoads.reset();
    this.statusMessage = '';
    this.classroomStatusMessage = '';
    this.calendarImportStatusMessage = '';
    this.dailyCourseNotificationStatusMessage = '';
    this.dailyCourseNotificationDirty = true;
    const work: Promise<void> = this.restorePersistedSettings();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  private async restorePersistedSettings(): Promise<void> {
    try {
      const savedTermID: string | null = await this.preferences.getString('termID');
      const savedTermStart: string | null = await this.preferences.getString('termStartDate');
      const savedCampusID: string | null = await this.preferences.getString('campusID');
      const savedLanguage: string | null = await this.preferences.getString('appLanguage');
      const notificationsEnabled: boolean = await this.preferences.getBool(
        DailyCourseNotificationSettings.enabledKey, false);
      this.automaticTermDetection = await this.preferences.getBool('automaticTermDetection', true);
      this.widgetShowsLocation = await this.preferences.getBool('widgetShowsLocation', true);
      this.widgetShowsTeacher = await this.preferences.getBool('widgetShowsTeacher', true);
      this.widgetCourseLimit = Math.min(Math.max(
        await this.preferences.getNumber('widgetCourseLimit', WidgetCoursePreferences.defaultLimit),
        1), WidgetCoursePreferences.maximumLimit);
      this.weatherEnabled = await this.preferences.getBool('weatherEnabled', true);
      this.almanacEnabled = await this.preferences.getBool('almanacEnabled', true);
      this.competitionDeadlinesEnabled = await this.preferences.getBool(
        'competitionDeadlinesEnabled', true);
      this.schoolContestNoticesEnabled = await this.preferences.getBool(
        'schoolContestNoticesEnabled', true);
      this.summerCampDeadlinesEnabled = await this.preferences.getBool(
        'summerCampDeadlinesEnabled', true);
      this.hackathonDeadlinesEnabled = await this.preferences.getBool(
        'hackathonDeadlinesEnabled', true);
      this.languageSettingRawValue = AppLanguageInfo.normalize(savedLanguage);
      this.systemLanguageID = AppLanguageInfo.systemLanguage();
      this.termID = savedTermID !== null && savedTermID.length > 0 ? savedTermID : ScheduleDefaults.termID;
      this.termStartDate = savedTermStart !== null && savedTermStart.length > 0 ?
        savedTermStart : ScheduleDefaults.termStartDate;
      this.campusID = savedCampusID !== null && savedCampusID.length > 0 ? savedCampusID : '01';
      this.queryCampusID = this.campusID;
      this.dailyCourseNotificationsEnabled = notificationsEnabled;
    } catch (e) {
      // 偏好读取失败时保留默认值（BUG-006 修复）。
    }
    try {
      await this.loadCredentials();
    } catch (e) {
    }
    try {
      await this.loadSchedule();
    } catch (e) {
    }
    try {
      await this.loadClassrooms();
    } catch (e) {
    }
    // 串行完成后再同步节次，避免与 loadSchedule 的写回竞态（BUG-007/009 修复）。
    this.synchronizeSelectedSlots();
    const year: number = StrictDates.todayParts().year;
    this.ensureHolidays(year, false);
    this.loadWeather(this.queryCampusID);
    this.reconcileDailyCourseNotifications(false);
  }

  // ---------- 设置保存 ----------

  async saveSettings(): Promise<boolean> {
    if (this.isSampleMode()) {
      this.statusMessage = '示例模式不会保存账户或设置';
      return false;
    }
    try {
      const normalizedTermID: string = this.termID.trim();
      const normalizedTermStartDate: string = this.termStartDate.trim();
      const nextTermID: string = normalizedTermID.length === 0 ?
        ScheduleDefaults.termID : normalizedTermID;
      const nextTermStartDate: string = normalizedTermStartDate.length === 0 ?
        ScheduleDefaults.termStartDate : normalizedTermStartDate;
      if (StrictDates.parseDateString(nextTermStartDate) === null) {
        throw CredentialSettingsError.invalidTermStartDate();
      }
      const storedCredentials: Credentials | null = await this.credentialStore.load();
      const credentialAction: CredentialSaveAction = CredentialSettingsLogic.saveAction(
        this.account, this.password, storedCredentials?.account ?? null,
        storedCredentials !== null && storedCredentials.password.length > 0);
      let nextCredentialAccount: string | null = null;
      if (credentialAction.kind === CredentialSaveActionKind.preserve) {
        nextCredentialAccount = storedCredentials !== null ? storedCredentials.account : null;
      } else if (credentialAction.kind === CredentialSaveActionKind.replace &&
        credentialAction.credentials !== null) {
        nextCredentialAccount = credentialAction.credentials.account;
      }
      const accountChanged: boolean =
        CredentialSettingsLogic.normalizedAccount(storedCredentials?.account ?? '') !==
        CredentialSettingsLogic.normalizedAccount(nextCredentialAccount ?? '');
      if (accountChanged) {
        if (this.isImportingCalendar) {
          throw CredentialSettingsError.calendarImportInProgress();
        }
        await this.clearAccountScopedData();
      }
      if (credentialAction.kind === CredentialSaveActionKind.preserve) {
        this.updateSavedCredentialState(storedCredentials);
      } else if (credentialAction.kind === CredentialSaveActionKind.replace &&
        credentialAction.credentials !== null) {
        await this.credentialStore.save(credentialAction.credentials);
        this.updateSavedCredentialState(credentialAction.credentials);
      } else {
        await this.credentialStore.clear();
        this.updateSavedCredentialState(null);
      }
      this.account = CredentialSettingsLogic.normalizedAccount(this.account);
      this.password = '';
      this.termID = nextTermID;
      this.termStartDate = nextTermStartDate;
      await this.preferences.setString('campusID', this.campusID);
      await this.preferences.setString('termID', this.termID);
      await this.preferences.setString('termStartDate', this.termStartDate);
      await this.preferences.setBool('automaticTermDetection', this.automaticTermDetection);
      this.statusMessage = '设置已保存';
      return true;
    } catch (e) {
      this.statusMessage = e instanceof Error ? e.message : '设置保存失败。';
      return false;
    }
  }

  // 仅保存学期设置（学期编号/第一周周一/自动检测开关），不涉及账号密码
  // （对应 Android SettingsPage.semesterSurface 的"保存学期设置"按钮）。
  async saveSemesterSettings(): Promise<boolean> {
    if (this.isSampleMode()) {
      this.statusMessage = '示例模式不会保存账户或设置';
      return false;
    }
    const normalizedTermID: string = this.termID.trim();
    const normalizedTermStartDate: string = this.termStartDate.trim();
    const nextTermID: string = normalizedTermID.length === 0 ?
      ScheduleDefaults.termID : normalizedTermID;
    const nextTermStartDate: string = normalizedTermStartDate.length === 0 ?
      ScheduleDefaults.termStartDate : normalizedTermStartDate;
    if (StrictDates.parseDateString(nextTermStartDate) === null) {
      this.statusMessage = CredentialSettingsError.invalidTermStartDate().message;
      return false;
    }
    this.termID = nextTermID;
    this.termStartDate = nextTermStartDate;
    try {
      await this.preferences.setString('termID', this.termID);
      await this.preferences.setString('termStartDate', this.termStartDate);
      await this.preferences.setBool('automaticTermDetection', this.automaticTermDetection);
      this.statusMessage = '学期设置已保存';
      return true;
    } catch (e) {
      this.statusMessage = e instanceof Error ? e.message : '学期设置保存失败。';
      return false;
    }
  }

  // 桌面小组件偏好：设置页即时生效并刷新全部卡片（对应 Android
  // widgetSurface 的 Switch/Spinner 直接写偏好）。
  async setWidgetShowsLocation(value: boolean): Promise<void> {
    this.widgetShowsLocation = value;
    await this.preferences.setBool('widgetShowsLocation', value);
    this.synchronizeWidgetSchedule();
  }

  async setLanguageSetting(value: AppLanguage): Promise<void> {
    this.languageSettingRawValue = value;
    this.systemLanguageID = AppLanguageInfo.systemLanguage();
    await this.preferences.setString('appLanguage', value);
    this.synchronizeWidgetSchedule();
    this.dailyCourseNotificationDirty = true;
    this.reconcileDailyCourseNotifications(false);
  }

  async setWidgetShowsTeacher(value: boolean): Promise<void> {
    this.widgetShowsTeacher = value;
    await this.preferences.setBool('widgetShowsTeacher', value);
    this.synchronizeWidgetSchedule();
  }

  async setWidgetCourseLimit(value: number): Promise<void> {
    const clamped: number = Math.min(Math.max(value, 1), WidgetCoursePreferences.maximumLimit);
    this.widgetCourseLimit = clamped;
    await this.preferences.setNumber('widgetCourseLimit', clamped);
    this.synchronizeWidgetSchedule();
  }

  // 日期详情与生活信息偏好即时保存；关闭后不再发起对应公开请求。
  async setWeatherEnabled(value: boolean): Promise<void> {
    this.weatherEnabled = value;
    await this.preferences.setBool('weatherEnabled', value);
    if (value) {
      this.loadWeather(this.queryCampusID);
    } else {
      this.resetWeatherState();
    }
  }

  async setAlmanacEnabled(value: boolean): Promise<void> {
    this.almanacEnabled = value;
    await this.preferences.setBool('almanacEnabled', value);
  }

  async setCompetitionDeadlinesEnabled(value: boolean): Promise<void> {
    this.competitionDeadlinesEnabled = value;
    await this.preferences.setBool('competitionDeadlinesEnabled', value);
  }

  async setSchoolContestNoticesEnabled(value: boolean): Promise<void> {
    this.schoolContestNoticesEnabled = value;
    await this.preferences.setBool('schoolContestNoticesEnabled', value);
  }

  async setSummerCampDeadlinesEnabled(value: boolean): Promise<void> {
    this.summerCampDeadlinesEnabled = value;
    await this.preferences.setBool('summerCampDeadlinesEnabled', value);
  }

  async setHackathonDeadlinesEnabled(value: boolean): Promise<void> {
    this.hackathonDeadlinesEnabled = value;
    await this.preferences.setBool('hackathonDeadlinesEnabled', value);
  }

  hasEnabledPublicDeadlines(): boolean {
    return this.competitionDeadlinesEnabled || this.schoolContestNoticesEnabled ||
      this.summerCampDeadlinesEnabled ||
      this.hackathonDeadlinesEnabled;
  }

  deadlineItemEnabled(item: PublicDeadlineItem): boolean {
    if (item.source === PublicDeadlineSource.schoolNotice) {
      return this.schoolContestNoticesEnabled;
    }
    const kind: PublicDeadlineKind = item.kind;
    if (kind === PublicDeadlineKind.competition) {
      return this.competitionDeadlinesEnabled;
    }
    if (kind === PublicDeadlineKind.summerCamp) {
      return this.summerCampDeadlinesEnabled;
    }
    return this.hackathonDeadlinesEnabled;
  }

  // ---------- 每日课程摘要 ----------

  setDailyCourseNotificationsEnabled(enabled: boolean): void {
    if (this.isSampleMode()) {
      if (this.isReviewDemo()) {
        this.dailyCourseNotificationsEnabled = enabled;
        this.dailyCourseNotificationStatusMessage = enabled ?
          '示例模式已模拟开启每日课程摘要，未申请通知权限' :
          '示例模式已模拟关闭每日课程摘要';
      } else {
        this.dailyCourseNotificationStatusMessage = '示例模式不会申请通知权限';
      }
      return;
    }
    this.dailyCourseNotificationsEnabled = enabled;
    if (enabled) {
      this.dailyCourseNotificationDirty = true;
      this.dailyCourseNotificationStatusMessage = '正在确认通知权限…';
      this.reconcileDailyCourseNotifications(true);
    } else {
      const work: Promise<void> = this.preferences.setBool(
        DailyCourseNotificationSettings.enabledKey, false);
      work.catch(() => {
        // 偏好写入失败不影响本次关闭（BUG-016 修复）。
      });
      this.dailyCourseNotificationStatusMessage = '每日课程摘要已关闭';
      const cancelWork: Promise<void> = this.cancelDailyCourseNotifications();
      cancelWork.catch(() => {
        // 取消失败由下次对账兜底。
      });
    }
  }

  refreshDailyCourseNotificationAuthorization(): void {
    this.reconcileDailyCourseNotifications(false);
  }

  private reconcileDailyCourseNotifications(requestPermissionIfNeeded: boolean): void {
    if (this.isSampleMode()) {
      this.dailyCourseNotificationsEnabled = false;
      return;
    }
    // 当日已对账且无变化时跳过，避免每次回前台都全量取消并重发提醒（BUG-050 修复）。
    const today: string = StrictDates.formatDateParts(StrictDates.todayParts());
    if (!requestPermissionIfNeeded && !this.dailyCourseNotificationDirty &&
      this.dailyCourseNotificationReconciledDay === today) {
      return;
    }
    this.dailyCourseNotificationDirty = false;
    this.dailyCourseNotificationReconciledDay = today;
    this.dailyCourseNotificationRevision++;
    const revision: number = this.dailyCourseNotificationRevision;
    if (!this.dailyCourseNotificationsEnabled) {
      this.dailyCourseNotificationScheduler.cancelPending(revision);
      return;
    }
    const coordinator: DailyCourseNotificationCoordinator = new DailyCourseNotificationCoordinator(
      this.dailyCourseNotificationScheduler, this.dailyCourseNotificationAuthorizationTimeoutMs,
      this.resolvedLanguage() === AppLanguage.english);
    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const result = await coordinator.reconcile(
          true, requestPermissionIfNeeded, this.hasSavedPassword, this.schedule, revision);
        if (revision !== this.dailyCourseNotificationRevision) {
          return;
        }
        if (result.outcome === DailyCourseNotificationReconcileOutcome.disabled) {
          await this.preferences.setBool(DailyCourseNotificationSettings.enabledKey, false);
        } else if (result.outcome === DailyCourseNotificationReconcileOutcome.permissionDenied) {
          this.dailyCourseNotificationsEnabled = false;
          await this.preferences.setBool(DailyCourseNotificationSettings.enabledKey, false);
          this.dailyCourseNotificationStatusMessage = '通知权限未开启，未安排课程摘要';
        } else if (result.outcome === DailyCourseNotificationReconcileOutcome.waitingForSchedule) {
          await this.preferences.setBool(DailyCourseNotificationSettings.enabledKey, true);
          this.dailyCourseNotificationStatusMessage = '每日课程摘要已开启，获取课表后自动安排';
        } else {
          await this.preferences.setBool(DailyCourseNotificationSettings.enabledKey, true);
          this.dailyCourseNotificationStatusMessage = result.scheduledCount === 0 ?
            '每日课程摘要已开启，当前课表没有待通知课程' :
            '已安排未来 ' + result.scheduledCount.toString() + ' 个有课日的课程摘要';
        }
      } catch (e) {
        if (revision !== this.dailyCourseNotificationRevision) {
          return;
        }
        this.dailyCourseNotificationsEnabled = false;
        await this.preferences.setBool(DailyCourseNotificationSettings.enabledKey, false);
        await this.dailyCourseNotificationScheduler.cancelPending(revision);
        this.dailyCourseNotificationStatusMessage = '课程摘要安排失败：' +
          (e instanceof Error ? e.message : '');
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  private cancelDailyCourseNotifications(): Promise<void> {
    this.dailyCourseNotificationRevision++;
    return this.dailyCourseNotificationScheduler.cancelPending(this.dailyCourseNotificationRevision);
  }

  // ---------- 清除本地数据 ----------

  async clearLocalData(): Promise<void> {
    if (this.isSampleMode()) {
      this.statusMessage = '示例模式不读写真实本地数据';
      return;
    }
    this.invalidatePendingOperations();
    this.dailyCourseNotificationsEnabled = false;
    await this.preferences.remove(DailyCourseNotificationSettings.enabledKey);
    this.dailyCourseNotificationStatusMessage = '';
    // 等待提醒取消完成再清空凭据/课表，避免残留提醒（BUG-060 修复）。
    try {
      await this.cancelDailyCourseNotifications();
    } catch (e) {
      // 取消失败由下次对账兜底。
    }
    const failures: string[] = [];

    try {
      await this.credentialStore.clear();
    } catch (e) {
      failures.push('账户密码');
    }
    this.account = '';
    this.password = '';
    this.updateSavedCredentialState(null);

    try {
      await this.scheduleStore.clear();
      this.schedule = null;
      this.synchronizeWidgetSchedule();
      this.calendarImportStatusMessage = '';
    } catch (e) {
      failures.push('个人课表');
    }

    try {
      await this.classroomStore.clear();
      this.classroomsCache = null;
      this.classroomStatusMessage = '';
    } catch (e) {
      failures.push('空教室缓存');
    }

    try {
      await this.holidayStore.clear();
      this.holidaysByYear.clear();
      this.holidayStatusByYear.clear();
      this.holidayLoads.reset();
    } catch (e) {
      failures.push('节假日缓存');
    }

    this.resetWeatherState();
    this.resetCalendarDailyInfoState();

    await this.preferences.remove('campusID');
    await this.preferences.remove('termID');
    await this.preferences.remove('termStartDate');
    await this.preferences.remove('automaticTermDetection');
    this.automaticTermDetection = true;
    await this.preferences.remove('widgetShowsLocation');
    await this.preferences.remove('widgetShowsTeacher');
    await this.preferences.remove('widgetCourseLimit');
    await this.preferences.remove('weatherEnabled');
    await this.preferences.remove('almanacEnabled');
    await this.preferences.remove('competitionDeadlinesEnabled');
    await this.preferences.remove('schoolContestNoticesEnabled');
    await this.preferences.remove('summerCampDeadlinesEnabled');
    await this.preferences.remove('hackathonDeadlinesEnabled');
    await this.preferences.remove('appLanguage');
    this.widgetShowsLocation = true;
    this.widgetShowsTeacher = true;
    this.widgetCourseLimit = WidgetCoursePreferences.defaultLimit;
    this.weatherEnabled = true;
    this.almanacEnabled = true;
    this.competitionDeadlinesEnabled = true;
    this.schoolContestNoticesEnabled = true;
    this.summerCampDeadlinesEnabled = true;
    this.hackathonDeadlinesEnabled = true;
    this.languageSettingRawValue = AppLanguage.system;
    this.systemLanguageID = AppLanguageInfo.systemLanguage();
    this.campusID = '01';
    this.queryCampusID = '01';
    this.termID = ScheduleDefaults.termID;
    this.termStartDate = ScheduleDefaults.termStartDate;
    this.selectedBuildings.clear();
    this.usePersonalSchedule = true;
    this.synchronizeSelectedSlots();

    this.statusMessage = failures.length === 0 ?
      '本地数据已清除' :
      '以下本地数据未能清除：' + failures.join('、');
  }

  // ---------- 课表刷新 ----------

  async refreshSchedule(): Promise<void> {
    if (this.isSampleMode()) {
      this.statusMessage = '正在展示内置示例课表，未连接北邮服务';
      return;
    }
    if (this.isRefreshingSchedule) {
      return;
    }
    let credentials: Credentials;
    try {
      credentials = await this.credentialsForRequest();
    } catch (e) {
      this.setStatusMessage(e instanceof Error ? e.message : '');
      return;
    }
    this.isRefreshingSchedule = true;
    this.scheduleRefreshToken++;
    const refreshToken: number = this.scheduleRefreshToken;
    this.setStatusMessage('正在获取个人课表…');
    const fallbackTermID: string = this.termID.trim().length === 0 ?
      ScheduleDefaults.termID : this.termID.trim();
    const fallbackTermStart: string = this.termStartDate.trim().length === 0 ?
      ScheduleDefaults.termStartDate : this.termStartDate.trim();
    if (StrictDates.parseDateString(fallbackTermStart) === null) {
      this.isRefreshingSchedule = false;
      this.setStatusMessage(CredentialSettingsError.invalidTermStartDate().message);
      return;
    }
    const generation: number = this.localDataGeneration;

    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const fetched: ScheduleSnapshot = await this.scheduleClient.fetch(
          credentials, fallbackTermID, fallbackTermStart);
        if (generation !== this.localDataGeneration || refreshToken !== this.scheduleRefreshToken) {
          return;
        }
        await this.scheduleStore.save(fetched);
        this.schedule = fetched;
        this.synchronizeWidgetSchedule();
        this.calendarImportStatusMessage = '';
        if (this.automaticTermDetection) {
          // 自动检测开启时用教务返回的学期覆盖本地（对应 Android
          // automaticTermDetectionEnabled）；关闭时保留手动填写值。
          this.termID = fetched.termID;
          this.termStartDate = fetched.termStartDate;
          await this.preferences.setString('termID', this.termID);
          await this.preferences.setString('termStartDate', this.termStartDate);
        }
        this.synchronizeSelectedSlots();
        this.dailyCourseNotificationDirty = true;
        this.reconcileDailyCourseNotifications(false);
        this.setStatusMessage('个人课表已更新，共 ' + fetched.courses.length.toString() + ' 门课程', true);
      } catch (e) {
        if (generation !== this.localDataGeneration || refreshToken !== this.scheduleRefreshToken) {
          return;
        }
        this.setStatusMessage(e instanceof Error ? e.message : '');
      } finally {
        if (refreshToken === this.scheduleRefreshToken) {
          this.isRefreshingSchedule = false;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // ---------- 系统日历导入 ----------

  async importScheduleToCalendar(): Promise<void> {
    if (this.isSampleMode()) {
      if (this.isReviewDemo() && this.schedule !== null) {
        try {
          const count: number = CalendarImportLogic.eventDrafts(this.schedule).length;
          this.calendarImportStatusMessage = '示例模式已模拟同步 ' + count.toString() +
            ' 个课程日期，未写入系统日历';
        } catch (e) {
          this.calendarImportStatusMessage = e instanceof Error ? e.message : '';
        }
      } else {
        this.calendarImportStatusMessage = '示例模式不会访问系统日历';
      }
      return;
    }
    if (this.isImportingCalendar) {
      return;
    }
    if (this.schedule === null) {
      this.calendarImportStatusMessage = CalendarImportError.noSchedule().message;
      return;
    }
    this.isImportingCalendar = true;
    this.calendarImportToken++;
    const importToken: number = this.calendarImportToken;
    this.calendarImportStatusMessage = '正在导入系统日历…';
    const generation: number = this.localDataGeneration;
    const schedule: ScheduleSnapshot = this.schedule;

    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const result: CalendarImportResult = await this.calendarImporter.importSchedule(schedule);
        if (generation !== this.localDataGeneration || importToken !== this.calendarImportToken) {
          return;
        }
        if (result.total() === 0) {
          this.calendarImportStatusMessage = '课表中没有可导入的课程日期';
        } else {
          this.calendarImportStatusMessage = '日历同步完成：新增 ' + result.inserted.toString() +
            '，更新 ' + result.updated.toString() + '，删除 ' + result.deleted.toString() +
            '，已存在 ' + result.unchanged.toString();
        }
      } catch (e) {
        if (generation !== this.localDataGeneration || importToken !== this.calendarImportToken) {
          return;
        }
        this.calendarImportStatusMessage = e instanceof Error ? e.message : '';
      } finally {
        if (importToken === this.calendarImportToken) {
          this.isImportingCalendar = false;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // ---------- 空教室刷新 ----------

  refreshClassroomsIfNeeded(): void {
    if (this.isSampleMode()) {
      return;
    }
    const work: Promise<void> = (async (): Promise<void> => {
      // 等待 launch 完成（凭据/缓存就绪），避免启动竞态误报与重复请求（BUG-003/038 修复）。
      if (this.launchPromise !== null) {
        await this.launchPromise;
      }
      if (this.classroomsCache !== null &&
        this.classroomsCache.targetDate === AppModel.todayString()) {
        return;
      }
      await this.refreshClassrooms(false);
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  async refreshClassrooms(force: boolean = true): Promise<void> {
    if (this.isSampleMode()) {
      this.classroomStatusMessage = '正在展示内置示例空教室，未连接北邮服务';
      return;
    }
    if (this.classroomRefreshInFlight) {
      return;
    }
    if (!force && this.classroomsCache !== null &&
      this.classroomsCache.targetDate === AppModel.todayString()) {
      return;
    }
    // 同步置位，防止并发入口在凭据读取期间重复发起请求（BUG-038 修复）。
    this.classroomRefreshInFlight = true;
    this.classroomRefreshToken++;
    const refreshToken: number = this.classroomRefreshToken;
    this.isRefreshingClassrooms = true;
    this.classroomStatusMessage = '正在获取当天空教室…';
    const targetDate: string = AppModel.todayString();
    const generation: number = this.localDataGeneration;

    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const credentials: Credentials = await this.credentialsForRequest();
        if (generation !== this.localDataGeneration || refreshToken !== this.classroomRefreshToken) {
          return;
        }
        const fetched: ClassroomsCache = await this.classroomClient.fetch(credentials, targetDate);
        if (generation !== this.localDataGeneration || refreshToken !== this.classroomRefreshToken) {
          return;
        }
        await this.classroomStore.save(fetched);
        this.classroomsCache = fetched;
        const buildings: Set<string> = new Set<string>(this.campusBuildings());
        const kept: Set<string> = new Set<string>();
        for (const building of this.selectedBuildings) {
          if (buildings.has(building)) {
            kept.add(building);
          }
        }
        this.selectedBuildings = kept;
        this.classroomStatusMessage = '当天空教室已更新';
      } catch (e) {
        if (generation !== this.localDataGeneration || refreshToken !== this.classroomRefreshToken) {
          return;
        }
        this.classroomStatusMessage = e instanceof Error ? e.message : '';
      } finally {
        if (refreshToken === this.classroomRefreshToken) {
          this.isRefreshingClassrooms = false;
          this.classroomRefreshInFlight = false;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // ---------- 校区天气 ----------

  private resetWeatherState(): void {
    this.weatherRevision++;
    this.weatherByCampus = new Map<string, CampusWeather>();
    this.weatherErrors = new Map<string, string>();
    this.loadingWeatherCampuses = new Set<string>();
  }

  loadWeather(campusID: string, force: boolean = false): void {
    if (!this.weatherEnabled) {
      return;
    }
    if (!force && this.weatherByCampus.has(campusID)) {
      return;
    }
    if (this.loadingWeatherCampuses.has(campusID)) {
      return;
    }
    if (this.isSampleMode()) {
      const sampleWeather: Map<string, CampusWeather> =
        new Map<string, CampusWeather>(this.weatherByCampus);
      sampleWeather.set(campusID, SampleData.weather(campusID));
      this.weatherByCampus = sampleWeather;
      return;
    }

    const loading: Set<string> = new Set<string>(this.loadingWeatherCampuses);
    loading.add(campusID);
    this.loadingWeatherCampuses = loading;
    const errors: Map<string, string> = new Map<string, string>(this.weatherErrors);
    errors.delete(campusID);
    this.weatherErrors = errors;
    const revision: number = this.weatherRevision;

    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const fetched: CampusWeather = await this.weatherClient.fetchWeather(campusID);
        if (revision !== this.weatherRevision) {
          return;
        }
        const next: Map<string, CampusWeather> = new Map<string, CampusWeather>(this.weatherByCampus);
        next.set(campusID, fetched);
        this.weatherByCampus = next;
      } catch (e) {
        if (revision !== this.weatherRevision) {
          return;
        }
        const nextErrors: Map<string, string> = new Map<string, string>(this.weatherErrors);
        nextErrors.set(campusID, e instanceof Error ? e.message : '天气获取失败。');
        this.weatherErrors = nextErrors;
      } finally {
        if (revision === this.weatherRevision) {
          const nextLoading: Set<string> = new Set<string>(this.loadingWeatherCampuses);
          nextLoading.delete(campusID);
          this.loadingWeatherCampuses = nextLoading;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // ---------- 月视图日期详情（作业 / 黄历 / DDL） ----------

  private resetCalendarDailyInfoState(): void {
    this.calendarDailyInfoRevision++;
    this.almanacByDate = new Map<string, AlmanacInfo>();
    this.almanacErrors = new Map<string, string>();
    this.loadingAlmanacDates = new Set<string>();
    this.publicDeadlinesByDate = new Map<string, PublicDeadlineSnapshot>();
    this.publicDeadlineErrors = new Map<string, string>();
    this.loadingPublicDeadlineDates = new Set<string>();
    this.assignmentDeadlinesByDate = new Map<string, AssignmentDeadlineItem[]>();
    this.assignmentUnavailableByDate = new Map<string, string>();
    this.loadingAssignmentDates = new Set<string>();
    this.calendarMarkerLoadingDates.clear();
    this.assignmentClient.reset();
  }

  // 月格/年格标记的批量预取与视图动画分离：UCloud 和公开 DDL 客户端
  // 各自共享一次全量请求，这里只在内存中按日期分组，最后一次性交付 Map。
  prefetchCalendarMarkers(days: DateParts[]): void {
    const dates: string[] = [];
    for (const day of days) {
      const date: string = StrictDates.formatDateParts(day);
      if (!this.calendarMarkerLoadingDates.has(date) && !dates.includes(date)) {
        const needsAssignments: boolean = !this.assignmentDeadlinesByDate.has(date) &&
          !this.assignmentUnavailableByDate.has(date);
        const needsDeadlines: boolean = this.hasEnabledPublicDeadlines() &&
          !this.publicDeadlinesByDate.has(date);
        if (needsAssignments || needsDeadlines) {
          dates.push(date);
          this.calendarMarkerLoadingDates.add(date);
        }
      }
    }
    if (dates.length === 0) {
      return;
    }
    const revision: number = this.calendarDailyInfoRevision;
    const work: Promise<void> = (async (): Promise<void> => {
      const assignmentResults: Map<string, AssignmentDeadlineItem[]> =
        new Map<string, AssignmentDeadlineItem[]>();
      const deadlineResults: Map<string, PublicDeadlineSnapshot> =
        new Map<string, PublicDeadlineSnapshot>();
      if (this.isSampleMode()) {
        for (const date of dates) {
          const parts: DateParts | null = StrictDates.parseDateString(date);
          assignmentResults.set(date, parts !== null && parts.day % 5 === 3 ?
            [new AssignmentDeadlineItem(
              'sample-assignment', '示例课程作业', '示例课程', date + ' 23:59:00', '未提交')] : []);
          if (this.hasEnabledPublicDeadlines()) {
            const items: PublicDeadlineItem[] = parts !== null && parts.day % 7 === 2 ?
              [new PublicDeadlineItem(
                'sample-competition', '全国大学生示例竞赛', PublicDeadlineKind.competition,
                PublicDeadlineSource.contestDDL, date + 'T23:59:00+08:00', '示例组委会', null)] : [];
            deadlineResults.set(date, new PublicDeadlineSnapshot(date, items,
            'https://nemoyuzx.github.io/contest-ddl/data/competitions.json', false));
          }
        }
      } else {
        try {
          const credentials: Credentials = await this.credentialsForRequest();
          for (const date of dates) {
            if (!this.assignmentDeadlinesByDate.has(date) &&
              !this.assignmentUnavailableByDate.has(date)) {
              assignmentResults.set(date, await this.assignmentClient.fetch(credentials, date));
            }
          }
        } catch (e) {
          // 未登录或作业源不可用时，不影响公开 DDL 的批量预取。
        }
        if (this.hasEnabledPublicDeadlines()) {
          for (const date of dates) {
            if (!this.publicDeadlinesByDate.has(date)) {
              try {
                deadlineResults.set(date, await this.calendarDailyInfoClient.fetchDeadlines(date));
              } catch (e) {
                // 标记预取不显示错误；选中日期的详情请求会给出可重试状态。
              }
            }
          }
        }
      }
      if (revision !== this.calendarDailyInfoRevision) {
        return;
      }
      if (assignmentResults.size > 0) {
        const assignments: Map<string, AssignmentDeadlineItem[]> =
          new Map<string, AssignmentDeadlineItem[]>(this.assignmentDeadlinesByDate);
        assignmentResults.forEach((items: AssignmentDeadlineItem[], date: string) => {
          assignments.set(date, items);
        });
        this.assignmentDeadlinesByDate = assignments;
      }
      if (deadlineResults.size > 0) {
        const deadlines: Map<string, PublicDeadlineSnapshot> =
          new Map<string, PublicDeadlineSnapshot>(this.publicDeadlinesByDate);
        deadlineResults.forEach((snapshot: PublicDeadlineSnapshot, date: string) => {
          deadlines.set(date, snapshot);
        });
        this.publicDeadlinesByDate = deadlines;
      }
    })();
    work.finally((): void => {
      for (const date of dates) {
        this.calendarMarkerLoadingDates.delete(date);
      }
    }).catch(() => {
      // 上述数据源均在内部降级，不让预取失败泄漏为未处理 Promise。
    });
  }

  loadCalendarDailyInfo(date: string, forceAlmanac: boolean = false,
    forceDeadlines: boolean = false): void {
    if (StrictDates.parseDateString(date) === null) {
      return;
    }
    this.loadAssignments(date, false);
    if (this.almanacEnabled) {
      this.loadAlmanac(date, forceAlmanac);
    }
    if (this.hasEnabledPublicDeadlines()) {
      this.loadPublicDeadlines(date, forceDeadlines);
    }
  }

  retryAssignments(date: string): void {
    this.loadAssignments(date, true);
  }

  private loadAssignments(date: string, force: boolean): void {
    if ((!force && (this.assignmentDeadlinesByDate.has(date) ||
      this.assignmentUnavailableByDate.has(date))) || this.loadingAssignmentDates.has(date)) {
      return;
    }
    const assignments: Map<string, AssignmentDeadlineItem[]> =
      new Map<string, AssignmentDeadlineItem[]>(this.assignmentDeadlinesByDate);
    const unavailable: Map<string, string> = new Map<string, string>(this.assignmentUnavailableByDate);
    if (this.isSampleMode()) {
      assignments.set(date, [new AssignmentDeadlineItem(
        'sample-assignment', '示例课程作业', '示例课程', date + ' 23:59:00', '未提交')]);
      unavailable.delete(date);
      this.assignmentDeadlinesByDate = assignments;
      this.assignmentUnavailableByDate = unavailable;
      return;
    }
    this.assignmentDeadlinesByDate = assignments;
    unavailable.set(date, '正在同步云课堂作业…');
    this.assignmentUnavailableByDate = unavailable;
    const loading: Set<string> = new Set<string>(this.loadingAssignmentDates);
    loading.add(date);
    this.loadingAssignmentDates = loading;
    const revision: number = this.calendarDailyInfoRevision;
    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const credentials: Credentials = await this.credentialsForRequest();
        const fetched: AssignmentDeadlineItem[] = await this.assignmentClient.fetch(credentials, date);
        if (revision !== this.calendarDailyInfoRevision) {
          return;
        }
        const nextAssignments: Map<string, AssignmentDeadlineItem[]> =
          new Map<string, AssignmentDeadlineItem[]>(this.assignmentDeadlinesByDate);
        nextAssignments.set(date, fetched);
        this.assignmentDeadlinesByDate = nextAssignments;
        const nextUnavailable: Map<string, string> =
          new Map<string, string>(this.assignmentUnavailableByDate);
        nextUnavailable.delete(date);
        this.assignmentUnavailableByDate = nextUnavailable;
      } catch (e) {
        if (revision !== this.calendarDailyInfoRevision) {
          return;
        }
        const nextAssignments: Map<string, AssignmentDeadlineItem[]> =
          new Map<string, AssignmentDeadlineItem[]>(this.assignmentDeadlinesByDate);
        nextAssignments.set(date, []);
        this.assignmentDeadlinesByDate = nextAssignments;
        const nextUnavailable: Map<string, string> =
          new Map<string, string>(this.assignmentUnavailableByDate);
        nextUnavailable.set(date, e instanceof Error ? e.message : '课程作业获取失败。');
        this.assignmentUnavailableByDate = nextUnavailable;
      } finally {
        if (revision === this.calendarDailyInfoRevision) {
          const nextLoading: Set<string> = new Set<string>(this.loadingAssignmentDates);
          nextLoading.delete(date);
          this.loadingAssignmentDates = nextLoading;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  private loadAlmanac(date: string, force: boolean): void {
    if (!this.almanacEnabled || (!force && this.almanacByDate.has(date)) ||
      this.loadingAlmanacDates.has(date)) {
      return;
    }
    if (this.isSampleMode()) {
      const sample: Map<string, AlmanacInfo> = new Map<string, AlmanacInfo>(this.almanacByDate);
      sample.set(date, new AlmanacInfo(
        date, '星期六', '七月初十', '丙午', '丙申', '戊辰', '马',
        null, null, null, '学习、交流、制定计划', '拖延、熬夜'));
      this.almanacByDate = sample;
      return;
    }
    const loading: Set<string> = new Set<string>(this.loadingAlmanacDates);
    loading.add(date);
    this.loadingAlmanacDates = loading;
    const errors: Map<string, string> = new Map<string, string>(this.almanacErrors);
    errors.delete(date);
    this.almanacErrors = errors;
    const revision: number = this.calendarDailyInfoRevision;
    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const fetched: AlmanacInfo = await this.calendarDailyInfoClient.fetchAlmanac(date);
        if (revision !== this.calendarDailyInfoRevision) {
          return;
        }
        const next: Map<string, AlmanacInfo> = new Map<string, AlmanacInfo>(this.almanacByDate);
        next.set(date, fetched);
        this.almanacByDate = next;
      } catch (e) {
        if (revision !== this.calendarDailyInfoRevision) {
          return;
        }
        const nextErrors: Map<string, string> = new Map<string, string>(this.almanacErrors);
        nextErrors.set(date, e instanceof Error ? e.message : '黄历获取失败。');
        this.almanacErrors = nextErrors;
      } finally {
        if (revision === this.calendarDailyInfoRevision) {
          const nextLoading: Set<string> = new Set<string>(this.loadingAlmanacDates);
          nextLoading.delete(date);
          this.loadingAlmanacDates = nextLoading;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  private loadPublicDeadlines(date: string, force: boolean): void {
    if (!this.hasEnabledPublicDeadlines() ||
      (!force && this.publicDeadlinesByDate.has(date)) ||
      this.loadingPublicDeadlineDates.has(date)) {
      return;
    }
    if (this.isSampleMode()) {
      const sample: Map<string, PublicDeadlineSnapshot> =
        new Map<string, PublicDeadlineSnapshot>(this.publicDeadlinesByDate);
      sample.set(date, new PublicDeadlineSnapshot(date, [new PublicDeadlineItem(
        'sample-competition', '全国大学生示例竞赛', PublicDeadlineKind.competition,
        PublicDeadlineSource.contestDDL, date + 'T23:59:00+08:00', '示例组委会', null)],
      'https://nemoyuzx.github.io/contest-ddl/data/competitions.json', false));
      this.publicDeadlinesByDate = sample;
      return;
    }
    const loading: Set<string> = new Set<string>(this.loadingPublicDeadlineDates);
    loading.add(date);
    this.loadingPublicDeadlineDates = loading;
    const errors: Map<string, string> = new Map<string, string>(this.publicDeadlineErrors);
    errors.delete(date);
    this.publicDeadlineErrors = errors;
    const revision: number = this.calendarDailyInfoRevision;
    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const fetched: PublicDeadlineSnapshot = await this.calendarDailyInfoClient.fetchDeadlines(date);
        if (revision !== this.calendarDailyInfoRevision) {
          return;
        }
        const next: Map<string, PublicDeadlineSnapshot> =
          new Map<string, PublicDeadlineSnapshot>(this.publicDeadlinesByDate);
        next.set(date, fetched);
        this.publicDeadlinesByDate = next;
      } catch (e) {
        if (revision !== this.calendarDailyInfoRevision) {
          return;
        }
        const nextErrors: Map<string, string> = new Map<string, string>(this.publicDeadlineErrors);
        nextErrors.set(date, e instanceof Error ? e.message : 'DDL 获取失败。');
        this.publicDeadlineErrors = nextErrors;
      } finally {
        if (revision === this.calendarDailyInfoRevision) {
          const nextLoading: Set<string> = new Set<string>(this.loadingPublicDeadlineDates);
          nextLoading.delete(date);
          this.loadingPublicDeadlineDates = nextLoading;
        }
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // ---------- 节假日 ----------

  holidayItems(year: number): HolidayItem[] {
    const snapshot: HolidaysSnapshot | undefined = this.holidaysByYear.get(year);
    return snapshot === undefined ? [] : snapshot.items;
  }

  ensureHolidays(year: number, force: boolean = false): void {
    if (year < 1900 || year > 2100) {
      return;
    }
    if (this.isSampleMode()) {
      if (!this.holidaysByYear.has(year)) {
        const sample: HolidaysSnapshot | null = SampleData.holidaysOrNull(year);
        if (sample !== null) {
          this.holidaysByYear.set(year, sample);
        }
      }
      return;
    }
    if (!this.holidaysByYear.has(year)) {
      const loadWork: Promise<void> = (async (): Promise<void> => {
        try {
          const cached: HolidaysSnapshot | null = await this.holidayStore.load(year);
          if (cached !== null) {
            this.holidaysByYear.set(year, cached);
          }
        } catch (e) {
          this.holidayStatusByYear.set(year, '本地节假日读取失败');
        }
      })();
      loadWork.catch(() => {
        // 已在内部处理。
      });
    }
    const cachedSnapshot: HolidaysSnapshot | undefined = this.holidaysByYear.get(year);
    if (!force && cachedSnapshot !== undefined && AppModel.isFreshHolidaySnapshot(cachedSnapshot)) {
      return;
    }
    const loadToken: number | null = this.holidayLoads.begin(year);
    if (loadToken === null) {
      return;
    }
    const cached: HolidaysSnapshot | undefined = this.holidaysByYear.get(year);
    const generation: number = this.localDataGeneration;

    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const fetched: HolidaysSnapshot = await this.holidayClient.fetch(year);
        if (generation !== this.localDataGeneration) {
          return;
        }
        await this.holidayStore.save(fetched);
        this.holidaysByYear.set(year, fetched);
        this.holidayStatusByYear.delete(year);
      } catch (e) {
        if (generation !== this.localDataGeneration) {
          return;
        }
        if (cached !== undefined) {
          this.holidayStatusByYear.set(year, '节假日更新失败，正在使用本地缓存');
        } else {
          const fallback: HolidaysSnapshot | null = HolidayOfflineFallback.snapshot(year);
          if (fallback !== null) {
            this.holidaysByYear.set(year, fallback);
            this.holidayStatusByYear.set(year, '节假日更新失败，正在使用内置 2026 年数据');
          } else {
            this.holidayStatusByYear.set(year, '节假日数据暂不可用');
          }
        }
      } finally {
        this.holidayLoads.finish(year, loadToken);
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // ---------- 内部实现 ----------

  private async loadCredentials(): Promise<void> {
    try {
      const credentials: Credentials | null = await this.credentialStore.load();
      if (credentials === null) {
        this.password = '';
        this.updateSavedCredentialState(null);
        return;
      }
      this.account = credentials.account;
      this.password = '';
      this.updateSavedCredentialState(credentials);
    } catch (e) {
      this.password = '';
      this.updateSavedCredentialState(null);
      this.statusMessage = e instanceof Error ? e.message : '';
    }
  }

  private async credentialsForRequest(): Promise<Credentials> {
    const stored: Credentials | null = await this.credentialStore.load();
    return CredentialSettingsLogic.credentialsForRequest(this.account, this.password, stored);
  }

  private updateSavedCredentialState(credentials: Credentials | null): void {
    this.savedCredentialAccount = credentials !== null ? credentials.account : null;
    this.hasSavedPassword = credentials !== null && credentials.password.length > 0;
  }

  private async clearAccountScopedData(): Promise<void> {
    this.invalidatePendingAccountRequests();
    const cancelWork: Promise<void> = this.cancelDailyCourseNotifications();
    cancelWork.catch(() => {
      // 取消失败由下次对账兜底。
    });
    if (this.dailyCourseNotificationsEnabled) {
      this.dailyCourseNotificationStatusMessage = '账号已更改，获取课表后将重新安排摘要';
    }
    let failed: boolean = false;
    try {
      await this.scheduleStore.clear();
    } catch (e) {
      failed = true;
    }
    this.schedule = null;
    this.synchronizeWidgetSchedule();
    this.calendarImportStatusMessage = '';
    try {
      await this.classroomStore.clear();
    } catch (e) {
      failed = true;
    }
    this.classroomsCache = null;
    this.classroomStatusMessage = '';
    this.resetCalendarDailyInfoState();
    this.selectedBuildings.clear();
    this.synchronizeSelectedSlots();
    if (failed) {
      throw CredentialSettingsError.accountDataResetFailed();
    }
  }

  private invalidatePendingAccountRequests(): void {
    this.localDataGeneration++;
    this.scheduleRefreshToken++;
    this.classroomRefreshToken++;
    this.isRefreshingSchedule = false;
    this.isRefreshingClassrooms = false;
  }

  private invalidatePendingOperations(): void {
    this.invalidatePendingAccountRequests();
    this.calendarImportToken++;
    this.isImportingCalendar = false;
  }

  private async loadSchedule(): Promise<void> {
    try {
      const loaded: ScheduleSnapshot | null = await this.scheduleStore.load();
      this.schedule = loaded;
      this.synchronizeWidgetSchedule();
      if (loaded !== null) {
        this.termID = loaded.termID;
        this.termStartDate = loaded.termStartDate;
      }
    } catch (e) {
      this.statusMessage = '本地课表读取失败：' + (e instanceof Error ? e.message : '');
    }
  }

  private async loadClassrooms(): Promise<void> {
    try {
      const cached: ClassroomsCache | null = await this.classroomStore.load();
      if (cached !== null && cached.targetDate === AppModel.todayString()) {
        this.classroomsCache = cached;
      }
    } catch (e) {
      this.classroomStatusMessage = '本地空教室读取失败：' + (e instanceof Error ? e.message : '');
    }
  }

  private synchronizeSelectedSlots(): void {
    const all: Set<number> = new Set<number>();
    for (const slot of this.slots) {
      all.add(slot.index);
    }
    if (this.usePersonalSchedule) {
      const busy: Set<number> = this.personalBusySlots();
      for (const slot of busy) {
        all.delete(slot);
      }
    }
    this.selectedSlots = all;
  }

  private setStatusMessage(message: string, autoDismiss: boolean = false): void {
    this.statusMessageRevision++;
    const revision: number = this.statusMessageRevision;
    if (this.statusMessageDismissTimer !== null) {
      clearTimeout(this.statusMessageDismissTimer);
      this.statusMessageDismissTimer = null;
    }
    this.statusMessage = message;
    if (!autoDismiss || message.length === 0) {
      return;
    }
    this.statusMessageDismissTimer = setTimeout(() => {
      if (this.statusMessageRevision === revision && this.statusMessage === message) {
        this.statusMessage = '';
        this.statusMessageDismissTimer = null;
      }
    }, this.statusMessageAutoDismissMs);
  }

  // 对应 iOS 端 synchronizeWidgetSchedule：课表变化后同步“今日课程”卡片。
  private synchronizeWidgetSchedule(): void {
    WidgetSync.refresh(this.schedule, new WidgetCoursePreferences(
    this.widgetShowsLocation, this.widgetShowsTeacher, this.widgetCourseLimit,
    this.resolvedLanguage()));
  }

  private static todayString(): string {
    return StrictDates.formatDateParts(StrictDates.todayParts());
  }

  private static isFreshHolidaySnapshot(snapshot: HolidaysSnapshot): boolean {
    const fetchedAt: number | null = StrictDates.parseFetchedAt(snapshot.fetchedAt);
    if (fetchedAt === null) {
      return false;
    }
    const age: number = Date.now() - fetchedAt;
    return age >= 0 && age <= 7 * 24 * 60 * 60 * 1000;
  }
}
