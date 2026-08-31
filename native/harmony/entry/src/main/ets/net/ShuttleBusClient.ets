// 校区班车公开查询客户端。
// 数据源固定为 Where To Study 服务端整理的北京邮电大学后勤部公开通知；
// 客户端只展示通过服务端严格校验的结构化班次，不对低置信度 OCR 结果进行猜测。
import { HttpRequestSpec, HttpResult, HttpUtil } from './HttpUtil';
import { JsonUtil } from '../common/JsonUtil';
import { DateParts, SHANGHAI_OFFSET_MS, StrictDates } from '../common/StrictDates';

export class ShuttleBusSources {
  static readonly endpoint: string = 'https://where-to-study.cn/api/shuttle-bus';
  static readonly sourcePage: string = 'https://hq.bupt.edu.cn/tzgg.htm';
  static readonly maximumPayloadBytes: number = 2 * 1024 * 1024;
}

export enum ShuttleBusPeriodState {
  active = 'active',
  upcoming = 'upcoming',
  ended = 'ended',
  inactive = 'inactive',
  unknown = 'unknown'
}

export class ShuttleBusService {
  readonly vehicle: string;
  readonly count: number;

  constructor(vehicle: string, count: number) {
    this.vehicle = vehicle;
    this.count = count;
  }
}

export class ShuttleBusRow {
  readonly departureTime: string;
  readonly services: Map<string, ShuttleBusService>;

  constructor(departureTime: string, services: Map<string, ShuttleBusService>) {
    this.departureTime = departureTime;
    this.services = services;
  }
}

export class ShuttleBusPeriod {
  readonly label: string;
  readonly startDate: string | null;
  readonly endDate: string | null;

  constructor(label: string, startDate: string | null, endDate: string | null) {
    this.label = label;
    this.startDate = startDate;
    this.endDate = endDate;
  }

  key(): string {
    return (this.startDate ?? '') + '\u001f' + (this.endDate ?? '') + '\u001f' + this.label;
  }
}

export class ShuttleBusSchedule {
  readonly period: ShuttleBusPeriod;
  readonly from: string;
  readonly to: string;
  readonly rows: ShuttleBusRow[];

  constructor(period: ShuttleBusPeriod, from: string, to: string, rows: ShuttleBusRow[]) {
    this.period = period;
    this.from = from;
    this.to = to;
    this.rows = rows;
  }
}

export class ShuttleBusStop {
  readonly campus: string;
  readonly location: string;

  constructor(campus: string, location: string) {
    this.campus = campus;
    this.location = location;
  }
}

export class ShuttleBusNotice {
  readonly id: string;
  readonly title: string;
  readonly publishedAt: string;
  readonly sourceURL: string | null;
  readonly schedules: ShuttleBusSchedule[];
  readonly stops: ShuttleBusStop[];
  readonly notes: string[];

  constructor(id: string, title: string, publishedAt: string, sourceURL: string | null,
    schedules: ShuttleBusSchedule[], stops: ShuttleBusStop[], notes: string[]) {
    this.id = id;
    this.title = title;
    this.publishedAt = publishedAt;
    this.sourceURL = sourceURL;
    this.schedules = schedules;
    this.stops = stops;
    this.notes = notes;
  }

  stopLocation(campus: string): string | null {
    for (const stop of this.stops) {
      if (stop.campus === campus) {
        return stop.location;
      }
    }
    return null;
  }
}

export class ShuttleBusSnapshot {
  readonly generatedAt: string;
  readonly status: string;
  readonly notices: ShuttleBusNotice[];
  readonly lastParsedNoticeID: string | null;

  constructor(generatedAt: string, status: string, notices: ShuttleBusNotice[],
    lastParsedNoticeID: string | null) {
    this.generatedAt = generatedAt;
    this.status = status;
    this.notices = notices;
    this.lastParsedNoticeID = lastParsedNoticeID;
  }
}

