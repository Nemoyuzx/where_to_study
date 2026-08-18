// 与 iOS 端 ScheduleStore.swift 对应的课表本地缓存。
// 加载时校验第一周周一日期并重新应用考试周推导，保存使用原子写入。
import { ScheduleSnapshot } from '../common/Models';
import { ScheduleLogic } from '../common/ScheduleLogic';
import { StrictDates } from '../common/StrictDates';
import { AppContext } from './AppContext';
import { JsonFile } from './JsonFile';

export interface ScheduleStoring {
  load(): Promise<ScheduleSnapshot | null>;

  save(schedule: ScheduleSnapshot): Promise<void>;

  clear(): Promise<void>;
}

export class FileScheduleStore implements ScheduleStoring {
  private readonly filePath: string;

  constructor(filePath: string = AppContext.scheduleFilePath()) {
    this.filePath = filePath;
  }

  async load(): Promise<ScheduleSnapshot | null> {
    const text: string | null = await JsonFile.readText(this.filePath);
    if (text === null) {
      return null;
    }
    let snapshot: ScheduleSnapshot;
    try {
      const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      snapshot = ScheduleSnapshot.fromJson(raw);
    } catch (e) {
      throw new Error('本地课表格式不正确。');
    }
    if (StrictDates.parseDateString(snapshot.termStartDate) === null) {
      throw new Error('本地课表的第一周周一日期格式不正确。');
    }
    return new ScheduleSnapshot(
      snapshot.termID,
      snapshot.termStartDate,
      snapshot.fetchedAt,
      ScheduleLogic.applyingExamWeeks(snapshot.courses)
    );
  }

  async save(schedule: ScheduleSnapshot): Promise<void> {
    if (StrictDates.parseDateString(schedule.termStartDate) === null) {
      throw new Error('本地课表的第一周周一日期格式不正确。');
    }
    const text: string = JSON.stringify(schedule.toJson(), null, 2);
    await JsonFile.writeTextAtomic(this.filePath, text);
  }

  async clear(): Promise<void> {
    await JsonFile.removeFile(this.filePath);
  }
}
