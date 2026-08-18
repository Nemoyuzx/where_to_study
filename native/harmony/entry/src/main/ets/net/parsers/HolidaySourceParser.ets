// 节假日数据源响应解析与离线兜底（纯模块，无平台依赖，可被主机侧单元测试引用）。
// 与 iOS 端 HolidaySourceParser / HolidayOfflineFallback 一一对应。
import { HolidayDefaults, HolidayItem, HolidaysSnapshot } from '../../common/Models';
import { StrictDates, DateParts } from '../../common/StrictDates';
import { JsonUtil } from '../../common/JsonUtil';
import { HolidayClientError, HolidaySourceLimits } from '../SjdErrors';

export class HolidaySourceParser {
  static parse(data: string, year: number, source: string, fetchedAt: string): HolidaysSnapshot {
    if (year < HolidayDefaults.supportedYearsStart || year > HolidayDefaults.supportedYearsEnd) {
      throw HolidayClientError.service('节假日年份不在支持范围内。');
    }
    if (data.length > HolidaySourceLimits.maximumPayloadBytes) {
      throw HolidayClientError.service('节假日数据响应过大。');
    }
    const payload: Record<string, Object> | null = JsonUtil.parseObject(data);
    if (payload === null) {
      throw HolidayClientError.service('节假日数据格式不正确。');
    }
    const payloadYear: number = JsonUtil.number(payload['year']);
    if (payloadYear !== year) {
      throw HolidayClientError.service('节假日数据年份与请求不一致。');
    }
    const region: string = JsonUtil.string(payload['region']);
    if (region !== 'CN') {
      throw HolidayClientError.service('节假日数据区域不正确。');
    }
    const dates: Object[] = JsonUtil.array(payload['dates']);
    if (dates.length > HolidaySourceLimits.maximumRecords) {
      throw HolidayClientError.service('节假日数据记录过多。');
    }
    const items: HolidayItem[] = [];
    for (const rawItem of dates) {
      const item: Record<string, Object> = JsonUtil.record(rawItem);
      // date 与 type 为必填字段（对应 Swift Codable 的非可选属性）。
      if (item['date'] === undefined || item['type'] === undefined) {
        throw HolidayClientError.service('节假日数据格式不正确。');
      }
      let name: string = JsonUtil.string(item['name_cn']).trim();
      if (name.length === 0) {
        name = JsonUtil.string(item['name']).trim();
      }
      if (name.length === 0) {
        throw HolidayClientError.service('节假日名称不能为空。');
      }
      if (name.length > HolidaySourceLimits.maximumNameLength) {
        throw HolidayClientError.service('节假日名称过长。');
      }
      const dateParts: DateParts | null = StrictDates.parseDateString(JsonUtil.string(item['date']));
      if (dateParts === null) {
        throw HolidayClientError.service('节假日数据日期格式不正确。');
      }
      if (dateParts.year !== year) {
        throw HolidayClientError.service('节假日数据包含其他年份的日期。');
      }
      const type: string | null = HolidaySourceParser.normalizedType(JsonUtil.string(item['type']));
      if (type === null) {
        continue;
      }
      if (items.length >= HolidaySourceLimits.maximumExpandedItems) {
        throw HolidayClientError.service('节假日展开记录过多。');
      }
      items.push(new HolidayItem(StrictDates.formatDateParts(dateParts), name, type));
    }
    if (items.length === 0) {
      throw HolidayClientError.service('节假日数据没有可识别的法定节假日或调休记录。');
    }
    items.sort((lhs: HolidayItem, rhs: HolidayItem) => {
      if (lhs.date !== rhs.date) {
        return lhs.date < rhs.date ? -1 : 1;
      }
      if (lhs.type !== rhs.type) {
        return lhs.type < rhs.type ? -1 : 1;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    return new HolidaysSnapshot(year, source, fetchedAt, items);
  }

  private static normalizedType(value: string): string | null {
    if (value === 'public_holiday') {
      return 'holiday';
    }
    if (value === 'transfer_workday') {
      return 'workday';
    }
    return null;
  }
}

class FallbackRange {
  readonly name: string;
  readonly startDate: string;
  readonly endDate: string;
  readonly type: string;

  constructor(name: string, startDate: string, endDate: string, type: string) {
    this.name = name;
    this.startDate = startDate;
    this.endDate = endDate;
    this.type = type;
  }
}

// 2026 年兜底日期（对应国务院办公厅通知，仅用于首次离线展示；
// 远端或本地缓存可用后使用自动获取的数据）。
export class HolidayOfflineFallback {
  static readonly source: string = 'https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm';

  static snapshot(year: number, fetchedAt?: string): HolidaysSnapshot | null {
    if (year !== 2026) {
      return null;
    }
    const at: string = fetchedAt === undefined ? StrictDates.formatFetchedAt(Date.now()) : fetchedAt;
    const ranges: FallbackRange[] = [
      new FallbackRange('元旦', '2026-01-01', '2026-01-03', 'holiday'),
      new FallbackRange('元旦补班', '2026-01-04', '2026-01-04', 'workday'),
      new FallbackRange('春节补班', '2026-02-14', '2026-02-14', 'workday'),
      new FallbackRange('春节', '2026-02-15', '2026-02-23', 'holiday'),
      new FallbackRange('春节补班', '2026-02-28', '2026-02-28', 'workday'),
      new FallbackRange('清明节', '2026-04-04', '2026-04-06', 'holiday'),
      new FallbackRange('劳动节', '2026-05-01', '2026-05-05', 'holiday'),
      new FallbackRange('劳动节补班', '2026-05-09', '2026-05-09', 'workday'),
      new FallbackRange('端午节', '2026-06-19', '2026-06-21', 'holiday'),
      new FallbackRange('中秋节', '2026-09-25', '2026-09-27', 'holiday'),
      new FallbackRange('国庆节补班', '2026-09-20', '2026-09-20', 'workday'),
      new FallbackRange('国庆节', '2026-10-01', '2026-10-07', 'holiday'),
      new FallbackRange('国庆节补班', '2026-10-10', '2026-10-10', 'workday')
    ];
    const items: HolidayItem[] = [];
    for (const range of ranges) {
      const start: DateParts | null = StrictDates.parseDateString(range.startDate);
      const end: DateParts | null = StrictDates.parseDateString(range.endDate);
      if (start === null || end === null) {
        return null;
      }
      const startDay: number = StrictDates.epochDay(start.year, start.month, start.day);
      const endDay: number = StrictDates.epochDay(end.year, end.month, end.day);
      if (startDay > endDay) {
        return null;
      }
      for (let day = startDay; day <= endDay; day++) {
        const parts: DateParts = StrictDates.partsFromEpochDay(day);
        items.push(new HolidayItem(StrictDates.formatDateParts(parts), range.name, range.type));
      }
    }
    return new HolidaysSnapshot(year, HolidayOfflineFallback.source, at, items);
  }
}
