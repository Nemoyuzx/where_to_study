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

// 将课表 save/clear 串行化。clear 在 generation 失效后入队，因此一定排在
// 已开始的旧 save 之后；新账号 save 又排在 clear 之后，最终不会被旧任务反向删除。
export class SchedulePersistenceCoordinator {
  private readonly store: ScheduleStoring;
  private tail: Promise<void> = Promise.resolve();

  constructor(store: ScheduleStoring) {
    this.store = store;
  }

  async saveIfCurrent(schedule: ScheduleSnapshot, isCurrent: () => boolean): Promise<boolean> {
    let publish: boolean = false;
    await this.enqueue(async (): Promise<void> => {
      if (!isCurrent()) {
        return;
      }
      await this.store.save(schedule);
      // save 期间可能发生账号切换/清空；旧任务只能放弃发布，不能自行 clear，
      // 否则会误删队列中随后由新账号保存的数据。
      publish = isCurrent();
    });
    return publish;
  }

  async clear(): Promise<void> {
    await this.enqueue(async (): Promise<void> => {
      await this.store.clear();
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const task: Promise<void> = this.tail.then(operation);
    this.tail = task.catch((): void => {
      // 单次 I/O 失败不能堵死后续 clear/save 队列；失败仍由 task 返回给调用者。
    });
    return task;
  }
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