export class ShuttleBusDailyView {
  readonly date: string;
  readonly weekdayKey: string;
  readonly state: ShuttleBusPeriodState;
  readonly period: ShuttleBusPeriod | null;
  readonly schedules: ShuttleBusSchedule[];
  readonly latestNotice: ShuttleBusNotice | null;
  readonly scheduleNotice: ShuttleBusNotice | null;
  readonly usingFallback: boolean;

  constructor(date: string, weekdayKey: string, state: ShuttleBusPeriodState,
    period: ShuttleBusPeriod | null, schedules: ShuttleBusSchedule[],
    latestNotice: ShuttleBusNotice | null, scheduleNotice: ShuttleBusNotice | null,
    usingFallback: boolean) {
    this.date = date;
    this.weekdayKey = weekdayKey;
    this.state = state;
    this.period = period;
    this.schedules = schedules;
    this.latestNotice = latestNotice;
    this.scheduleNotice = scheduleNotice;
    this.usingFallback = usingFallback;
  }
}

export class ShuttleBusResponseParser {
  private static readonly clock: RegExp = new RegExp('^(?:[01]\\d|2[0-3]):[0-5]\\d$');
  private static readonly weekdays: string[] = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
  ];

  static parse(payload: string): ShuttleBusSnapshot {
    const root: Record<string, Object> | null = JsonUtil.parseObject(payload);
    if (root === null || JsonUtil.string(root['schema_version']) !== '1.0') {
      throw new Error('班车数据格式不正确。');
    }
    const generatedAt: string = JsonUtil.string(root['generated_at']);
    const status: string = JsonUtil.string(root['status']);
    const lastParsedNoticeIDValue: string = JsonUtil.string(root['last_parsed_notice_id']);
    const notices: ShuttleBusNotice[] = [];
    const rawItems: Object[] = JsonUtil.array(root['items']);
    for (let index: number = 0; index < rawItems.length && notices.length < 60; index += 1) {
      const notice: ShuttleBusNotice | null = ShuttleBusResponseParser.notice(rawItems[index]);
      if (notice !== null) {
        notices.push(notice);
      }
    }
    if (notices.length === 0) {
      throw new Error('班车数据中没有有效通知。');
    }
    return new ShuttleBusSnapshot(generatedAt, status, notices,
      lastParsedNoticeIDValue.length > 0 ? lastParsedNoticeIDValue : null);
  }

  private static notice(raw: Object): ShuttleBusNotice | null {
    const record: Record<string, Object> = JsonUtil.record(raw);
    const id: string = JsonUtil.string(record['id']).trim();
    const title: string = JsonUtil.string(record['title']).trim();
    const publishedAt: string = JsonUtil.string(record['published_at']).trim();
    if (id.length === 0 || title.length === 0 || StrictDates.parseDateString(publishedAt) === null) {
      return null;
    }
    const schedules: ShuttleBusSchedule[] = [];
    const rawSchedules: Object[] = JsonUtil.array(record['schedules']);
    for (let index: number = 0; index < rawSchedules.length && schedules.length < 20; index += 1) {
      const schedule: ShuttleBusSchedule | null = ShuttleBusResponseParser.schedule(rawSchedules[index]);
      if (schedule !== null) {
        schedules.push(schedule);
      }
    }
    const stops: ShuttleBusStop[] = [];
    for (const rawStop of JsonUtil.array(record['stops'])) {
      const stop: Record<string, Object> = JsonUtil.record(rawStop);
      const campus: string = JsonUtil.string(stop['campus']).trim();
      const location: string = JsonUtil.string(stop['location']).trim();
      if (campus.length > 0 && location.length > 0 && stops.length < 12) {
        stops.push(new ShuttleBusStop(campus, location));
      }
    }
    const notes: string[] = [];
    for (const rawNote of JsonUtil.array(record['notes'])) {
      if (typeof rawNote === 'string') {
        const note: string = (rawNote as string).trim();
        if (note.length > 0 && notes.length < 12) {
          notes.push(note);
        }
      }
    }
    const rawURL: string = JsonUtil.string(record['source_url']).trim();
    const sourceURL: string | null = rawURL.startsWith('https://hq.bupt.edu.cn/') ? rawURL : null;
    return new ShuttleBusNotice(id, title, publishedAt, sourceURL, schedules, stops, notes);
  }

  private static schedule(raw: Object): ShuttleBusSchedule | null {
    const record: Record<string, Object> = JsonUtil.record(raw);
    if (JsonUtil.string(record['parse_status']) !== 'parsed') {
      return null;
    }
    const from: string = JsonUtil.string(record['from']).trim();
    const to: string = JsonUtil.string(record['to']).trim();
    const periodRecord: Record<string, Object> = JsonUtil.record(record['period']);
    const label: string = JsonUtil.string(periodRecord['label']).trim();
    const startValue: string = JsonUtil.string(periodRecord['start_date']).trim();
    const endValue: string = JsonUtil.string(periodRecord['end_date']).trim();
    const startDate: string | null = StrictDates.parseDateString(startValue) === null ? null : startValue;
    const endDate: string | null = StrictDates.parseDateString(endValue) === null ? null : endValue;
    if (from.length === 0 || to.length === 0 || label.length === 0) {
      return null;
    }
    const rows: ShuttleBusRow[] = [];
    const rawRows: Object[] = JsonUtil.array(record['rows']);
    for (let index: number = 0; index < rawRows.length && rows.length < 80; index += 1) {
      const rowRecord: Record<string, Object> = JsonUtil.record(rawRows[index]);
      const departure: string = JsonUtil.string(rowRecord['departure_time']).trim();
      if (!ShuttleBusResponseParser.clock.test(departure)) {
        continue;
      }
      const rawServices: Record<string, Object> = JsonUtil.record(rowRecord['services']);
      const services: Map<string, ShuttleBusService> = new Map<string, ShuttleBusService>();
      for (const weekday of ShuttleBusResponseParser.weekdays) {
        const serviceRecord: Record<string, Object> = JsonUtil.record(rawServices[weekday]);
        const vehicle: string = JsonUtil.string(serviceRecord['vehicle']).trim();
        const count: number = JsonUtil.number(serviceRecord['count'], 0);
        if (vehicle.length > 0 && Number.isInteger(count) && count > 0 && count <= 20) {
          services.set(weekday, new ShuttleBusService(vehicle, count));
        }
      }
      rows.push(new ShuttleBusRow(departure, services));
    }
    rows.sort((left: ShuttleBusRow, right: ShuttleBusRow): number =>
      left.departureTime < right.departureTime ? -1 :
        (left.departureTime > right.departureTime ? 1 : 0));
    if (rows.length === 0) {
      return null;
    }
    return new ShuttleBusSchedule(
      new ShuttleBusPeriod(label, startDate, endDate), from, to, rows);
  }
}

