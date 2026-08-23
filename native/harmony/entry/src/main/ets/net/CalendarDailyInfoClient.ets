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
  hackathon = 'hackathon'
}

export enum PublicDeadlineSource {
  contestDDL = 'contest_ddl',
  schoolNotice = 'school_notice'
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
    return null;
  }

  static title(kind: PublicDeadlineKind): string {
    if (kind === PublicDeadlineKind.competition) {
      return '学科竞赛';
    }
    if (kind === PublicDeadlineKind.summerCamp) {
      return '夏令营';
    }
    return '黑客松';
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

  constructor(id: string, name: string, kind: PublicDeadlineKind,
    source: PublicDeadlineSource, deadline: string,
    organizer: string | null, officialURL: string | null) {
    this.id = id;
    this.name = name;
    this.kind = kind;
    this.source = source;
    this.deadline = deadline;
    this.organizer = organizer;
    this.officialURL = officialURL;
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
    let root: Object;
    try {
      root = JSON.parse(payload) as Object;
    } catch (e) {
      throw new CalendarDailyInfoError('DDL 数据格式不正确。');
    }
    const records: Object[] = PublicDeadlineResponseParser.extractRecords(root);
    const result: PublicDeadlineItem[] = [];
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
        !deadline.startsWith(requestedDate) ||
        !PublicDeadlineResponseParser.rfc3339.test(deadline)) {
        continue;
      }
      const rawURL: string | null = CalendarResponseValues.firstString(
        record, ['official_url', 'officialUrl', 'url']);
      const officialURL: string | null = rawURL !== null &&
        PublicDeadlineResponseParser.isTrustedOfficialURL(rawURL) ? rawURL : null;
      result.push(new PublicDeadlineItem(
        id, name, kind, PublicDeadlineSource.contestDDL, deadline,
        CalendarResponseValues.firstString(record, ['organizer', 'host']), officialURL));
      if (result.length >= CalendarDailyInfoSources.maximumItemsPerDay) {
        break;
      }
    }
    result.sort((lhs: PublicDeadlineItem, rhs: PublicDeadlineItem): number => {
      if (lhs.deadline !== rhs.deadline) {
        return lhs.deadline < rhs.deadline ? -1 : 1;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    return result;
  }

  static parseSchoolNotices(payload: string, requestedDate: string): PublicDeadlineItem[] {
    if (StrictDates.parseDateString(requestedDate) === null) {
      throw new CalendarDailyInfoError('DDL 日期格式不正确。');
    }
    let root: Object;
    try {
      root = JSON.parse(payload) as Object;
    } catch (e) {
      throw new CalendarDailyInfoError('校内竞赛通知格式不正确。');
    }
    const source: Record<string, Object> = JsonUtil.record(root);
    const records: Object[] = JsonUtil.array(source['items']);
    const result: PublicDeadlineItem[] = [];
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
        if (deadline === null || !deadline.startsWith(requestedDate) ||
          !PublicDeadlineResponseParser.rfc3339.test(deadline)) {
          continue;
        }
        const label: string = CalendarResponseValues.firstString(deadlineRecord, ['label']) ??
          '截止时间';
        result.push(new PublicDeadlineItem(
          'school:' + id + ':' + index.toString(), name, PublicDeadlineKind.competition,
          PublicDeadlineSource.schoolNotice, deadline, sourceName + ' · ' + label, officialURL));
        if (result.length >= CalendarDailyInfoSources.maximumItemsPerDay) {
          break;
        }
      }
      if (result.length >= CalendarDailyInfoSources.maximumItemsPerDay) {
        break;
      }
    }
    result.sort((lhs: PublicDeadlineItem, rhs: PublicDeadlineItem): number => {
      if (lhs.deadline !== rhs.deadline) {
        return lhs.deadline < rhs.deadline ? -1 : 1;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    return result;
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
}

export interface FixedPublicJsonFetching {
  fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string>;
}

class DefaultPublicJsonTransport implements FixedPublicJsonFetching {
  fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string> {
    return FixedPublicJsonTransport.fetch(url, scheme, host, maximumBytes);
  }
}

class DeadlinePayloadBundle {
  readonly contestPayload: string | null;
  readonly contestSource: string;
  readonly usedBackup: boolean;
  readonly contestError: string | null;
  readonly schoolPayload: string | null;
  readonly schoolError: string | null;

  constructor(contestPayload: string | null, contestSource: string, usedBackup: boolean,
    contestError: string | null, schoolPayload: string | null, schoolError: string | null) {
    this.contestPayload = contestPayload;
    this.contestSource = contestSource;
    this.usedBackup = usedBackup;
    this.contestError = contestError;
    this.schoolPayload = schoolPayload;
    this.schoolError = schoolError;
  }
}

class DeadlinePayloadCache {
  readonly fetchedAt: number;
  readonly bundle: DeadlinePayloadBundle;

  constructor(fetchedAt: number, bundle: DeadlinePayloadBundle) {
    this.fetchedAt = fetchedAt;
    this.bundle = bundle;
  }
}

export class CalendarDailyInfoClient implements CalendarDailyInfoFetching {
  private static readonly deadlineCacheLifetimeMs: number = 10 * 60 * 1000;
  private deadlinePayloadCache: DeadlinePayloadCache | null = null;
  private deadlinePayloadInFlight: Promise<DeadlinePayloadBundle> | null = null;
  private readonly transport: FixedPublicJsonFetching;

  constructor(transport: FixedPublicJsonFetching = new DefaultPublicJsonTransport()) {
    this.transport = transport;
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
    const bundle: DeadlinePayloadBundle = await this.deadlinePayloads(date);
    const contestItems: PublicDeadlineItem[] | null = bundle.contestPayload === null ? null :
      PublicDeadlineResponseParser.parse(bundle.contestPayload, date);
    const schoolItems: PublicDeadlineItem[] | null = bundle.schoolPayload === null ? null :
      PublicDeadlineResponseParser.parseSchoolNotices(bundle.schoolPayload, date);
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

  private async deadlinePayloads(validationDate: string): Promise<DeadlinePayloadBundle> {
    const now: number = Date.now();
    if (this.deadlinePayloadCache !== null &&
      now - this.deadlinePayloadCache.fetchedAt < CalendarDailyInfoClient.deadlineCacheLifetimeMs) {
      return this.deadlinePayloadCache.bundle;
    }
    if (this.deadlinePayloadInFlight !== null) {
      return await this.deadlinePayloadInFlight;
    }
    const work: Promise<DeadlinePayloadBundle> = this.fetchDeadlinePayloads(validationDate);
    this.deadlinePayloadInFlight = work;
    try {
      const result: DeadlinePayloadBundle = await work;
      this.deadlinePayloadCache = new DeadlinePayloadCache(Date.now(), result);
      return result;
    } finally {
      if (this.deadlinePayloadInFlight === work) {
        this.deadlinePayloadInFlight = null;
      }
    }
  }

  private async fetchDeadlinePayloads(validationDate: string): Promise<DeadlinePayloadBundle> {
    let contestPayload: string | null = null;
    let contestSource: string = CalendarDailyInfoSources.deadlinePrimary;
    let usedBackup: boolean = false;
    let contestError: string | null = null;
    try {
      const payload: string = await this.transport.fetch(
        CalendarDailyInfoSources.deadlinePrimary, 'https', 'nemoyuzx.github.io',
        CalendarDailyInfoSources.deadlinePayloadLimit);
      PublicDeadlineResponseParser.parse(payload, validationDate);
      contestPayload = payload;
    } catch (primaryError) {
      try {
        const payload: string = await this.transport.fetch(
          CalendarDailyInfoSources.deadlineBackup, 'http', '101.201.29.29',
          CalendarDailyInfoSources.deadlinePayloadLimit);
        PublicDeadlineResponseParser.parse(payload, validationDate);
        contestPayload = payload;
        contestSource = CalendarDailyInfoSources.deadlineBackup;
        usedBackup = true;
      } catch (backupError) {
        const primaryMessage: string = primaryError instanceof Error ? primaryError.message : '未知错误';
        const backupMessage: string = backupError instanceof Error ? backupError.message : '未知错误';
        contestError = '主 DDL 数据源不可用（' + primaryMessage + '）；备用数据源也不可用（' +
          backupMessage + '）。';
      }
    }
    let schoolPayload: string | null = null;
    let schoolError: string | null = null;
    try {
      const payload: string = await this.transport.fetch(
        CalendarDailyInfoSources.schoolContestNotices, 'http', '101.201.29.29',
        CalendarDailyInfoSources.deadlinePayloadLimit);
      PublicDeadlineResponseParser.parseSchoolNotices(payload, validationDate);
      schoolPayload = payload;
    } catch (error) {
      schoolError = error instanceof Error ? error.message : '未知错误';
    }
    if (contestPayload === null && schoolPayload === null) {
      throw new CalendarDailyInfoError(
        '公开活动 DDL 不可用（' + (contestError ?? '未知错误') + '）；校内竞赛通知也不可用（' +
          (schoolError ?? '未知错误') + '）。');
    }
    return new DeadlinePayloadBundle(
      contestPayload, contestSource, usedBackup, contestError, schoolPayload, schoolError);
  }
}

class FixedPublicJsonTransport {
  static async fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string> {
    if (!FixedPublicJsonTransport.allows(url, scheme, host)) {
      throw new CalendarDailyInfoError('公开数据源地址不受信任。');
    }
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
