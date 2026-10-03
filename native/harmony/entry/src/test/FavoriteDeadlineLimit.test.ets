import { describe, it, expect } from '@ohos/hypium';
import { AppModel } from '../main/ets/model/AppModel';
import { AppRuntimeMode } from '../main/ets/model/AppRuntimeMode';
import { ClassroomsCache, HolidaysSnapshot, ScheduleSnapshot } from '../main/ets/common/Models';
import { ExamSchedule, GradeOptions, GradeSnapshot } from '../main/ets/common/AcademicModels';
import { CourseRemovalRecord } from '../main/ets/common/CourseRemoval';
import { Credentials, CredentialStoring } from '../main/ets/store/CredentialStore';
import { ScheduleStoring } from '../main/ets/store/ScheduleStore';
import { ClassroomStoring } from '../main/ets/store/ClassroomStore';
import { HolidayStoring } from '../main/ets/store/HolidayStore';
import { CourseRemovalStoring } from '../main/ets/store/CourseRemovalStore';
import { PreferencesStore } from '../main/ets/store/PreferencesStore';
import { ScheduleFetching } from '../main/ets/net/SjdScheduleClient';
import { ClassroomFetching } from '../main/ets/net/SjdClassroomClient';
import { HolidayFetching } from '../main/ets/net/HolidayClient';
import { CampusWeather, WeatherFetching } from '../main/ets/net/DailyInfoClient';
import { AssignmentDeadlineFetching } from '../main/ets/net/UCloudAssignmentClient';
import { GradeFetching, ExamFetching } from '../main/ets/net/SjdGradeClient';
import { CalendarImporting } from '../main/ets/calendar/CalendarImporter';
import { CalendarImportResult } from '../main/ets/calendar/CalendarImportLogic';
import {
  DailyCourseNotificationAuthorization, DailyCourseNotificationRequest, DailyCourseNotificationScheduling
} from '../main/ets/notify/DailyCoursePlanning';
import {
  AssignmentDeadlineItem, FavoriteDeadlineCodec, PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineSource
} from '../main/ets/net/CalendarDailyInfoClient';

// 显式注入全部有副作用的构造依赖；不能将 undefined 当作 mock，
// FileScheduleStore 等默认参数会在构造时访问真实 AppContext。
class FavoriteCredentials implements CredentialStoring {
  async load(): Promise<Credentials | null> { return null; }
  async save(credentials: Credentials): Promise<void> {}
  async clear(): Promise<void> {}
}
class FavoriteSchedules implements ScheduleStoring {
  async load(): Promise<ScheduleSnapshot | null> { return null; }
  async save(schedule: ScheduleSnapshot): Promise<void> {}
  async clear(): Promise<void> {}
}
class FavoriteScheduleClient implements ScheduleFetching {
  async fetch(credentials: Credentials, fallbackTermID: string,
    fallbackTermStartDate: string): Promise<ScheduleSnapshot> {
    throw new Error('synthetic schedule client must not be called');
  }
}
class FavoriteClassrooms implements ClassroomStoring {
  async load(): Promise<ClassroomsCache | null> { return null; }
  async save(cache: ClassroomsCache): Promise<void> {}
  async clear(): Promise<void> {}
}
class FavoriteClassroomClient implements ClassroomFetching {
  async fetch(credentials: Credentials, targetDate: string): Promise<ClassroomsCache> {
    throw new Error('synthetic classroom client must not be called');
  }
}
class FavoriteHolidays implements HolidayStoring {
  async load(year: number): Promise<HolidaysSnapshot | null> { return null; }
  async save(snapshot: HolidaysSnapshot): Promise<void> {}
  async clear(): Promise<void> {}
}
class FavoriteHolidayClient implements HolidayFetching {
  async fetch(year: number): Promise<HolidaysSnapshot> {
    throw new Error('synthetic holiday client must not be called');
  }
}
class FavoriteCalendarImporter implements CalendarImporting {
  async importSchedule(schedule: ScheduleSnapshot): Promise<CalendarImportResult> {
    throw new Error('synthetic calendar importer must not be called');
  }
  async importFavorites(items: PublicDeadlineItem[]): Promise<CalendarImportResult> {
    throw new Error('synthetic calendar importer must not be called');
  }
}
export class FavoriteReminderScheduler implements DailyCourseNotificationScheduling {
  cancelCount: number = 0;
  async authorizationStatus(timeoutMs: number): Promise<DailyCourseNotificationAuthorization> {
    return DailyCourseNotificationAuthorization.denied;
  }
  async requestAuthorization(timeoutMs: number): Promise<boolean> { return false; }
  async replacePending(requests: DailyCourseNotificationRequest[], revision: number): Promise<number> { return 0; }
  async cancelPending(revision: number): Promise<void> { this.cancelCount++; }
}
class FavoriteWeatherClient implements WeatherFetching {
  async fetchWeather(campusID: string): Promise<CampusWeather> {
    throw new Error('synthetic weather client must not be called');
  }
}
class FavoriteAssignmentClient implements AssignmentDeadlineFetching {
  async fetch(credentials: Credentials, date: string): Promise<AssignmentDeadlineItem[]> {
    throw new Error('synthetic assignment client must not be called');
  }
  async fetchCatalog(credentials: Credentials, refresh: boolean = false): Promise<AssignmentDeadlineItem[]> {
    throw new Error('synthetic assignment client must not be called');
  }
  reset(): void {}
}
class FavoriteCourseRemovals implements CourseRemovalStoring {
  async load(): Promise<CourseRemovalRecord[]> { return []; }
  async save(records: CourseRemovalRecord[]): Promise<void> {}
  async clear(): Promise<void> {}
}
class FavoriteGradeClient implements GradeFetching {
  async options(credentials: Credentials): Promise<GradeOptions> {
    throw new Error('synthetic grade client must not be called');
  }
  async fetch(credentials: Credentials, termID: string, recordType: string): Promise<GradeSnapshot> {
    throw new Error('synthetic grade client must not be called');
  }
}
class FavoriteExamClient implements ExamFetching {
  async fetch(credentials: Credentials, termID: string): Promise<ExamSchedule> {
    throw new Error('synthetic exam client must not be called');
  }
}

