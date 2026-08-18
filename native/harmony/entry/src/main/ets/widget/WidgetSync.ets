// 应用侧卡片同步：课表变化后写入卡片归档并刷新所有已添加卡片，
// 对应 iOS 端 AppModel.synchronizeWidgetSchedule + WidgetCenter.reloadTimelines。
import { formProvider } from '@kit.FormKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ScheduleSnapshot } from '../common/Models';
import { JsonFile } from '../store/JsonFile';
import { AppContext } from '../store/AppContext';
import {
  TodayCourseWidgetData, WidgetArchive, WidgetArchiveCourse
} from './TodayCourseWidgetData';

export class WidgetSync {
  // AppModel 在课表保存/清除/加载后调用；失败不影响主流程。
  static refresh(schedule: ScheduleSnapshot | null): void {
    const work: Promise<void> = (async (): Promise<void> => {
      try {
        const path: string = TodayCourseWidgetData.archiveFilePath(AppContext.filesRoot());
        if (schedule === null) {
          await JsonFile.removeFile(path);
        } else {
          const archive: WidgetArchive = TodayCourseWidgetData.scheduleToArchive(schedule);
          const text: string = JSON.stringify(WidgetSync.archiveToJson(archive));
          await JsonFile.writeTextAtomic(path, text);
        }
        await WidgetSync.reloadAllForms();
      } catch (e) {
        // 卡片刷新失败不影响应用主流程。
      }
    })();
    work.catch(() => {
      // 已在内部处理。
    });
  }

  // 通知系统重载本应用全部“今日课程”卡片（等价于 iOS 的
  // WidgetCenter.reloadTimelines）；卡片侧在 onUpdateForm 里读取归档更新。
  static async reloadAllForms(): Promise<void> {
    try {
      await formProvider.reloadForms(
        AppContext.get(), 'entry', 'TodayCourseWidgetAbility', 'TodayCourseCard');
    } catch (e) {
      // 无已添加卡片或系统暂不支持时忽略，周期更新会兜底。
    }
  }

  static async loadArchive(path: string): Promise<WidgetArchive | null> {
    const text: string | null = await JsonFile.readText(path);
    if (text === null) {
      return null;
    }
    try {
      const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      return WidgetSync.parseArchive(raw);
    } catch (e) {
      // BUG-021 修复：解析失败不再静默，便于排查。
      hilog.warn(0x0000, 'WidgetSync', '卡片归档解析失败: %{public}s',
        e instanceof Error ? e.message : 'unknown');
      return null;
    }
  }

  // FormExtensionAbility.onAddForm 必须同步返回绑定数据，因此提供同步读取。
  static loadArchiveSync(path: string): WidgetArchive | null {
    try {
      fs.statSync(path);
      const text: string = fs.readTextSync(path);
      if (text.length === 0) {
        return null;
      }
      const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      return WidgetSync.parseArchive(raw);
    } catch (e) {
      hilog.warn(0x0000, 'WidgetSync', '卡片归档同步解析失败: %{public}s',
        e instanceof Error ? e.message : 'unknown');
      return null;
    }
  }

  private static parseArchive(raw: Record<string, Object>): WidgetArchive | null {
    const termStartDate: string = typeof raw['term_start_date'] === 'string' ?
      raw['term_start_date'] as string : '';
    const fetchedAt: string = typeof raw['fetched_at'] === 'string' ?
      raw['fetched_at'] as string : '';
    if (termStartDate.length === 0 || fetchedAt.length === 0) {
      return null;
    }
    const rawCourses: Object[] = Array.isArray(raw['courses']) ? raw['courses'] as Object[] : [];
    const courses: WidgetArchiveCourse[] = [];
    for (const item of rawCourses) {
      if (typeof item !== 'object') {
        continue;
      }
      const record: Record<string, Object> = item as Record<string, Object>;
      courses.push(new WidgetArchiveCourse(
        WidgetSync.asString(record['id']),
        WidgetSync.asString(record['name']),
        WidgetSync.asString(record['room']),
        WidgetSync.asString(record['time_range']),
        WidgetSync.asNumber(record['weekday']),
        WidgetSync.numberArray(record['week_numbers']),
        WidgetSync.numberArray(record['exam_week_numbers']),
        WidgetSync.asNumber(record['start_slot'])
      ));
    }
    return new WidgetArchive(termStartDate, fetchedAt, courses);
  }

  private static numberArray(value: Object | undefined): number[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const result: number[] = [];
    for (const item of value as Object[]) {
      if (typeof item === 'number') {
        result.push(item as number);
      }
    }
    return result;
  }

  private static asString(value: Object | undefined): string {
    return typeof value === 'string' ? value as string : '';
  }

  private static asNumber(value: Object | undefined): number {
    return typeof value === 'number' ? value as number : 0;
  }

  private static archiveToJson(archive: WidgetArchive): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['term_start_date'] = archive.termStartDate;
    out['fetched_at'] = archive.fetchedAt;
    const courses: Record<string, Object>[] = [];
    for (const course of archive.courses) {
      const item: Record<string, Object> = {};
      item['id'] = course.id;
      item['name'] = course.name;
      item['room'] = course.room;
      item['time_range'] = course.timeRange;
      item['weekday'] = course.weekday;
      item['week_numbers'] = course.weekNumbers;
      item['exam_week_numbers'] = course.examWeekNumbers;
      item['start_slot'] = course.startSlot;
      courses.push(item);
    }
    out['courses'] = courses;
    return out;
  }
}
