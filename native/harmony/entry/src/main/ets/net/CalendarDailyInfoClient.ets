// 教学日历日期详情的公开数据客户端：黄历（UAPI + Timeless）、
// 学科竞赛/夏令营/黑客松 DDL（Contest DDL 主源 + 固定 IP 备用源 + 校内竞赛通知），
// 以及北邮云课堂真实响应契约的作业解析器。
//
// 公开数据请求不携带账号、密码或 Cookie；所有地址均固定校验、禁止重定向，
// 并限制响应体大小。云课堂作业需要独立登录会话，本客户端只解析已获授权的
// 响应；真实登录同步由 UCloudAssignmentClient 负责，不读取浏览器令牌。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppMeta } from '../common/AppMeta';
import { JsonUtil } from '../common/JsonUtil';
import { StrictDates, DateParts } from '../common/StrictDates';
import { Utf8 } from '../common/Utf8';

export class AlmanacInfo {
  readonly date: string;
  readonly weekday: string;
  readonly lunarDate: string;
  readonly ganzhiYear: string;
  readonly ganzhiMonth: string;
  readonly ganzhiDay: string;
  readonly zodiac: string;
  readonly solarTerm: string | null;
  readonly lunarFestival: string | null;
  readonly solarFestival: string | null;
  readonly yi: string | null;
  readonly ji: string | null;

  constructor(date: string, weekday: string, lunarDate: string, ganzhiYear: string,
    ganzhiMonth: string, ganzhiDay: string, zodiac: string, solarTerm: string | null,
    lunarFestival: string | null, solarFestival: string | null, yi: string | null,
    ji: string | null) {
    this.date = date;
    this.weekday = weekday;
    this.lunarDate = lunarDate;
    this.ganzhiYear = ganzhiYear;
    this.ganzhiMonth = ganzhiMonth;
    this.ganzhiDay = ganzhiDay;
    this.zodiac = zodiac;
    this.solarTerm = solarTerm;
    this.lunarFestival = lunarFestival;
    this.solarFestival = solarFestival;
    this.yi = yi;
    this.ji = ji;
  }

  withAdvice(yi: string, ji: string): AlmanacInfo {
    return new AlmanacInfo(this.date, this.weekday, this.lunarDate, this.ganzhiYear,
      this.ganzhiMonth, this.ganzhiDay, this.zodiac, this.solarTerm,
      this.lunarFestival, this.solarFestival, yi, ji);
  }
}

export enum PublicDeadlineKind {
  competition = 'competition',
  summerCamp = 'summer_camp',
  hackathon = 'hackathon',
  custom = 'custom'
}

export enum PublicDeadlineSource {
  contestDDL = 'contest_ddl',
  schoolNotice = 'school_notice',
  custom = 'custom'
}

export class PublicDeadlineKindInfo {
  static fromWireValue(value: string): PublicDeadlineKind | null {
    if (value === PublicDeadlineKind.competition) {
      return PublicDeadlineKind.competition;
    }
    if (value === PublicDeadlineKind.summerCamp) {
      return PublicDeadlineKind.summerCamp;
    }
    if (value === PublicDeadlineKind.hackathon) {
      return PublicDeadlineKind.hackathon;
    }
    if (value === PublicDeadlineKind.custom) {
      return PublicDeadlineKind.custom;
    }
    return null;
  }

  static title(kind: PublicDeadlineKind): string {
    if (kind === PublicDeadlineKind.competition) {
      return '学科竞赛';
    }
    if (kind === PublicDeadlineKind.summerCamp) {
      return '夏令营';
    }
    if (kind === PublicDeadlineKind.hackathon) {
      return '黑客松';
    }
    return '自定义日程';
  }
}

export class PublicDeadlineSourceInfo {
  static fromWireValue(value: string): PublicDeadlineSource | null {
    if (value === PublicDeadlineSource.contestDDL) {
      return PublicDeadlineSource.contestDDL;
    }
    if (value === PublicDeadlineSource.schoolNotice) {
      return PublicDeadlineSource.schoolNotice;
    }
    if (value === PublicDeadlineSource.custom) {
      return PublicDeadlineSource.custom;
    }
    return null;
  }
}

export class PublicDeadlineItem {
  readonly id: string;
  readonly name: string;
  readonly kind: PublicDeadlineKind;
  readonly source: PublicDeadlineSource;
  readonly deadline: string;
  readonly organizer: string | null;
  readonly officialURL: string | null;
  readonly sourceName: string | null;
  readonly sourceHomepage: string | null;

  constructor(id: string, name: string, kind: PublicDeadlineKind,
    source: PublicDeadlineSource, deadline: string,
    organizer: string | null, officialURL: string | null,
    sourceName: string | null = null, sourceHomepage: string | null = null) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.source = source;
    this.deadline = deadline;
    this.organizer = organizer;
    this.officialURL = officialURL;
    this.sourceName = sourceName;
    this.sourceHomepage = sourceHomepage;
  }
}

export class PublicDeadlineSnapshot {
  readonly date: string;
  readonly items: PublicDeadlineItem[];
  readonly source: string;
  readonly usedBackup: boolean;

  constructor(date: string, items: PublicDeadlineItem[], source: string, usedBackup: boolean) {
    this.date = date;
    this.items = items;
    this.source = source;
    this.usedBackup = usedBackup;
  }
}

export class FavoriteDeadlineCodec {
  static readonly maximumFavorites: number = 500;

  static key(item: PublicDeadlineItem): string {
    const sourceIdentity: string = item.source === PublicDeadlineSource.custom ?
      (item.sourceHomepage ?? item.sourceName ?? '') : '';
    return item.source + '\u001f' + sourceIdentity + '\u001f' + item.id + '\u001f' + item.deadline;
  }

  static encode(items: PublicDeadlineItem[]): string {
    const records: Record<string, Object | null>[] = [];
    const seen: Set<string> = new Set<string>();
    for (const item of items) {
      const key: string = FavoriteDeadlineCodec.key(item);
      if (seen.has(key) || records.length >= FavoriteDeadlineCodec.maximumFavorites) {
        continue;
      }
      seen.add(key);
      const record: Record<string, Object | null> = {};
      record['id'] = item.id;
      record['name'] = item.name;
      record['event_type'] = item.kind;
      record['source_type'] = item.source;
      record['primary_deadline'] = item.deadline;
      record['organizer'] = item.organizer;
      record['official_url'] = item.officialURL;
      record['source_name'] = item.sourceName;
      record['source_homepage'] = item.sourceHomepage;
      records.push(record);
    }
    return JSON.stringify(records);
  }