class FavoriteWriteGate {
  private finish: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.finish = resolve; });
  release(): void { this.finish(); }
}

export class RecordingFavoritePreferences extends PreferencesStore {
  savedFavorites: string[] = [];
  favoriteValue: string | null = null;
  favoriteRemovals: number = 0;
  failNextFavoriteWrite: boolean = false;
  failNextThemeWrite: boolean = false;
  blockNextFavoriteWrite: FavoriteWriteGate | null = null;
  blockNextFavoriteRead: FavoriteWriteGate | null = null;
  readonly favoriteWriteStarted: FavoriteWriteGate = new FavoriteWriteGate();
  readonly favoriteReadStarted: FavoriteWriteGate = new FavoriteWriteGate();

  async getString(key: string): Promise<string | null> {
    if (key !== 'favoriteDeadlinesV1') { return null; }
    const captured: string | null = this.favoriteValue;
    const gate: FavoriteWriteGate | null = this.blockNextFavoriteRead;
    this.blockNextFavoriteRead = null;
    if (gate !== null) {
      this.favoriteReadStarted.release();
      await gate.promise;
    }
    return captured;
  }

  // 启动读取回归只使用本地记录型偏好；关闭公开源等功能，不能触发真实网络。
  async getBool(key: string, fallback: boolean): Promise<boolean> { return false; }
  async getNumber(key: string, fallback: number): Promise<number> { return fallback; }
  async getNumberArray(key: string): Promise<number[]> { return []; }
  async setBool(key: string, value: boolean): Promise<void> {}
  async setNumber(key: string, value: number): Promise<void> {}
  async setNumberArray(key: string, value: number[]): Promise<void> {}

  async setString(key: string, value: string): Promise<void> {
    if (key === 'colorThemeV1' && this.failNextThemeWrite) {
      this.failNextThemeWrite = false;
      throw new Error('synthetic downstream theme cleanup failure');
    }
    if (key === 'favoriteDeadlinesV1') {
      const gate: FavoriteWriteGate | null = this.blockNextFavoriteWrite;
      this.blockNextFavoriteWrite = null;
      if (gate !== null) {
        this.favoriteWriteStarted.release();
        await gate.promise;
      }
      if (this.failNextFavoriteWrite) {
        this.failNextFavoriteWrite = false;
        throw new Error('synthetic favorite persistence failure');
      }
      this.savedFavorites.push(value);
      this.favoriteValue = value;
    }
  }

  async remove(key: string): Promise<void> {
    if (key === 'favoriteDeadlinesV1') {
      this.favoriteRemovals++;
      this.favoriteValue = null;
    }
  }
}

function favorite(index: number): PublicDeadlineItem {
  return new PublicDeadlineItem(index.toString(), '合成活动 ' + index.toString(),
    PublicDeadlineKind.competition, PublicDeadlineSource.contestDDL,
    '2026-10-10T23:59:00+08:00', null, null);
}