export class ShuttleBusLogic {
  private static readonly weekdayKeys: string[] = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
  ];

  static dailyView(snapshot: ShuttleBusSnapshot,
    today: DateParts = StrictDates.todayParts()): ShuttleBusDailyView {
    const date: string = StrictDates.formatDateParts(today);
    const weekdayKey: string = ShuttleBusLogic.weekdayKeys[StrictDates.weekdayMonday1(today) - 1];
    const latest: ShuttleBusNotice | null = snapshot.notices.length > 0 ? snapshot.notices[0] : null;
    let scheduleNotice: ShuttleBusNotice | null = null;
    if (snapshot.lastParsedNoticeID !== null) {
      for (const notice of snapshot.notices) {
        if (notice.id === snapshot.lastParsedNoticeID && notice.schedules.length > 0) {
          scheduleNotice = notice;
          break;
        }
      }
    }
    if (scheduleNotice === null) {
      for (const notice of snapshot.notices) {
        if (notice.schedules.length > 0) {
          scheduleNotice = notice;
          break;
        }
      }
    }
    if (scheduleNotice === null) {
      return new ShuttleBusDailyView(date, weekdayKey, ShuttleBusPeriodState.unknown,
        null, [], latest, null, false);
    }
    const periods: ShuttleBusPeriod[] = [];
    const seen: Set<string> = new Set<string>();
    for (const schedule of scheduleNotice.schedules) {
      const key: string = schedule.period.key();
      if (!seen.has(key)) {
        seen.add(key);
        periods.push(schedule.period);
      }
    }
    const selected: ShuttleBusPeriod | null = ShuttleBusLogic.activePeriod(periods, date);
    if (selected === null) {
      return new ShuttleBusDailyView(date, weekdayKey, ShuttleBusPeriodState.inactive,
        null, [], latest, scheduleNotice, latest !== null && latest.id !== scheduleNotice.id);
    }
    const schedules: ShuttleBusSchedule[] = scheduleNotice.schedules.filter(
      (schedule: ShuttleBusSchedule): boolean => schedule.period.key() === selected.key());
    return new ShuttleBusDailyView(date, weekdayKey, ShuttleBusLogic.periodState(selected, date),
      selected, schedules, latest, scheduleNotice,
      latest !== null && latest.id !== scheduleNotice.id);
  }

  static servicesForToday(schedule: ShuttleBusSchedule,
    weekdayKey: string): ShuttleBusRow[] {
    return schedule.rows.filter((row: ShuttleBusRow): boolean => row.services.has(weekdayKey));
  }

  static nextDepartureIndex(rows: ShuttleBusRow[], state: ShuttleBusPeriodState,
    nowMinutes: number = ShuttleBusLogic.shanghaiClockMinutes()): number {
    if (state !== ShuttleBusPeriodState.active) {
      return -1;
    }
    for (let index: number = 0; index < rows.length; index += 1) {
      const minutes: number = ShuttleBusLogic.departureMinutes(rows[index].departureTime);
      if (minutes > nowMinutes) {
        return index;
      }
    }
    return -1;
  }

  static periodState(period: ShuttleBusPeriod, date: string): ShuttleBusPeriodState {
    if (period.startDate !== null && date < period.startDate) {
      return ShuttleBusPeriodState.upcoming;
    }
    if (period.endDate !== null && date > period.endDate) {
      return ShuttleBusPeriodState.ended;
    }
    if (period.startDate !== null && date >= period.startDate &&
      (period.endDate === null || date <= period.endDate)) {
      return ShuttleBusPeriodState.active;
    }
    return ShuttleBusPeriodState.unknown;
  }

  private static activePeriod(periods: ShuttleBusPeriod[], date: string): ShuttleBusPeriod | null {
    for (const period of periods) {
      if (ShuttleBusLogic.periodState(period, date) === ShuttleBusPeriodState.active) {
        return period;
      }
    }
    return null;
  }

  private static shanghaiClockMinutes(): number {
    const shifted: Date = new Date(Date.now() + SHANGHAI_OFFSET_MS);
    return shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  }

  private static departureMinutes(value: string): number {
    return Number(value.substring(0, 2)) * 60 + Number(value.substring(3, 5));
  }
}

export interface ShuttleBusFetching {
  fetch(): Promise<ShuttleBusSnapshot>;
}

export class ShuttleBusClient implements ShuttleBusFetching {
  static requestSpec(): HttpRequestSpec {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.headers = { 'Accept': 'application/json' };
    spec.maxBytes = ShuttleBusSources.maximumPayloadBytes;
    // The public query endpoint is pinned exactly. A redirect is an endpoint
    // change and must be rejected before any follow-up request is sent.
    spec.maxRedirects = 0;
    return spec;
  }

  async fetch(): Promise<ShuttleBusSnapshot> {
    const spec: HttpRequestSpec = ShuttleBusClient.requestSpec();
    const response: HttpResult = await HttpUtil.perform(
      ShuttleBusSources.endpoint, spec, 'where-to-study.cn');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error('班车服务返回 HTTP ' + response.statusCode.toString() + '。');
    }
    return ShuttleBusResponseParser.parse(response.body);
  }
}
