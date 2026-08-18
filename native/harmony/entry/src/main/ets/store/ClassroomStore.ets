// 与 iOS 端 ClassroomStore.swift 对应的空教室本地缓存。
// 缓存版本低于契约版本时直接忽略，保存使用原子写入。
import { ClassroomDefaults, ClassroomsCache } from '../common/Models';
import { AppContext } from './AppContext';
import { JsonFile } from './JsonFile';

export interface ClassroomStoring {
  load(): Promise<ClassroomsCache | null>;

  save(cache: ClassroomsCache): Promise<void>;

  clear(): Promise<void>;
}

export class FileClassroomStore implements ClassroomStoring {
  private readonly filePath: string;

  constructor(filePath: string = AppContext.classroomsFilePath()) {
    this.filePath = filePath;
  }

  async load(): Promise<ClassroomsCache | null> {
    const text: string | null = await JsonFile.readText(this.filePath);
    if (text === null) {
      return null;
    }
    let cache: ClassroomsCache;
    try {
      const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      cache = ClassroomsCache.fromJson(raw);
    } catch (e) {
      throw new Error('本地空教室缓存格式不正确。');
    }
    return cache.cacheVersion >= ClassroomDefaults.cacheVersion ? cache : null;
  }

  async save(cache: ClassroomsCache): Promise<void> {
    const text: string = JSON.stringify(cache.toJson(), null, 2);
    await JsonFile.writeTextAtomic(this.filePath, text);
  }

  async clear(): Promise<void> {
    await JsonFile.removeFile(this.filePath);
  }
}