  static decode(payload: string | null): PublicDeadlineItem[] {
    if (payload === null || payload.trim().length === 0) {
      return [];
    }
    let rawItems: Object[];
    try {
      const parsed: Object = JSON.parse(payload) as Object;
      rawItems = Array.isArray(parsed) ? parsed as Object[] : [];
    } catch (e) {
      return [];
    }
    const items: PublicDeadlineItem[] = [];
    const seen: Set<string> = new Set<string>();
    for (const raw of rawItems) {
      const record: Record<string, Object> = JsonUtil.record(raw);
      const id: string | null = CalendarResponseValues.optionalString(record, 'id');
      const name: string | null = CalendarResponseValues.optionalString(record, 'name');
      const kindValue: string | null = CalendarResponseValues.optionalString(record, 'event_type');
      const sourceValue: string | null = CalendarResponseValues.optionalString(record, 'source_type');
      const deadline: string | null = CalendarResponseValues.optionalString(record, 'primary_deadline');
      const kind: PublicDeadlineKind | null = kindValue === null ? null :
        PublicDeadlineKindInfo.fromWireValue(kindValue);
      const source: PublicDeadlineSource | null = sourceValue === null ? null :
        PublicDeadlineSourceInfo.fromWireValue(sourceValue);
      if (id === null || id.length > 128 || name === null || name.length > 200 ||
        kind === null || source === null || deadline === null || deadline.length < 10 ||
        StrictDates.parseDateString(deadline.substring(0, 10)) === null) {
        continue;
      }
      const rawURL: string | null = CalendarResponseValues.optionalString(record, 'official_url');
      const officialURL: string | null = rawURL !== null && rawURL.startsWith('https://') &&
        rawURL.indexOf('@') < 0 ? rawURL : null;
      const sourceName: string | null = CalendarResponseValues.optionalString(record, 'source_name');
      const rawSourceHomepage: string | null =
        CalendarResponseValues.optionalString(record, 'source_homepage');
      const sourceHomepage: string | null = rawSourceHomepage !== null &&
        rawSourceHomepage.startsWith('https://') && rawSourceHomepage.indexOf('@') < 0 ?
        rawSourceHomepage : null;
      const item: PublicDeadlineItem = new PublicDeadlineItem(
        id, name, kind, source, deadline,
        CalendarResponseValues.optionalString(record, 'organizer'), officialURL,
        sourceName !== null && sourceName.length <= 80 ? sourceName : null, sourceHomepage);
      const key: string = FavoriteDeadlineCodec.key(item);
      if (!seen.has(key)) {
        seen.add(key);
        items.push(item);
      }
      if (items.length >= FavoriteDeadlineCodec.maximumFavorites) {
        break;
      }
    }
    items.sort((left: PublicDeadlineItem, right: PublicDeadlineItem): number =>
      left.deadline === right.deadline ? left.name.localeCompare(right.name) :
        (left.deadline < right.deadline ? -1 : 1));
    return items;
  }
}

export class AssignmentDeadlineItem {
  readonly id: string;
  readonly title: string;
  readonly courseName: string | null;
  readonly deadline: string;
  readonly status: string | null;

  constructor(id: string, title: string, courseName: string | null, deadline: string,
    status: string | null) {
    this.id = id;
    this.title = title;
    this.courseName = courseName;
    this.deadline = deadline;
    this.status = status;
  }
}

export class CalendarDailyInfoSources {
  static readonly uapiOrigin: string = 'https://uapis.cn';
  static readonly timelessOrigin: string = 'https://api.timelessq.com';
  static readonly deadlinePrimary: string =
    'https://nemoyuzx.github.io/contest-ddl/data/competitions.json';
  static readonly deadlinePrimaryPage: string = 'https://nemoyuzx.github.io/contest-ddl/';
  static readonly deadlineBackup: string = 'http://101.201.29.29/api/contest-events';
  static readonly schoolContestNotices: string = 'http://101.201.29.29/api/contest-notices';
  static readonly assignments: string =
    'https://ucloud.bupt.edu.cn/uclass/course.html#/student/studentAssignmentListPage?ind=3';
  static readonly smallPayloadLimit: number = 128 * 1024;
  static readonly deadlinePayloadLimit: number = 2 * 1024 * 1024;
  static readonly maximumItemsPerDay: number = 100;
}

export class CalendarDailyInfoError extends Error {
  constructor(message: string) {
    super(message);
  }
}

export class AlmanacResponseParser {
  static parseBase(payload: string, requestedDate: string): AlmanacInfo {
    AlmanacResponseParser.requireDate(requestedDate, '黄历');
    const source: Record<string, Object> | null = JsonUtil.parseObject(payload);
    if (source === null) {
      throw new CalendarDailyInfoError('黄历数据格式不正确。');
    }
    const datetime: string = CalendarResponseValues.requiredString(
      source, 'datetime', '黄历数据格式不正确。');
    if (!datetime.startsWith(requestedDate)) {
      throw new CalendarDailyInfoError('黄历数据日期不一致。');
    }
    return new AlmanacInfo(
      requestedDate,
      CalendarResponseValues.requiredString(source, 'weekday_cn', '黄历数据格式不正确。'),
      CalendarResponseValues.requiredString(source, 'lunar_month_cn', '黄历数据格式不正确。') +
        CalendarResponseValues.requiredString(source, 'lunar_day_cn', '黄历数据格式不正确。'),
      CalendarResponseValues.requiredString(source, 'ganzhi_year', '黄历数据格式不正确。'),
      CalendarResponseValues.requiredString(source, 'ganzhi_month', '黄历数据格式不正确。'),
      CalendarResponseValues.requiredString(source, 'ganzhi_day', '黄历数据格式不正确。'),
      CalendarResponseValues.requiredString(source, 'zodiac', '黄历数据格式不正确。'),
      CalendarResponseValues.optionalString(source, 'solar_term'),
      CalendarResponseValues.optionalString(source, 'lunar_festival'),
      CalendarResponseValues.optionalString(source, 'solar_festival'),
      null,
      null
    );
  }

