// 与 iOS 端 HolidayStore.swift 对应的节假日本地缓存。
// 包含 HolidayCacheContract 的严格校验：精确字段集合、年份范围、
// 数据源与时间戳格式、条目数量、日期/名称/类型逐项核对。
import { HolidaysSnapshot } from '../common/Models';
import { StrictDates } from '../common/StrictDates';
import { HolidaySourceLimits } from '../net/SjdErrors';
import { AppContext } from './AppContext';
import { JsonFile } from './JsonFile';

export interface HolidayStoring {
  load(year: number): Promise<HolidaysSnapshot | null>;

  save(snapshot: HolidaysSnapshot): Promise<void>;

  clear(): Promise<void>;
}

export class FileHolidayStore implements HolidayStoring {
  private readonly directoryPath: string;

  constructor(directoryPath: string = AppContext.holidaysDirectoryPath()) {
    this.directoryPath = directoryPath;
  }

  private filePathFor(year: number): string {
    return this.directoryPath + '/holidays_' + year.toString() + '.json';
  }

  async load(year: number): Promise<HolidaysSnapshot | null> {
    HolidayCacheContract.validateRequestedYear(year);
    const text: string | null = await JsonFile.readText(
      this.filePathFor(year), HolidaySourceLimits.maximumPayloadBytes);
    if (text === null) {
      return null;
    }
    if (text.length > HolidaySourceLimits.maximumPayloadBytes) {
      throw new Error('本地节假日缓存过大。');
    }
    return HolidayCacheContract.decode(text, year);
  }

  async save(snapshot: HolidaysSnapshot): Promise<void> {
    HolidayCacheContract.validate(snapshot, null);
    const text: string = JSON.stringify(snapshot.toJson(), null, 2);
    if (text.length > HolidaySourceLimits.maximumPayloadBytes) {
      throw new Error('本地节假日缓存过大。');
    }
    await JsonFile.writeTextAtomic(this.filePathFor(snapshot.year), text);
  }

  async clear(): Promise<void> {
    await JsonFile.removeDirectory(this.directoryPath);
  }
}

class HolidayCacheContract {
  private static readonly snapshotKeys: string[] = ['year', 'source', 'fetched_at', 'items'];
  private static readonly itemKeys: string[] = ['date', 'name', 'type'];
  private static readonly maximumSourceLength: number = 512;
  private static readonly maximumTimestampLength: number = 64;

  static decode(text: string, expectedYear: number): HolidaysSnapshot {
    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      throw new Error('本地节假日缓存格式不正确。');
    }
    // 结构校验的报错信息按 Swift 端原文保留。
    HolidayCacheContract.validateJSONStructure(raw);
    let snapshot: HolidaysSnapshot;
    try {
      snapshot = HolidaysSnapshot.fromJson(raw);
    } catch (e) {
      throw new Error('本地节假日缓存格式不正确。');
    }
    HolidayCacheContract.validate(snapshot, expectedYear);
    return snapshot;
  }

  static validateRequestedYear(year: number): void {
    if (year < 1900 || year > 2100) {
      throw new Error('节假日年份不在支持范围内。');
    }
  }

  static validate(snapshot: HolidaysSnapshot, expectedYear: number | null): void {
    if (snapshot.year < 1900 || snapshot.year > 2100) {
      throw new Error('本地节假日缓存的年份不在支持范围内。');
    }
    if (expectedYear !== null && snapshot.year !== expectedYear) {
      throw new Error('本地节假日缓存年份与请求不一致。');
    }
    const source: string = snapshot.source.trim();
    if (source.length === 0 || snapshot.source.length > HolidayCacheContract.maximumSourceLength) {
      throw new Error('本地节假日缓存的数据源不正确。');
    }
    if (!HolidayCacheContract.isContractTimestamp(snapshot.fetchedAt)) {
      throw new Error('本地节假日缓存的获取时间不正确。');
    }
    if (snapshot.items.length > HolidaySourceLimits.maximumExpandedItems) {
      throw new Error('本地节假日缓存的条目数量超过限制。');
    }
    for (const item of snapshot.items) {
      const parts = StrictDates.parseDateString(item.date);
      if (parts === null) {
        throw new Error('本地节假日缓存的日期不正确。');
      }
      if (parts.year !== snapshot.year) {
        throw new Error('本地节假日缓存包含其他年份的日期。');
      }
      const name: string = item.name.trim();
      if (name.length === 0 || item.name.length > HolidaySourceLimits.maximumNameLength) {
        throw new Error('本地节假日缓存的名称不正确。');
      }
      if (item.type !== 'holiday' && item.type !== 'workday') {
        throw new Error('本地节假日缓存的类型不正确。');
      }
    }
  }

  private static validateJSONStructure(root: Record<string, Object>): void {
    if (!HolidayCacheContract.exactKeys(root, HolidayCacheContract.snapshotKeys)) {
      throw new Error('本地节假日缓存根对象格式不正确。');
    }
    const itemsRaw: Object | undefined = root['items'];
    if (itemsRaw === undefined || !Array.isArray(itemsRaw)) {
      throw new Error('本地节假日缓存的 items 格式不正确。');
    }
    const items: Object[] = itemsRaw as Object[];
    for (const value of items) {
      if (value === undefined || value === null || typeof value !== 'object') {
        throw new Error('本地节假日缓存的条目格式不正确。');
      }
      const item: Record<string, Object> = value as Record<string, Object>;
      if (!HolidayCacheContract.exactKeys(item, HolidayCacheContract.itemKeys)) {
        throw new Error('本地节假日缓存的条目字段不正确。');
      }
    }
  }

  private static exactKeys(record: Record<string, Object>, expected: string[]): boolean {
    const keys: string[] = Object.keys(record);
    if (keys.length !== expected.length) {
      return false;
    }
    const sortedKeys: string[] = keys.sort();
    const sortedExpected: string[] = expected.slice().sort();
    for (let i = 0; i < sortedKeys.length; i++) {
      if (sortedKeys[i] !== sortedExpected[i]) {
        return false;
      }
    }
    return true;
  }

  private static isContractTimestamp(value: string): boolean {
    if (value.length > HolidayCacheContract.maximumTimestampLength) {
      return false;
    }
    const pattern: RegExp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})$/;
    if (!pattern.test(value)) {
      return false;
    }
    return StrictDates.parseFetchedAt(value) !== null;
  }
}
