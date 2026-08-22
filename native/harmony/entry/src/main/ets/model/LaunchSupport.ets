// 与 iOS 端 UITestSupport.swift 对应的启动配置与示例依赖：
// AppRuntimeMode、启动参数与 UI 测试用示例存储/客户端。
import { Want } from '@kit.AbilityKit';
import { ClassroomsCache, HolidaysSnapshot, ScheduleSnapshot } from '../common/Models';
import { Credentials, CredentialStoring } from '../store/CredentialStore';
import { ScheduleStoring } from '../store/ScheduleStore';
import { ClassroomStoring } from '../store/ClassroomStore';
import { HolidayStoring } from '../store/HolidayStore';
import { ScheduleFetching } from '../net/SjdScheduleClient';
import { ClassroomFetching } from '../net/SjdClassroomClient';
import { HolidayFetching } from '../net/HolidayClient';
import { CampusWeather, WeatherFetching } from '../net/DailyInfoClient';
import { HolidayOfflineFallback } from '../net/parsers/HolidaySourceParser';
import { CalendarImporting } from '../calendar/CalendarImporter';
import { CalendarImportResult } from '../calendar/CalendarImportLogic';
import {
  DailyCourseNotificationAuthorization, DailyCourseNotificationRequest, DailyCourseNotificationScheduling
} from '../notify/DailyCoursePlanning';
import { SampleData } from './SampleData';
import { AppModel } from './AppModel';
import { AppRuntimeMode } from './AppRuntimeMode';

export { AppRuntimeMode };

export class AppLaunchConfiguration {
  static readonly uiTestingArgument: string = '--ui-testing';
  static readonly uiTestingLiveArgument: string = '--ui-testing-live';
  static readonly reviewDemoArgument: string = '--review-demo';

  static uiTesting: boolean = false;
  static uiTestingLive: boolean = false;
  static reviewDemo: boolean = false;

  // EntryAbility.onCreate 时从 want.parameters 读取 UI 测试/演示模式标记。
  static applyFromWant(want: Want): void {
    const params: Record<string, Object> = want.parameters ?? {};
    AppLaunchConfiguration.uiTesting =
      AppLaunchConfiguration.flag(params, 'uiTesting', AppLaunchConfiguration.uiTestingArgument);
    AppLaunchConfiguration.uiTestingLive =
      AppLaunchConfiguration.flag(params, 'uiTestingLive', AppLaunchConfiguration.uiTestingLiveArgument);
    AppLaunchConfiguration.reviewDemo =
      AppLaunchConfiguration.flag(params, 'reviewDemo', AppLaunchConfiguration.reviewDemoArgument);
  }

  static isUITesting(): boolean {
    return AppLaunchConfiguration.uiTesting;
  }

  static isUITestingLive(): boolean {
    return AppLaunchConfiguration.uiTestingLive;
  }

  static isReviewDemo(): boolean {
    return AppLaunchConfiguration.reviewDemo;
  }

  static makeModel(): AppModel {
    if (!AppLaunchConfiguration.isUITesting() && !AppLaunchConfiguration.isUITestingLive() &&
      !AppLaunchConfiguration.isReviewDemo()) {
      return new AppModel();
    }
    if (AppLaunchConfiguration.isUITestingLive()) {
      return new AppModel(
        AppRuntimeMode.live(),
        new SampleCredentialStore(),
        new SampleScheduleStore(null),
        new SampleScheduleClient(),
        new SampleClassroomStore(null),
        new SampleClassroomClient(),
        new SampleHolidayStore(),
        new SampleHolidayClient(),
        new SampleCalendarImporter(),
        new SampleDailyCourseNotificationScheduler(),
        'ui-tests-live',
        new SampleWeatherClient()
      );
    }
    return new AppModel(
      AppRuntimeMode.sample(AppLaunchConfiguration.isReviewDemo()),
      new SampleCredentialStore(),
      new SampleScheduleStore(),
      new SampleScheduleClient(),
      new SampleClassroomStore(),
      new SampleClassroomClient(),
      new SampleHolidayStore(),
      new SampleHolidayClient(),
      new SampleCalendarImporter(),
      new SampleDailyCourseNotificationScheduler(),
      'ui-tests',
      new SampleWeatherClient()
    );
  }

  private static flag(params: Record<string, Object>, key: string, argument: string): boolean {
    const direct: Object | undefined = params[key];
    const viaArgument: Object | undefined = params[argument];
    return direct === true || viaArgument === true;
  }
}

class SampleCredentialStore implements CredentialStoring {
  async load(): Promise<Credentials | null> {
    return null;
  }

  async save(credentials: Credentials): Promise<void> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }

  async clear(): Promise<void> {
  }
}

class SampleScheduleStore implements ScheduleStoring {
  private readonly schedule: ScheduleSnapshot | null;

  constructor(schedule: ScheduleSnapshot | null = SampleData.schedule()) {
    this.schedule = schedule;
  }

  async load(): Promise<ScheduleSnapshot | null> {
    return this.schedule;
  }

  async save(schedule: ScheduleSnapshot): Promise<void> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }

  async clear(): Promise<void> {
  }
}

class SampleScheduleClient implements ScheduleFetching {
  async fetch(credentials: Credentials, fallbackTermID: string,
    fallbackTermStartDate: string): Promise<ScheduleSnapshot> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }
}

class SampleClassroomStore implements ClassroomStoring {
  private readonly cache: ClassroomsCache | null;

  constructor(cache: ClassroomsCache | null = SampleData.classrooms()) {
    this.cache = cache;
  }

  async load(): Promise<ClassroomsCache | null> {
    return this.cache;
  }

  async save(cache: ClassroomsCache): Promise<void> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }

  async clear(): Promise<void> {
  }
}

class SampleClassroomClient implements ClassroomFetching {
  async fetch(credentials: Credentials, targetDate: string): Promise<ClassroomsCache> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }
}

class SampleHolidayStore implements HolidayStoring {
  async load(year: number): Promise<HolidaysSnapshot | null> {
    const fallback: HolidaysSnapshot | null = HolidayOfflineFallback.snapshot(year);
    if (fallback !== null) {
      return fallback;
    }
    return new HolidaysSnapshot(year, 'review-demo', SampleData.timestamp, []);
  }

  async save(snapshot: HolidaysSnapshot): Promise<void> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }

  async clear(): Promise<void> {
  }
}

class SampleHolidayClient implements HolidayFetching {
  async fetch(year: number): Promise<HolidaysSnapshot> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }
}

class SampleWeatherClient implements WeatherFetching {
  async fetchWeather(campusID: string): Promise<CampusWeather> {
    return SampleData.weather(campusID);
  }
}

class SampleCalendarImporter implements CalendarImporting {
  async importSchedule(schedule: ScheduleSnapshot): Promise<CalendarImportResult> {
    throw new Error('示例模式不会访问外部服务或系统数据。');
  }
}

class SampleDailyCourseNotificationScheduler implements DailyCourseNotificationScheduling {
  async authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization> {
    return DailyCourseNotificationAuthorization.denied;
  }

  async requestAuthorization(timeoutMs: number): Promise<boolean> {
    return false;
  }

  async replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<void> {
  }

  async cancelPending(revision: number): Promise<void> {
  }
}