export function testModel(preferences: RecordingFavoritePreferences,
  scheduler: DailyCourseNotificationScheduling = new FavoriteReminderScheduler()): AppModel {
  return new AppModel(AppRuntimeMode.live(), new FavoriteCredentials(), new FavoriteSchedules(),
    new FavoriteScheduleClient(), new FavoriteClassrooms(), new FavoriteClassroomClient(),
    new FavoriteHolidays(), new FavoriteHolidayClient(), new FavoriteCalendarImporter(),
    scheduler, 'favorite-limit-tests', new FavoriteWeatherClient(),
    new FavoriteAssignmentClient(), preferences, new FavoriteCourseRemovals(),
    new FavoriteGradeClient(), new FavoriteExamClient());
}

export default function favoriteDeadlineLimitTest() {
  describe('FavoriteDeadlineLimitTest', () => {
    it('rejects_501_without_memory_or_disk_write_and_allows_removal_then_addition', 0, async () => {
      const preferences: RecordingFavoritePreferences = new RecordingFavoritePreferences('favorite-limit-tests');
      const model: AppModel = testModel(preferences);
      const existing: PublicDeadlineItem[] = [];
      for (let index = 0; index < FavoriteDeadlineCodec.maximumFavorites; index++) {
        existing.push(favorite(index));
      }
      model.favoriteDeadlines = existing;

      const rejected: boolean = await model.toggleFavoriteDeadline(favorite(500));
      expect(rejected).assertFalse();
      expect(model.favoriteDeadlines.length).assertEqual(500);
      expect(model.isFavoriteDeadline(favorite(500))).assertFalse();
      expect(preferences.savedFavorites.length).assertEqual(0);
      expect(model.statusMessage).assertEqual(AppModel.favoriteDeadlineLimitMessage);

      const removed: boolean = await model.toggleFavoriteDeadline(existing[0]);
      expect(removed).assertTrue();
      expect(model.favoriteDeadlines.length).assertEqual(499);
      expect(model.isFavoriteDeadline(existing[0])).assertFalse();
      expect(preferences.savedFavorites.length).assertEqual(1);
      expect(FavoriteDeadlineCodec.decode(preferences.savedFavorites[0]).length).assertEqual(499);

      const added: boolean = await model.toggleFavoriteDeadline(favorite(500));
      expect(added).assertTrue();
      expect(model.favoriteDeadlines.length).assertEqual(500);
      expect(model.isFavoriteDeadline(favorite(500))).assertTrue();
      expect(preferences.savedFavorites.length).assertEqual(2);
      expect(FavoriteDeadlineCodec.decode(preferences.savedFavorites[1]).length).assertEqual(500);
    });

    it('failed_storage_write_does_not_publish_and_next_operation_recovers', 0, async () => {
      const preferences: RecordingFavoritePreferences = new RecordingFavoritePreferences('favorite-failure-tests');
      const model: AppModel = testModel(preferences);
      preferences.failNextFavoriteWrite = true;
      let rejected: boolean = false;
      await model.toggleFavoriteDeadline(favorite(1)).catch(() => { rejected = true; });
      expect(rejected).assertTrue();
      expect(model.favoriteDeadlines.length).assertEqual(0);
      expect(preferences.savedFavorites.length).assertEqual(0);

      expect(await model.toggleFavoriteDeadline(favorite(2))).assertTrue();
      expect(model.favoriteDeadlines.length).assertEqual(1);
      expect(FavoriteDeadlineCodec.decode(preferences.favoriteValue).length).assertEqual(1);
    });

    it('two_rapid_additions_are_serial_and_account_independent', 0, async () => {
      const preferences: RecordingFavoritePreferences = new RecordingFavoritePreferences('favorite-queue-tests');
      const model: AppModel = testModel(preferences);
      const gate: FavoriteWriteGate = new FavoriteWriteGate();
      preferences.blockNextFavoriteWrite = gate;
      model.account = 'synthetic-first-account';
      const first: Promise<boolean> = model.toggleFavoriteDeadline(favorite(1));
      const second: Promise<boolean> = model.toggleFavoriteDeadline(favorite(2));
      await preferences.favoriteWriteStarted.promise;
      expect(model.favoriteDeadlines.length).assertEqual(0);
      expect(preferences.savedFavorites.length).assertEqual(0);
      model.account = 'synthetic-second-account';
      gate.release();
      expect(await first).assertTrue();
      expect(await second).assertTrue();
      expect(model.favoriteDeadlines.length).assertEqual(2);
      expect(preferences.savedFavorites.length).assertEqual(2);
      expect(FavoriteDeadlineCodec.decode(preferences.favoriteValue).length).assertEqual(2);
    });

    it('two_rapid_management_cancels_are_idempotent_and_never_readd', 0, async () => {
      const preferences: RecordingFavoritePreferences = new RecordingFavoritePreferences('favorite-remove-tests');
      const model: AppModel = testModel(preferences);
      const existing: PublicDeadlineItem = favorite(8);
      model.favoriteDeadlines = [existing];
      preferences.favoriteValue = FavoriteDeadlineCodec.encode([existing]);
      const gate: FavoriteWriteGate = new FavoriteWriteGate();
      preferences.blockNextFavoriteWrite = gate;
      const first: Promise<void> = model.removeFavoriteDeadline(existing);
      const second: Promise<void> = model.removeFavoriteDeadline(existing);
      await preferences.favoriteWriteStarted.promise;
      expect(model.isFavoriteDeadline(existing)).assertTrue();
      gate.release();
      await first;
      await second;
      expect(model.isFavoriteDeadline(existing)).assertFalse();
      expect(model.favoriteDeadlines.length).assertEqual(0);
      expect(preferences.savedFavorites.length).assertEqual(1);
      expect(FavoriteDeadlineCodec.decode(preferences.favoriteValue).length).assertEqual(0);
    });

    it('clear_removes_favorite_key_after_inflight_write_even_if_later_device_cleanup_fails', 0, async () => {
      const preferences: RecordingFavoritePreferences = new RecordingFavoritePreferences('favorite-clear-tests');
      const model: AppModel = testModel(preferences);
      model.favoriteDeadlines = [favorite(0)];
      preferences.favoriteValue = FavoriteDeadlineCodec.encode(model.favoriteDeadlines);
      const gate: FavoriteWriteGate = new FavoriteWriteGate();
      preferences.blockNextFavoriteWrite = gate;
      const pending: Promise<boolean> = model.toggleFavoriteDeadline(favorite(1));
      await preferences.favoriteWriteStarted.promise;
      const clearing: Promise<void> = model.clearLocalData();
      let rejectedDuringClear: boolean = false;
      await model.toggleFavoriteDeadline(favorite(2)).catch(() => { rejectedDuringClear = true; });
      expect(rejectedDuringClear).assertTrue();
      gate.release();
      let staleOperationRejected: boolean = false;
      await pending.catch(() => { staleOperationRejected = true; });
      expect(staleOperationRejected).assertTrue();
      // 这只验证收藏事务/删除顺序，不声称系统卡片等设备依赖的完整清理成功。
      // 例如无 AppContext 时 WidgetSync.refreshTheme 会在收藏 key 删除后失败。
      await clearing.catch(() => {});
      expect(preferences.favoriteRemovals).assertEqual(1);
      expect(preferences.favoriteValue).assertNull();
      expect(model.favoriteDeadlines.length).assertEqual(0);
      expect(preferences.savedFavorites.length).assertEqual(1);
    });

    it('late_favorite_read_cannot_republish_after_clear_or_revive_on_next_toggle', 0, async () => {
      const preferences: RecordingFavoritePreferences = new RecordingFavoritePreferences('favorite-read-clear-tests');
      const model: AppModel = testModel(preferences);
      preferences.favoriteValue = FavoriteDeadlineCodec.encode([favorite(0)]);
      const gate: FavoriteWriteGate = new FavoriteWriteGate();
      preferences.blockNextFavoriteRead = gate;
      const loading: Promise<void> = model.launch();
      await preferences.favoriteReadStarted.promise;

      // 确保清理在收藏删除后确定失败；本用例只验证收藏失效，不声称全量清理原子成功。
      preferences.failNextThemeWrite = true;
      let downstreamFailure: boolean = false;
      await model.clearLocalData().catch(() => { downstreamFailure = true; });
      expect(downstreamFailure).assertTrue();
      expect(preferences.favoriteRemovals).assertEqual(1);
      expect(preferences.favoriteValue).assertNull();
      expect(model.favoriteDeadlines.length).assertEqual(0);

      gate.release();
      await loading;
      expect(model.favoriteDeadlines.length).assertEqual(0);
      expect(preferences.favoriteValue).assertNull();
      expect(await model.toggleFavoriteDeadline(favorite(2))).assertTrue();
      expect(model.favoriteDeadlines.length).assertEqual(1);
      expect(model.isFavoriteDeadline(favorite(0))).assertFalse();
      const saved: PublicDeadlineItem[] = FavoriteDeadlineCodec.decode(preferences.favoriteValue);
      expect(saved.length).assertEqual(1);
      expect(FavoriteDeadlineCodec.key(saved[0])).assertEqual(FavoriteDeadlineCodec.key(favorite(2)));
    });
  });
}
