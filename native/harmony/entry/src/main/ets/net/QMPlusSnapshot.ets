// ArkWeb 页面产物只在内存中使用。即使共享脚本已限制响应，native 仍重新验证
// 来源、大小、时间和每个官方业务 URL；不接受 Cookie、sesskey 或完整 HTML。
import { JsonUtil } from '../common/JsonUtil';
import { Utf8 } from '../common/Utf8';

export class QMPlusCourse {
  readonly id: string;
  readonly name: string;
  readonly shortName: string;
  readonly url: string | null;
  readonly startAt: string | null;
  readonly endAt: string | null;
  readonly currentTermStatus: string;

  constructor(id: string, name: string, shortName: string, url: string | null,
    startAt: string | null, endAt: string | null, currentTermStatus: string) {
    this.id = id;
    this.name = name;
    this.shortName = shortName;
    this.url = url;
    this.startAt = startAt;
    this.endAt = endAt;
    this.currentTermStatus = currentTermStatus;
  }
}

export class QMPlusActivity {
  readonly id: string;
  readonly courseID: string;
  readonly title: string;
  readonly kind: string;
  readonly url: string;
  readonly dueAt: string | null;
  readonly opensAt: string | null;
  readonly closesAt: string | null;
  readonly cutoffAt: string | null;
  readonly timeLimitSeconds: number | null;
  readonly status: string;
  readonly detailStatus: string;
  readonly rawTimeText: string;

  constructor(id: string, courseID: string, title: string, kind: string, url: string,
    dueAt: string | null, opensAt: string | null, closesAt: string | null, cutoffAt: string | null,
    timeLimitSeconds: number | null, status: string, detailStatus: string, rawTimeText: string) {
    this.id = id;
    this.courseID = courseID;
    this.title = title;
    this.kind = kind;
    this.url = url;
    this.dueAt = dueAt;
    this.opensAt = opensAt;
    this.closesAt = closesAt;
    this.cutoffAt = cutoffAt;
    this.timeLimitSeconds = timeLimitSeconds;
    this.status = status;
    this.detailStatus = detailStatus;
    this.rawTimeText = rawTimeText;
  }
}

export class QMPlusSnapshot {
  readonly fetchedAt: string;
  readonly partial: boolean;
  readonly courses: QMPlusCourse[];
  readonly activities: QMPlusActivity[];
  readonly warnings: string[];

  constructor(fetchedAt: string, partial: boolean, courses: QMPlusCourse[],
    activities: QMPlusActivity[], warnings: string[]) {
    this.fetchedAt = fetchedAt;
    this.partial = partial;
    this.courses = courses;
    this.activities = activities;
    this.warnings = warnings;
  }
}

export class QMPlusURLPolicy {
  static readonly home: string = 'https://qmplus.qmul.ac.uk/my/';

  static isBusinessPage(value: string): boolean {
    return /^https:\/\/qmplus\.qmul\.ac\.uk\/(?:my\/|course\/|mod\/assign\/|mod\/quiz\/|calendar\/)(?:[^\s]*)?$/.test(value);
  }

  static isHTTPSPage(value: string): boolean {
    return /^https:\/\/[^\s/@?#]+(?:\/|\?|#|$)/i.test(value);
  }

  static isCourseURL(value: string): boolean {
    return /^https:\/\/qmplus\.qmul\.ac\.uk\/course\/view\.php\?id=[1-9]\d{0,15}$/.test(value);
  }

  static isActivityURL(value: string, kind: string): boolean {
    const path: string = kind === 'assignment' ? 'assign' : kind === 'quiz' ? 'quiz' : '';
    return path.length > 0 && new RegExp('^https://qmplus\\.qmul\\.ac\\.uk/mod/' + path +
      '/view\\.php\\?id=[1-9]\\d{0,15}$').test(value);
  }
}

export class QMPlusSnapshotParser {
  static readonly maximumBytes: number = 512 * 1024;
  private static readonly identifier: RegExp = /^[1-9]\d{0,15}$/;
  private static readonly utcDate: RegExp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;

