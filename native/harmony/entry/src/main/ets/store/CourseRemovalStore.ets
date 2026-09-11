import { CourseRemovalRecord } from '../common/CourseRemoval';
import { JsonUtil } from '../common/JsonUtil';
import { AppContext } from './AppContext';
import { JsonFile } from './JsonFile';

export interface CourseRemovalStoring {
  load(): Promise<CourseRemovalRecord[]>;
  save(records: CourseRemovalRecord[]): Promise<void>;
  clear(): Promise<void>;
}

export class FileCourseRemovalStore implements CourseRemovalStoring {
  private readonly filePath: string;
  private tail: Promise<void> = Promise.resolve();

  constructor(filePath: string = '') {
    this.filePath = filePath;
  }

  private path(): string {
    return this.filePath.length > 0 ? this.filePath : AppContext.filesRoot() + '/course_removals.json';
  }

  async load(): Promise<CourseRemovalRecord[]> {
    await this.tail;
    const text: string | null = await JsonFile.readText(this.path());
    if (text === null) {
      return [];
    }
    const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    if (!Array.isArray(raw['records'])) {
      throw new Error('本地课程删除记录格式不正确。');
    }
    return JsonUtil.array(raw['records']).map((item: Object): CourseRemovalRecord =>
      CourseRemovalRecord.fromJson(JsonUtil.record(item)));
  }

  save(records: CourseRemovalRecord[]): Promise<void> {
    const out: Record<string, Object> = {
      'records': records.map((record: CourseRemovalRecord): Record<string, Object> => record.toJson())
    };
    const text: string = JSON.stringify(out);
    return this.enqueue(async (): Promise<void> => {
      await JsonFile.writeTextAtomic(this.path(), text);
    });
  }

  clear(): Promise<void> {
    return this.enqueue(async (): Promise<void> => {
      await JsonFile.removeFile(this.path());
    });
  }

  private enqueue(work: () => Promise<void>): Promise<void> {
    const task: Promise<void> = this.tail.then(work);
    this.tail = task.catch((): void => {});
    return task;
  }
}