  static parseAdvice(payload: string, requestedDate: string): string[] {
    const requested: DateParts = AlmanacResponseParser.requireDate(requestedDate, '宜忌');
    const source: Record<string, Object> | null = JsonUtil.parseObject(payload);
    if (source === null) {
      throw new CalendarDailyInfoError('宜忌数据格式不正确。');
    }
    if (JsonUtil.number(source['errno'], -1) !== 0) {
      throw new CalendarDailyInfoError(
        CalendarResponseValues.optionalString(source, 'errmsg') ?? '宜忌接口返回错误。');
    }
    const data: Record<string, Object> = JsonUtil.record(source['data']);
    if (JsonUtil.number(data['year'], -1) !== requested.year ||
      JsonUtil.number(data['month'], -1) !== requested.month ||
      JsonUtil.number(data['day'], -1) !== requested.day) {
      throw new CalendarDailyInfoError('宜忌数据日期不一致。');
    }
    const almanac: Record<string, Object> = JsonUtil.record(data['almanac']);
    return [
      CalendarResponseValues.requiredString(almanac, 'yi', '宜忌数据格式不正确。'),
      CalendarResponseValues.requiredString(almanac, 'ji', '宜忌数据格式不正确。')
    ];
  }

  private static requireDate(value: string, label: string): DateParts {
    const parsed: DateParts | null = StrictDates.parseDateString(value);
    if (parsed === null) {
      throw new CalendarDailyInfoError(label + ' 日期格式不正确。');
    }
    return parsed;
  }
}

export class PublicDeadlineResponseParser {
  private static readonly rfc3339: RegExp = new RegExp(
    '^\\d{4}-\\d{2}-\\d{2}T(?:[01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d' +
      '(?:\\.\\d+)?(?:Z|[+-](?:[01]\\d|2[0-3]):[0-5]\\d)$');

  static parse(payload: string, requestedDate: string): PublicDeadlineItem[] {
    if (StrictDates.parseDateString(requestedDate) === null) {
      throw new CalendarDailyInfoError('DDL 日期格式不正确。');
    }
    return PublicDeadlineResponseParser.parseIndex(payload).get(requestedDate) ?? [];
  }

  static parseIndex(payload: string): Map<string, PublicDeadlineItem[]> {
    let root: Object;
    try {
      root = JSON.parse(payload) as Object;
    } catch (e) {
      throw new CalendarDailyInfoError('DDL 数据格式不正确。');
    }
    const records: Object[] = PublicDeadlineResponseParser.extractRecords(root);
    const indexed: Map<string, PublicDeadlineItem[]> = new Map<string, PublicDeadlineItem[]>();
    for (const raw of records) {
      const record: Record<string, Object> = JsonUtil.record(raw);
      const kindValue: string | null = CalendarResponseValues.firstString(
        record, ['event_type', 'eventType', 'type']);
      const kind: PublicDeadlineKind | null = kindValue === null ? null :
        PublicDeadlineKindInfo.fromWireValue(kindValue);
      const id: string | null = CalendarResponseValues.firstString(record, ['id', 'event_id', 'eventId']);
      const name: string | null = CalendarResponseValues.firstString(
        record, ['name', 'title', 'event_name']);
      const deadline: string | null = CalendarResponseValues.firstString(
        record, ['primary_deadline', 'primaryDeadline', 'deadline', 'end_time']);
      if (kind === null || id === null || name === null || deadline === null ||
        !PublicDeadlineResponseParser.rfc3339.test(deadline)) {
        continue;
      }
      const date: string = deadline.substring(0, 10);
      if (StrictDates.parseDateString(date) === null) {
        continue;
      }
      const items: PublicDeadlineItem[] = indexed.get(date) ?? [];
      if (items.length >= CalendarDailyInfoSources.maximumItemsPerDay) {
        continue;
      }
      const rawURL: string | null = CalendarResponseValues.firstString(
        record, ['official_url', 'officialUrl', 'url']);
      const officialURL: string | null = rawURL !== null &&
        PublicDeadlineResponseParser.isTrustedOfficialURL(rawURL) ? rawURL : null;
      items.push(new PublicDeadlineItem(
        id, name, kind, PublicDeadlineSource.contestDDL, deadline,
        CalendarResponseValues.firstString(record, ['organizer', 'host']), officialURL));
      indexed.set(date, items);
    }
    indexed.forEach((items: PublicDeadlineItem[], date: string): void => {
      PublicDeadlineResponseParser.sortItems(items);
      indexed.set(date, items);
    });
    return indexed;
  }