  static parse(raw: string): QMPlusSnapshot {
    if (raw.length > QMPlusSnapshotParser.maximumBytes ||
      Utf8.bytes(raw).length > QMPlusSnapshotParser.maximumBytes) {
      throw new Error('QMplus 快照超过安全大小上限。');
    }
    const root: Record<string, Object> | null = JsonUtil.parseObject(raw);
    if (root === null || root['schema_version'] !== 1 || root['source'] !== 'qmplus' ||
      typeof root['ok'] !== 'boolean' || typeof root['partial'] !== 'boolean' ||
      !Array.isArray(root['courses']) || !Array.isArray(root['activities']) ||
      !Array.isArray(root['warnings'])) {
      throw new Error('QMplus 快照格式不正确。');
    }
    if (!QMPlusSnapshotParser.hasOnlyKeys(root, root['ok'] === true ?
      ['schema_version', 'source', 'fetched_at', 'ok', 'partial', 'courses', 'activities', 'warnings'] :
      ['schema_version', 'source', 'fetched_at', 'ok', 'partial', 'courses', 'activities', 'warnings', 'error_code'])) {
      throw new Error('QMplus 快照包含未授权字段。');
    }
    if (root['ok'] !== true) {
      const code: string = QMPlusSnapshotParser.boundedString(root['error_code'], 80);
      throw new Error(/^[A-Z0-9_]{1,80}$/.test(code) ? code : 'QM_SYNC_FAILED');
    }
    const fetchedAt: string = QMPlusSnapshotParser.requiredUTC(root['fetched_at']);
    const rawCourses: Object[] = JsonUtil.array(root['courses']);
    const rawActivities: Object[] = JsonUtil.array(root['activities']);
    const rawWarnings: Object[] = JsonUtil.array(root['warnings']);
    if (rawCourses.length > 100 || rawActivities.length > 500 || rawWarnings.length > 40) {
      throw new Error('QMplus 快照条目超过安全上限。');
    }
    const courses: QMPlusCourse[] = [];
    const ids: Set<string> = new Set<string>();
    for (const rawCourse of rawCourses) {
      const course: Record<string, Object> = JsonUtil.record(rawCourse);
      if (!QMPlusSnapshotParser.hasOnlyKeys(course,
        ['id', 'name', 'short_name', 'url', 'start_at', 'end_at', 'current_term_status'])) {
        throw new Error('QMplus 课程包含未授权字段。');
      }
      const id: string = QMPlusSnapshotParser.identifierString(course['id']);
      const status: string = QMPlusSnapshotParser.boundedString(course['current_term_status'], 16);
      if (!['current', 'other', 'unknown'].includes(status) || ids.has(id)) {
        throw new Error('QMplus 课程条目格式不正确。');
      }
      const url: string | null = QMPlusSnapshotParser.nullableString(course['url'], 200);
      if (url !== null && !QMPlusURLPolicy.isCourseURL(url)) {
        throw new Error('QMplus 课程地址不安全。');
      }
      ids.add(id);
      courses.push(new QMPlusCourse(id, QMPlusSnapshotParser.boundedString(course['name'], 512),
        QMPlusSnapshotParser.boundedString(course['short_name'], 512), url,
        QMPlusSnapshotParser.nullableUTC(course['start_at']),
        QMPlusSnapshotParser.nullableUTC(course['end_at']), status));
    }
    const activities: QMPlusActivity[] = [];
    for (const rawActivity of rawActivities) {
      const item: Record<string, Object> = JsonUtil.record(rawActivity);
      if (!QMPlusSnapshotParser.hasOnlyKeys(item,
        ['id', 'course_id', 'title', 'kind', 'url', 'due_at', 'opens_at', 'closes_at',
          'cutoff_at', 'time_limit_seconds', 'status', 'detail_status', 'raw_time_text'])) {
        throw new Error('QMplus 活动包含未授权字段。');
      }
      const id: string = QMPlusSnapshotParser.identifierString(item['id']);
      const courseID: string = QMPlusSnapshotParser.identifierString(item['course_id']);
      const kind: string = QMPlusSnapshotParser.boundedString(item['kind'], 16);
      const url: string = QMPlusSnapshotParser.boundedString(item['url'], 200);
      const detailStatus: string = QMPlusSnapshotParser.boundedString(item['detail_status'], 20);
      if (!ids.has(courseID) || !['assignment', 'quiz'].includes(kind) ||
        !QMPlusURLPolicy.isActivityURL(url, kind) ||
        !['available', 'restricted', 'unavailable'].includes(detailStatus)) {
        throw new Error('QMplus 活动条目格式不正确。');
      }
      const timeLimit: number | null = QMPlusSnapshotParser.nullableTimeLimit(item['time_limit_seconds']);
      activities.push(new QMPlusActivity(id, courseID,
        QMPlusSnapshotParser.boundedString(item['title'], 512), kind, url,
        QMPlusSnapshotParser.nullableUTC(item['due_at']),
        QMPlusSnapshotParser.nullableUTC(item['opens_at']),
        QMPlusSnapshotParser.nullableUTC(item['closes_at']),
        QMPlusSnapshotParser.nullableUTC(item['cutoff_at']), timeLimit,
        QMPlusSnapshotParser.boundedString(item['status'], 512), detailStatus,
        QMPlusSnapshotParser.boundedString(item['raw_time_text'], 1000)));
    }
    const warnings: string[] = [];
    for (const rawWarning of rawWarnings) {
      const warning: string = QMPlusSnapshotParser.boundedString(rawWarning, 80);
      if (!/^[A-Z0-9_]{1,80}$/.test(warning)) {
        throw new Error('QMplus 警告字段格式不正确。');
      }
      warnings.push(warning);
    }
    return new QMPlusSnapshot(fetchedAt, root['partial'] === true, courses, activities, warnings);
  }