  static parseCustomIndex(payload: string, feedURL: string | null = null):
    Map<string, PublicDeadlineItem[]> {
    let root: Object;
    try {
      root = JSON.parse(payload) as Object;
    } catch (e) {
      throw new CalendarDailyInfoError('自定义日程数据格式不正确。');
    }
    const source: Record<string, Object> = JsonUtil.record(root);
    const envelopeKeys: Set<string> = new Set<string>([
      'version', 'source', 'homepage', 'updated_at', 'items'
    ]);
    if (Object.keys(source).some((key: string): boolean => !envelopeKeys.has(key)) ||
      !Array.isArray(source['items'])) {
      throw new CalendarDailyInfoError('自定义日程不符合 v1 接口规范。');
    }
    if (JsonUtil.number(source['version'], -1) !== 1) {
      throw new CalendarDailyInfoError('自定义日程接口版本必须为 1。');
    }
    const sourceName: string | null = CalendarResponseValues.optionalString(source, 'source');
    if (sourceName === null || sourceName.length > 80) {
      throw new CalendarDailyInfoError('自定义日程来源名称无效。');
    }
    let sourceHomepage: string | null = null;
    if (source['homepage'] !== undefined) {
      const homepage: string | null = CalendarResponseValues.optionalString(source, 'homepage');
      if (homepage === null || !CustomDeadlineURLPolicy.allows(homepage)) {
        throw new CalendarDailyInfoError('自定义日程来源主页必须使用安全的 HTTPS URL。');
      }
      sourceHomepage = homepage;
    } else if (feedURL !== null && CustomDeadlineURLPolicy.allows(feedURL)) {
      sourceHomepage = feedURL;
    }
    if (source['updated_at'] !== undefined) {
      const updatedAt: string | null = CalendarResponseValues.optionalString(source, 'updated_at');
      if (updatedAt === null || !PublicDeadlineResponseParser.rfc3339.test(updatedAt)) {
        throw new CalendarDailyInfoError('自定义日程更新时间格式不正确。');
      }
    }
    const records: Object[] = JsonUtil.array(source['items']);
    if (records.length > 5000) {
      throw new CalendarDailyInfoError('自定义日程条目超过 5000 项。');
    }
    const indexed: Map<string, PublicDeadlineItem[]> = new Map<string, PublicDeadlineItem[]>();
    const itemKeys: Set<string> = new Set<string>([
      'id', 'name', 'event_type', 'primary_deadline', 'organizer', 'official_url'
    ]);
    for (const raw of records) {
      const record: Record<string, Object> = JsonUtil.record(raw);
      if (Object.keys(record).some((key: string): boolean => !itemKeys.has(key))) {
        continue;
      }
      const kindValue: string | null = CalendarResponseValues.optionalString(record, 'event_type');
      const kind: PublicDeadlineKind | null = kindValue === null ? null :
        PublicDeadlineKindInfo.fromWireValue(kindValue);
      const id: string | null = CalendarResponseValues.optionalString(record, 'id');
      const name: string | null = CalendarResponseValues.optionalString(record, 'name');
      const deadline: string | null = CalendarResponseValues.optionalString(record, 'primary_deadline');
      if (kind === null || id === null || id.length > 128 || name === null || name.length > 200 ||
        deadline === null || !PublicDeadlineResponseParser.rfc3339.test(deadline)) {
        continue;
      }
      const date: string = deadline.substring(0, 10);
      if (StrictDates.parseDateString(date) === null) {
        continue;
      }
      const items: PublicDeadlineItem[] = indexed.get(date) ?? [];
      if (items.length >= CalendarDailyInfoSources.maximumItemsPerDay) {
        continue;
      }
      const rawURL: string | null = CalendarResponseValues.optionalString(record, 'official_url');
      const officialURL: string | null = rawURL !== null &&
        PublicDeadlineResponseParser.isTrustedOfficialURL(rawURL) ? rawURL : null;
      if (rawURL !== null && officialURL === null) {
        continue;
      }
      const customOrganizer: string | null = CalendarResponseValues.optionalString(record, 'organizer');
      if (record['organizer'] !== undefined &&
        (customOrganizer === null || customOrganizer.length > 200)) {
        continue;
      }
      const organizer: string = customOrganizer ?? sourceName;
      items.push(new PublicDeadlineItem(
        'custom:' + id, name, kind, PublicDeadlineSource.custom, deadline, organizer, officialURL,
        sourceName, sourceHomepage));
      indexed.set(date, items);
    }
    indexed.forEach((items: PublicDeadlineItem[], date: string): void => {
      PublicDeadlineResponseParser.sortItems(items);
      indexed.set(date, items);
    });
    return indexed;
  }

  static parseSchoolNotices(payload: string, requestedDate: string): PublicDeadlineItem[] {
    if (StrictDates.parseDateString(requestedDate) === null) {
      throw new CalendarDailyInfoError('DDL 日期格式不正确。');
    }
    return PublicDeadlineResponseParser.parseSchoolNoticesIndex(payload).get(requestedDate) ?? [];
  }

  static parseSchoolNoticesIndex(payload: string): Map<string, PublicDeadlineItem[]> {
    let root: Object;
    try {
      root = JSON.parse(payload) as Object;
    } catch (e) {
      throw new CalendarDailyInfoError('校内竞赛通知格式不正确。');
    }
    const source: Record<string, Object> = JsonUtil.record(root);
    const records: Object[] = JsonUtil.array(source['items']);
    const indexed: Map<string, PublicDeadlineItem[]> = new Map<string, PublicDeadlineItem[]>();
    for (const raw of records) {
      const record: Record<string, Object> = JsonUtil.record(raw);
      const id: string | null = CalendarResponseValues.firstString(record, ['id', 'source_id']);
      const name: string | null = CalendarResponseValues.firstString(record, ['name', 'title']);
      if (id === null || name === null) {
        continue;
      }
      const sourceName: string = CalendarResponseValues.firstString(record, ['source']) ??
        '北京邮电大学教学云平台';
      const rawURL: string | null = CalendarResponseValues.firstString(record, ['source_url']);
      const officialURL: string | null = rawURL !== null &&
        PublicDeadlineResponseParser.isTrustedOfficialURL(rawURL) ? rawURL : null;
      let deadlines: Object[] = JsonUtil.array(record['deadlines']);
      if (deadlines.length === 0) {
        const primary: string | null = CalendarResponseValues.firstString(record, ['primary_deadline']);
        if (primary === null) {
          continue;
        }
        const fallback: Record<string, Object> = {};
        fallback['date'] = primary;
        fallback['label'] = CalendarResponseValues.firstString(
          record, ['primary_deadline_label']) ?? '截止时间';
        deadlines = [fallback];
      }
      for (let index: number = 0; index < deadlines.length; index += 1) {
        const deadlineRecord: Record<string, Object> = JsonUtil.record(deadlines[index]);
        const deadline: string | null = CalendarResponseValues.firstString(deadlineRecord, ['date']);
        if (deadline === null || !PublicDeadlineResponseParser.rfc3339.test(deadline)) {
          continue;
        }
        const date: string = deadline.substring(0, 10);
        if (StrictDates.parseDateString(date) === null) {
          continue;
        }
        const items: PublicDeadlineItem[] = indexed.get(date) ?? [];
        if (items.length >= CalendarDailyInfoSources.maximumItemsPerDay) {
          continue;
        }
        const label: string = CalendarResponseValues.firstString(deadlineRecord, ['label']) ??
          '截止时间';
        items.push(new PublicDeadlineItem(
          'school:' + id + ':' + index.toString(), name, PublicDeadlineKind.competition,
          PublicDeadlineSource.schoolNotice, deadline, sourceName + ' · ' + label, officialURL));
        indexed.set(date, items);
      }
    }
    indexed.forEach((items: PublicDeadlineItem[], date: string): void => {
      PublicDeadlineResponseParser.sortItems(items);
      indexed.set(date, items);
    });
    return indexed;
  }

  private static sortItems(items: PublicDeadlineItem[]): void {
    items.sort((lhs: PublicDeadlineItem, rhs: PublicDeadlineItem): number => {
      if (lhs.deadline !== rhs.deadline) {
        return lhs.deadline < rhs.deadline ? -1 : 1;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
  }

  static merge(groups: PublicDeadlineItem[][]): PublicDeadlineItem[] {
    const seen: Set<string> = new Set<string>();
    const result: PublicDeadlineItem[] = [];
    for (const group of groups) {
      for (const item of group) {
        const key: string = item.source + '\u001f' + item.kind + '\u001f' +
          item.name.trim().toLowerCase() +
          '\u001f' + item.deadline;
        if (!seen.has(key)) {
          seen.add(key);
          result.push(item);
        }
      }
    }
    result.sort((lhs: PublicDeadlineItem, rhs: PublicDeadlineItem): number => {
      if (lhs.deadline !== rhs.deadline) {
        return lhs.deadline < rhs.deadline ? -1 : 1;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    return result.slice(0, CalendarDailyInfoSources.maximumItemsPerDay);
  }

  private static extractRecords(root: Object): Object[] {
    if (Array.isArray(root)) {
      return root as Object[];
    }
    const source: Record<string, Object> = JsonUtil.record(root);
    for (const key of ['items', 'records', 'data']) {
      const direct: Object[] = JsonUtil.array(source[key]);
      if (direct.length > 0 || Array.isArray(source[key])) {
        return direct;
      }
      const nested: Record<string, Object> = JsonUtil.record(source[key]);
      for (const nestedKey of ['items', 'records']) {
        const records: Object[] = JsonUtil.array(nested[nestedKey]);
        if (records.length > 0 || Array.isArray(nested[nestedKey])) {
          return records;
        }
      }
    }
    return [];
  }

  private static isTrustedOfficialURL(value: string): boolean {
    if (!value.startsWith('https://')) {
      return false;
    }
    const rest: string = value.substring('https://'.length);
    const slash: number = rest.indexOf('/');
    const authority: string = slash < 0 ? rest : rest.substring(0, slash);
    return authority.length > 0 && authority.indexOf('@') < 0;
  }
}

export class AssignmentDeadlineResponseParser {
  private static readonly timestamp: RegExp = new RegExp(
    '^\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}(?::\\d{2})?(?:.*)?$');

  static parse(payload: string, requestedDate: string): AssignmentDeadlineItem[] {
    if (StrictDates.parseDateString(requestedDate) === null) {
      throw new CalendarDailyInfoError('作业日期格式不正确。');
    }
    const source: Record<string, Object> | null = JsonUtil.parseObject(payload);
    if (source === null) {
      throw new CalendarDailyInfoError('作业数据格式不正确。');
    }
    const allItems: AssignmentDeadlineItem[] =
      AssignmentDeadlineResponseParser.parseAll(source, null);
    const result: AssignmentDeadlineItem[] = [];
    for (const item of allItems) {
      if (item.deadline.startsWith(requestedDate)) {
        result.push(item);
      }
    }
    result.sort((lhs: AssignmentDeadlineItem, rhs: AssignmentDeadlineItem): number => {
      if (lhs.deadline !== rhs.deadline) {
        return lhs.deadline < rhs.deadline ? -1 : 1;
      }
      return lhs.title < rhs.title ? -1 : (lhs.title > rhs.title ? 1 : 0);
    });
    return result;
  }

  static parseAll(
    source: Record<string, Object>, courseNameOverride: string | null
  ): AssignmentDeadlineItem[] {
    const firstDataValue: Record<string, Object> = JsonUtil.record(source['data']);
    const firstData: Record<string, Object> = Object.keys(firstDataValue).length > 0 ? firstDataValue : source;
    const secondDataValue: Record<string, Object> = JsonUtil.record(firstData['data']);
    const secondData: Record<string, Object> = Object.keys(secondDataValue).length > 0 ?
      secondDataValue : firstData;
    let records: Object[] = JsonUtil.array(secondData['records']);
    if (!Array.isArray(secondData['records'])) {
      records = JsonUtil.array(secondData['undoneList']);
    }
    const result: AssignmentDeadlineItem[] = [];
    for (const raw of records) {
      const item: Record<string, Object> = JsonUtil.record(raw);
      if (item['type'] !== undefined) {
        const type: number = CalendarResponseValues.optionalNumber(item['type'], -1);
        if (type !== 3 && type !== 5) {
          continue;
        }
      }
      const deadline: string | null = CalendarResponseValues.firstString(
        item, ['assignmentEndTime', 'endTime']);
      const id: string | null = CalendarResponseValues.firstString(
        item, ['id', 'assignmentId', 'activityId']);
      const title: string | null = CalendarResponseValues.firstString(
        item, ['assignmentTitle', 'activityName', 'title']);
      if (deadline === null || id === null || title === null ||
        !AssignmentDeadlineResponseParser.timestamp.test(deadline)) {
        continue;
      }
      const embeddedCourseName: string | null = CalendarResponseValues.firstString(
        item, ['siteName', 'courseName', 'siteTitle']);
      const courseName: string | null = embeddedCourseName ??
        (courseNameOverride !== null && courseNameOverride.trim().length > 0 ?
          courseNameOverride.trim() : null);
      result.push(new AssignmentDeadlineItem(
        id, title, courseName,
        deadline, AssignmentDeadlineResponseParser.status(item['assignmentStatus'])));
    }
    return result;
  }

  private static status(value: Object | undefined): string | null {
    const numberValue: number = CalendarResponseValues.optionalNumber(value, -9999);
    if (numberValue === 99) {
      return '未提交';
    }
    if (numberValue === 0) {
      return '已提交';
    }
    if (numberValue === 1) {
      return '已批改';
    }
    if (numberValue === 2) {
      return '已驳回';
    }
    return typeof value === 'string' ? CalendarResponseValues.normalized(value as string) : null;
  }
}

export interface CalendarDailyInfoFetching {
  fetchAlmanac(date: string): Promise<AlmanacInfo>;
  fetchDeadlines(date: string): Promise<PublicDeadlineSnapshot>;
  prewarmDeadlines(date: string, forceRemote?: boolean): Promise<PublicDeadlineSnapshot>;
  fetchCustomDeadlines(url: string, date: string,
    forceRemote?: boolean, refreshStaleCache?: boolean): Promise<PublicDeadlineSnapshot>;
}

export interface FixedPublicJsonFetching {
  fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string>;
  fetchCustom(url: string, maximumBytes: number): Promise<string>;
}

class DefaultPublicJsonTransport implements FixedPublicJsonFetching {
  fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string> {
    return FixedPublicJsonTransport.fetch(url, scheme, host, maximumBytes);
  }

  fetchCustom(url: string, maximumBytes: number): Promise<string> {
    return FixedPublicJsonTransport.fetchCustom(url, maximumBytes);
  }
}

class DeadlineIndexBundle {
  readonly contestItemsByDate: Map<string, PublicDeadlineItem[]> | null;
  readonly contestSource: string;
  readonly usedBackup: boolean;
  readonly contestError: string | null;
  readonly schoolItemsByDate: Map<string, PublicDeadlineItem[]> | null;
  readonly schoolError: string | null;

  constructor(contestItemsByDate: Map<string, PublicDeadlineItem[]> | null,
    contestSource: string, usedBackup: boolean, contestError: string | null,
    schoolItemsByDate: Map<string, PublicDeadlineItem[]> | null, schoolError: string | null) {
    this.contestItemsByDate = contestItemsByDate;
    this.contestSource = contestSource;
    this.usedBackup = usedBackup;
    this.contestError = contestError;
    this.schoolItemsByDate = schoolItemsByDate;
    this.schoolError = schoolError;
  }
}

class DeadlineIndexCache {
  readonly fetchedAt: number;
  readonly bundle: DeadlineIndexBundle;

  constructor(fetchedAt: number, bundle: DeadlineIndexBundle) {
    this.fetchedAt = fetchedAt;
    this.bundle = bundle;
  }
}

export class CalendarDailyInfoClient implements CalendarDailyInfoFetching {
  private static readonly deadlineCacheLifetimeMs: number = 5 * 60 * 1000;
  private deadlineIndexCache: DeadlineIndexCache | null = null;
  private deadlineIndexInFlight: Promise<DeadlineIndexBundle> | null = null;
  private readonly customDeadlineCache: Map<string, DeadlineIndexCache> =
    new Map<string, DeadlineIndexCache>();
  private readonly customDeadlineInFlight: Map<string, Promise<DeadlineIndexBundle>> =
    new Map<string, Promise<DeadlineIndexBundle>>();
  private readonly transport: FixedPublicJsonFetching;
  private readonly parseContestIndex: (payload: string) => Map<string, PublicDeadlineItem[]>;
  private readonly parseSchoolIndex: (payload: string) => Map<string, PublicDeadlineItem[]>;

  constructor(transport: FixedPublicJsonFetching = new DefaultPublicJsonTransport(),
    parseContestIndex: (payload: string) => Map<string, PublicDeadlineItem[]> =
      (payload: string): Map<string, PublicDeadlineItem[]> =>
        PublicDeadlineResponseParser.parseIndex(payload),
    parseSchoolIndex: (payload: string) => Map<string, PublicDeadlineItem[]> =
      (payload: string): Map<string, PublicDeadlineItem[]> =>
        PublicDeadlineResponseParser.parseSchoolNoticesIndex(payload)) {
    this.transport = transport;
    this.parseContestIndex = parseContestIndex;
    this.parseSchoolIndex = parseSchoolIndex;
  }

  async fetchAlmanac(date: string): Promise<AlmanacInfo> {
    const target: DateParts | null = StrictDates.parseDateString(date);
    if (target === null) {
      throw new CalendarDailyInfoError('黄历日期格式不正确。');
    }
    // 当天上海时间 12:00 对应 UTC 04:00。
    const timestamp: number = StrictDates.epochDay(target.year, target.month, target.day) * 86400 + 4 * 3600;
    const basePayload: string = await this.transport.fetch(
      CalendarDailyInfoSources.uapiOrigin + '/api/v1/misc/lunartime?ts=' + timestamp.toString() +
        '&timezone=Asia%2FShanghai',
      'https', 'uapis.cn', CalendarDailyInfoSources.smallPayloadLimit);
    const base: AlmanacInfo = AlmanacResponseParser.parseBase(basePayload, date);
    try {
      const advicePayload: string = await this.transport.fetch(
        CalendarDailyInfoSources.timelessOrigin + '/time?datetime=' + date,
        'https', 'api.timelessq.com', CalendarDailyInfoSources.smallPayloadLimit);
      const advice: string[] = AlmanacResponseParser.parseAdvice(advicePayload, date);
      return base.withAdvice(advice[0], advice[1]);
    } catch (e) {
      // 宜忌是增强信息；增强源不可用时仍展示 UAPI 的基础黄历。
      return base;
    }
  }

  async fetchDeadlines(date: string): Promise<PublicDeadlineSnapshot> {
    if (StrictDates.parseDateString(date) === null) {
      throw new CalendarDailyInfoError('DDL 日期格式不正确。');
    }
    const bundle: DeadlineIndexBundle = await this.deadlineIndexes(false, false);
    return this.snapshotFromBundle(date, bundle);
  }

  async prewarmDeadlines(date: string, forceRemote: boolean = false): Promise<PublicDeadlineSnapshot> {
    if (StrictDates.parseDateString(date) === null) {
      throw new CalendarDailyInfoError('DDL 日期格式不正确。');
    }
    const bundle: DeadlineIndexBundle = await this.deadlineIndexes(forceRemote, true);
    return this.snapshotFromBundle(date, bundle);
  }

  async fetchCustomDeadlines(url: string, date: string,
    forceRemote: boolean = false, refreshStaleCache: boolean = false):
    Promise<PublicDeadlineSnapshot> {
    if (StrictDates.parseDateString(date) === null) {
      throw new CalendarDailyInfoError('自定义日程日期格式不正确。');
    }
    if (!CustomDeadlineURLPolicy.allows(url)) {
      throw new CalendarDailyInfoError('自定义日程只允许公开、无凭据的 HTTPS URL。');
    }
    const cached: DeadlineIndexCache | undefined = this.customDeadlineCache.get(url);
    if (!forceRemote && cached !== undefined &&
      (!refreshStaleCache ||
        Date.now() - cached.fetchedAt < CalendarDailyInfoClient.deadlineCacheLifetimeMs)) {
      const items: PublicDeadlineItem[] = cached.bundle.contestItemsByDate?.get(date) ?? [];
      return new PublicDeadlineSnapshot(date, items, url, false);
    }
    let work: Promise<DeadlineIndexBundle> | undefined = this.customDeadlineInFlight.get(url);
    if (work === undefined) {
      work = (async (): Promise<DeadlineIndexBundle> => {
        const payload: string = await this.transport.fetchCustom(
          url, CalendarDailyInfoSources.deadlinePayloadLimit);
        const index: Map<string, PublicDeadlineItem[]> =
          PublicDeadlineResponseParser.parseCustomIndex(payload, url);
        return new DeadlineIndexBundle(
          index, url, false, null, new Map<string, PublicDeadlineItem[]>(), null);
      })();
      this.customDeadlineInFlight.set(url, work);
    }
    try {
      const bundle: DeadlineIndexBundle = await work;
      this.customDeadlineCache.set(url, new DeadlineIndexCache(Date.now(), bundle));
      return new PublicDeadlineSnapshot(
        date, bundle.contestItemsByDate?.get(date) ?? [], url, false);
    } finally {
      if (this.customDeadlineInFlight.get(url) === work) {
        this.customDeadlineInFlight.delete(url);
      }
    }
  }

  private snapshotFromBundle(date: string, bundle: DeadlineIndexBundle): PublicDeadlineSnapshot {
    const contestItems: PublicDeadlineItem[] | null = bundle.contestItemsByDate === null ? null :
      (bundle.contestItemsByDate.get(date) ?? []);
    const schoolItems: PublicDeadlineItem[] | null = bundle.schoolItemsByDate === null ? null :
      (bundle.schoolItemsByDate.get(date) ?? []);
    if (contestItems === null && schoolItems === null) {
      throw new CalendarDailyInfoError(
        '公开活动 DDL 不可用（' + (bundle.contestError ?? '未知错误') +
          '）；校内竞赛通知也不可用（' + (bundle.schoolError ?? '未知错误') + '）。');
    }
    if (contestItems === null) {
      return new PublicDeadlineSnapshot(
        date, schoolItems ?? [], CalendarDailyInfoSources.schoolContestNotices, false);
    }
    if (schoolItems === null) {
      return new PublicDeadlineSnapshot(
        date, contestItems, bundle.contestSource, bundle.usedBackup);
    }
    return new PublicDeadlineSnapshot(
      date, PublicDeadlineResponseParser.merge([contestItems, schoolItems]),
      bundle.contestSource, bundle.usedBackup);
  }

  private async deadlineIndexes(forceRemote: boolean,
    refreshStaleCache: boolean): Promise<DeadlineIndexBundle> {
    const now: number = Date.now();
    if (!forceRemote && this.deadlineIndexCache !== null &&
      (!refreshStaleCache ||
        now - this.deadlineIndexCache.fetchedAt < CalendarDailyInfoClient.deadlineCacheLifetimeMs)) {
      return this.deadlineIndexCache.bundle;
    }
    if (this.deadlineIndexInFlight !== null) {
      return await this.deadlineIndexInFlight;
    }
    const work: Promise<DeadlineIndexBundle> = this.fetchDeadlineIndexes();
    this.deadlineIndexInFlight = work;
    try {
      const result: DeadlineIndexBundle = await work;
      this.deadlineIndexCache = new DeadlineIndexCache(Date.now(), result);
      return result;
    } finally {
      if (this.deadlineIndexInFlight === work) {
        this.deadlineIndexInFlight = null;
      }
    }
  }

  private async fetchDeadlineIndexes(): Promise<DeadlineIndexBundle> {
    let contestItemsByDate: Map<string, PublicDeadlineItem[]> | null = null;
    let contestSource: string = CalendarDailyInfoSources.deadlinePrimary;
    let usedBackup: boolean = false;
    let contestError: string | null = null;
    try {
      const payload: string = await this.transport.fetch(
        CalendarDailyInfoSources.deadlinePrimary, 'https', 'nemoyuzx.github.io',
        CalendarDailyInfoSources.deadlinePayloadLimit);
      contestItemsByDate = this.parseContestIndex(payload);
    } catch (primaryError) {
      try {
        const payload: string = await this.transport.fetch(
          CalendarDailyInfoSources.deadlineBackup, 'http', '101.201.29.29',
          CalendarDailyInfoSources.deadlinePayloadLimit);
        contestItemsByDate = this.parseContestIndex(payload);
        contestSource = CalendarDailyInfoSources.deadlineBackup;
        usedBackup = true;
      } catch (backupError) {
        const primaryMessage: string = primaryError instanceof Error ? primaryError.message : '未知错误';
        const backupMessage: string = backupError instanceof Error ? backupError.message : '未知错误';
        contestError = '主 DDL 数据源不可用（' + primaryMessage + '）；备用数据源也不可用（' +
          backupMessage + '）。';
      }
    }
    let schoolItemsByDate: Map<string, PublicDeadlineItem[]> | null = null;
    let schoolError: string | null = null;
    try {
      const payload: string = await this.transport.fetch(
        CalendarDailyInfoSources.schoolContestNotices, 'http', '101.201.29.29',
        CalendarDailyInfoSources.deadlinePayloadLimit);
      schoolItemsByDate = this.parseSchoolIndex(payload);
    } catch (error) {
      schoolError = error instanceof Error ? error.message : '未知错误';
    }
    if (contestItemsByDate === null && schoolItemsByDate === null) {
      throw new CalendarDailyInfoError(
        '公开活动 DDL 不可用（' + (contestError ?? '未知错误') + '）；校内竞赛通知也不可用（' +
          (schoolError ?? '未知错误') + '）。');
    }
    return new DeadlineIndexBundle(
      contestItemsByDate, contestSource, usedBackup, contestError, schoolItemsByDate, schoolError);
  }
}

export class CustomDeadlineURLPolicy {
  static allows(url: string): boolean {
    if (!url.startsWith('https://') || url.indexOf('#') >= 0) {
      return false;
    }
    const rest: string = url.substring('https://'.length);
    let authorityEnd: number = rest.length;
    for (const separator of ['/', '?']) {
      const index: number = rest.indexOf(separator);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }
    const authority: string = rest.substring(0, authorityEnd);
    if (authority.length === 0 || authority.indexOf('@') >= 0 || authority.startsWith('[')) {
      return false;
    }
    const colon: number = authority.lastIndexOf(':');
    const host: string = (colon < 0 ? authority : authority.substring(0, colon))
      .replace(/\.$/, '').toLowerCase();
    if (host.length === 0 || host === 'localhost' || host.endsWith('.localhost')) {
      return false;
    }
    if (colon >= 0) {
      const port: number = Number(authority.substring(colon + 1));
      if (!Number.isInteger(port) || port < 1 || port > 65535) {
        return false;
      }
    }
    const parts: string[] = host.split('.');
    if (parts.length === 4 && parts.every((part: string): boolean => /^\d+$/.test(part))) {
      const octets: number[] = parts.map((part: string): number => Number(part));
      if (octets.some((value: number): boolean => value < 0 || value > 255)) {
        return false;
      }
      const first: number = octets[0];
      const second: number = octets[1];
      const third: number = octets[2];
      return !(first === 0 || first === 10 || first === 127 || first >= 224 ||
        (first === 100 && second >= 64 && second <= 127) ||
        (first === 169 && second === 254) ||
        (first === 172 && second >= 16 && second <= 31) ||
        (first === 192 && (second === 0 || second === 168)) ||
        (first === 198 && (second === 18 || second === 19 || (second === 51 && third === 100))) ||
        (first === 203 && second === 0 && third === 113));
    }
    return host.indexOf('.') > 0 && host.indexOf(' ') < 0;
  }
}

class FixedPublicJsonTransport {
  static async fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string> {
    if (!FixedPublicJsonTransport.allows(url, scheme, host)) {
      throw new CalendarDailyInfoError('公开数据源地址不受信任。');
    }
    return FixedPublicJsonTransport.request(url, maximumBytes);
  }

  static async fetchCustom(url: string, maximumBytes: number): Promise<string> {
    if (!CustomDeadlineURLPolicy.allows(url)) {
      throw new CalendarDailyInfoError('自定义日程只允许公开、无凭据的 HTTPS URL。');
    }
    return FixedPublicJsonTransport.request(url, maximumBytes);
  }

  private static async request(url: string, maximumBytes: number): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': AppMeta.holidayUserAgent
        },
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxRedirects: 0
      });
      const status: number = typeof response.responseCode === 'number' ?
        response.responseCode as number : 0;
      if (status >= 300 && status <= 399) {
        throw new CalendarDailyInfoError('公开数据源返回了不受信任的重定向。');
      }
      if (status < 200 || status > 299) {
        throw new CalendarDailyInfoError('公开数据源返回错误，HTTP ' + status.toString() + '。');
      }
      return FixedPublicJsonTransport.responseBody(response.result, maximumBytes);
    } catch (e) {
      if (e instanceof CalendarDailyInfoError) {
        throw e;
      }
      throw new CalendarDailyInfoError('无法连接公开数据源，请检查网络后重试。');
    } finally {
      client.destroy();
    }
  }

  private static allows(url: string, scheme: string, host: string): boolean {
    const prefix: string = scheme + '://';
    if (!url.startsWith(prefix)) {
      return false;
    }
    const rest: string = url.substring(prefix.length);
    const slash: number = rest.indexOf('/');
    const authority: string = slash < 0 ? rest : rest.substring(0, slash);
    if (authority.indexOf('@') >= 0) {
      return false;
    }
    const colon: number = authority.indexOf(':');
    const parsedHost: string = (colon < 0 ? authority : authority.substring(0, colon)).toLowerCase();
    if (parsedHost !== host.toLowerCase()) {
      return false;
    }
    const defaultPort: number = scheme === 'https' ? 443 : 80;
    const port: number = colon < 0 ? defaultPort : Number(authority.substring(colon + 1));
    return port === defaultPort;
  }

  private static responseBody(result: Object | undefined, maximumBytes: number): string {
    if (result instanceof ArrayBuffer) {
      if (result.byteLength > maximumBytes) {
        throw new CalendarDailyInfoError('公开数据响应过大。');
      }
      return new util.TextDecoder('utf-8').decode(new Uint8Array(result));
    }
    if (typeof result === 'string') {
      if (Utf8.bytes(result as string).length > maximumBytes) {
        throw new CalendarDailyInfoError('公开数据响应过大。');
      }
      return result as string;
    }
    throw new CalendarDailyInfoError('公开数据响应为空。');
  }
}

class CalendarResponseValues {
  static normalized(value: string): string | null {
    const normalized: string = value.trim();
    return normalized.length > 0 ? normalized : null;
  }

  static optionalString(source: Record<string, Object>, key: string): string | null {
    const raw: Object | undefined = source[key];
    if (typeof raw === 'string') {
      return CalendarResponseValues.normalized(raw as string);
    }
    if (typeof raw === 'number') {
      return (raw as number).toString();
    }
    return null;
  }

  static requiredString(source: Record<string, Object>, key: string, message: string): string {
    const value: string | null = CalendarResponseValues.optionalString(source, key);
    if (value === null) {
      throw new CalendarDailyInfoError(message);
    }
    return value;
  }

  static firstString(source: Record<string, Object>, keys: string[]): string | null {
    for (const key of keys) {
      const value: string | null = CalendarResponseValues.optionalString(source, key);
      if (value !== null) {
        return value;
      }
    }
    return null;
  }

  static optionalNumber(value: Object | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return value as number;
    }
    if (typeof value === 'string') {
      const parsed: number = Number(value as string);
      return Number.isFinite(parsed) ? parsed : fallback;
    }
    return fallback;
  }
}