  private static identifierString(value: Object | undefined | null): string {
    if (typeof value !== 'string' || !QMPlusSnapshotParser.identifier.test(value)) {
      throw new Error('QMplus 标识符格式不正确。');
    }
    return value;
  }

  private static hasOnlyKeys(record: Record<string, Object>, allowed: string[]): boolean {
    for (const key of Object.keys(record)) {
      if (allowed.indexOf(key) < 0) { return false; }
    }
    return true;
  }

  private static boundedString(value: Object | undefined | null, maximumLength: number): string {
    if (typeof value !== 'string' || value.length > maximumLength) {
      throw new Error('QMplus 文本字段格式不正确。');
    }
    return value;
  }

  private static nullableString(value: Object | undefined | null, maximumLength: number): string | null {
    if (value === null) { return null; }
    return QMPlusSnapshotParser.boundedString(value, maximumLength);
  }

  private static requiredUTC(value: Object | undefined | null): string {
    const text: string = QMPlusSnapshotParser.boundedString(value, 32);
    if (!QMPlusSnapshotParser.utcDate.test(text)) {
      throw new Error('QMplus 时间字段格式不正确。');
    }
    const epoch: number = new Date(text).getTime();
    if (!Number.isFinite(epoch) || new Date(epoch).toISOString().substring(0, 19) !== text.substring(0, 19)) {
      throw new Error('QMplus 时间字段无效。');
    }
    return text;
  }

  private static nullableUTC(value: Object | undefined | null): string | null {
    return value === null ? null : QMPlusSnapshotParser.requiredUTC(value);
  }

  private static nullableTimeLimit(value: Object | undefined | null): number | null {
    if (value === null) { return null; }
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > 366 * 86400) {
      throw new Error('QMplus 限时字段格式不正确。');
    }
    return value;
  }
}
