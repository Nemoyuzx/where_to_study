import { AppContext } from './AppContext';
import { JsonFile } from './JsonFile';
import { JsonUtil } from '../common/JsonUtil';
import { StrictDates } from '../common/StrictDates';
import { Utf8 } from '../common/Utf8';
import { AssignmentDeadlineItem } from '../net/CalendarDailyInfoClient';
import { UCloudCourse } from '../net/UCloudAssignmentClient';
import { QMPlusSnapshot, QMPlusSnapshotParser } from '../net/QMPlusSnapshot';

export class CourseDTOCache {
  readonly scope: string;
  readonly courses: UCloudCourse[] | null;
  readonly assignments: AssignmentDeadlineItem[] | null;
  readonly coursesFetchedAt: number;
  readonly assignmentsFetchedAt: number;
  constructor(scope: string, courses: UCloudCourse[] | null, assignments: AssignmentDeadlineItem[] | null,
    coursesFetchedAt: number, assignmentsFetchedAt: number) {
    this.scope = scope; this.courses = courses; this.assignments = assignments;
    this.coursesFetchedAt = coursesFetchedAt; this.assignmentsFetchedAt = assignmentsFetchedAt;
  }
}

// Named ArkTS payloads retain JSON null without assigning it to Object-valued
// Record indexes. The reader still validates the serialized whitelist first.
class CachedCoursePayload {
  readonly id: string;
  readonly name: string | null;
  readonly teachers: string[];
  constructor(course: UCloudCourse) {
    this.id = course.id; this.name = course.name; this.teachers = course.teacherNames;
  }
}

class CachedAssignmentPayload {
  readonly id: string;
  readonly title: string;
  readonly course_name: string | null;
  readonly course_id: string | null;
  readonly deadline: string;
  readonly status: string | null;
  constructor(item: AssignmentDeadlineItem) {
    this.id = item.id; this.title = item.title; this.course_name = item.courseName;
    this.course_id = item.courseID; this.deadline = item.deadline; this.status = item.status;
  }
}

class CourseCachePayload {
  readonly schema: number = 1;
  readonly source: string = 'teaching-cloud';
  readonly scope: string;
  readonly courses_fetched_at: number;
  readonly assignments_fetched_at: number;
  readonly courses: CachedCoursePayload[] | null;
  readonly assignments: CachedAssignmentPayload[] | null;
  constructor(cache: CourseDTOCache) {
    this.scope = cache.scope; this.courses_fetched_at = cache.coursesFetchedAt;
    this.assignments_fetched_at = cache.assignmentsFetchedAt;
    this.courses = cache.courses === null ? null : cache.courses.map((course: UCloudCourse): CachedCoursePayload => new CachedCoursePayload(course));
    this.assignments = cache.assignments === null ? null : cache.assignments.map((item: AssignmentDeadlineItem): CachedAssignmentPayload => new CachedAssignmentPayload(item));
  }
}

// One ordered stream per file, shared across Root recreation. Only validated
// business DTOs and an opaque random binding enter these app-private files.
// No account, credential digest, cookie, ticket, access token or HTML fields.
export class CourseDTOCacheStore {
  static readonly maximumBytes: number = 2 * 1024 * 1024;
  private static queues: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  private readonly name: string;
  constructor(name: string = 'teaching-cloud') {
    if (!['teaching-cloud', 'qmplus'].includes(name)) { throw new Error('COURSE_CACHE_SOURCE'); }
    this.name = name;
  }
  private path(): string { return AppContext.get().filesDir + '/course-dto-cache-' + this.name + '-v1.json'; }
  private async enqueue(work: () => Promise<void>): Promise<void> {
    const path: string = this.path();
    const next: Promise<void> = (CourseDTOCacheStore.queues.get(path) ?? Promise.resolve()).catch((): void => {}).then(work);
    CourseDTOCacheStore.queues.set(path, next.catch((): void => {}));
    await next;
  }
  private keys(raw: Record<string, Object>, allowed: string[]): void {
    if (Object.keys(raw).some((key: string): boolean => !allowed.includes(key))) { throw new Error('COURSE_CACHE_FIELDS'); }
  }
  private text(raw: Object | undefined, nullable: boolean = false, max: number = 2048): string | null {
    if (nullable && (raw === undefined || raw === null)) { return null; }
    if (typeof raw !== 'string' || (raw as string).length > max) { throw new Error('COURSE_CACHE_TEXT'); }
    return raw as string;
  }
  private time(raw: Object | undefined): number {
    if (typeof raw !== 'number' || !Number.isFinite(raw) || raw < 0 || raw > Date.now() + 60000) { throw new Error('COURSE_CACHE_TIME'); }
    return raw as number;
  }
  private parse(raw: Record<string, Object>, scope: string): CourseDTOCache {
    this.keys(raw, ['schema', 'source', 'scope', 'courses', 'assignments', 'courses_fetched_at', 'assignments_fetched_at']);
    if (raw['schema'] !== 1 || raw['source'] !== 'teaching-cloud' || raw['scope'] !== scope || !/^[0-9a-f]{32}$/.test(scope)) {
      throw new Error('COURSE_CACHE_BINDING');
    }
    let courses: UCloudCourse[] | null = null;
    if (raw['courses'] !== null) {
      if (!Array.isArray(raw['courses']) || (raw['courses'] as Object[]).length > 512) { throw new Error('COURSE_CACHE_COURSES'); }
      courses = [];
      const ids: Set<string> = new Set<string>();
      for (const value of raw['courses'] as Object[]) {
        if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('COURSE_CACHE_COURSE'); }
        const row: Record<string, Object> = value as Record<string, Object>;
        this.keys(row, ['id', 'name', 'teachers']);
        const id: string = this.text(row['id'], false, 128) as string;
        if (id.length === 0 || ids.has(id)) { throw new Error('COURSE_CACHE_ID'); }
        ids.add(id);
        if (!Array.isArray(row['teachers']) || (row['teachers'] as Object[]).length > 64) { throw new Error('COURSE_CACHE_TEACHERS'); }
        const teachers: string[] = (row['teachers'] as Object[]).map((teacher: Object): string => this.text(teacher, false, 256) as string);
        courses.push(new UCloudCourse(id, this.text(row['name'], true), teachers));
      }
    }
    let assignments: AssignmentDeadlineItem[] | null = null;
    if (raw['assignments'] !== null) {
      if (!Array.isArray(raw['assignments']) || (raw['assignments'] as Object[]).length > 5000) { throw new Error('COURSE_CACHE_ASSIGNMENTS'); }
      assignments = [];
      const ids: Set<string> = new Set<string>();
      for (const value of raw['assignments'] as Object[]) {
        if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('COURSE_CACHE_ASSIGNMENT'); }
        const row: Record<string, Object> = value as Record<string, Object>;
        this.keys(row, ['id', 'title', 'course_name', 'course_id', 'deadline', 'status']);
        const id: string = this.text(row['id'], false, 256) as string;
        const deadline: string = this.text(row['deadline'], false, 64) as string;
        if (id.length === 0 || ids.has(id) || StrictDates.parseDateString(deadline.substring(0, 10)) === null ||
          !/^\d{4}-\d{2}-\d{2}[ T](?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,3})?)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)?$/.test(deadline)) {
          throw new Error('COURSE_CACHE_ASSIGNMENT_ID_TIME');
        }
        ids.add(id);
        assignments.push(new AssignmentDeadlineItem(id, this.text(row['title']) as string,
          this.text(row['course_name'], true), deadline, this.text(row['status'], true), this.text(row['course_id'], true, 128)));
      }
    }
    return new CourseDTOCache(scope, courses, assignments, this.time(raw['courses_fetched_at']), this.time(raw['assignments_fetched_at']));
  }
  async load(scope: string): Promise<CourseDTOCache | null> {
    if (!/^[0-9a-f]{32}$/.test(scope) || this.name !== 'teaching-cloud') { return null; }
    try {
      let result: CourseDTOCache | null = null;
      await this.enqueue(async (): Promise<void> => {
        const text: string | null = await JsonFile.readText(this.path(), CourseDTOCacheStore.maximumBytes);
        const raw: Record<string, Object> | null = text === null ? null : JsonUtil.parseObject(text);
        if (raw !== null) { result = this.parse(raw, scope); }
      });
      return result;
    } catch (e) { return null; }
  }
  async save(cache: CourseDTOCache, current: () => boolean): Promise<boolean> {
    if (this.name !== 'teaching-cloud' || !/^[0-9a-f]{32}$/.test(cache.scope)) { return false; }
    let saved: boolean = false;
    await this.enqueue(async (): Promise<void> => {
      if (!current()) { return; }
      const text: string = JSON.stringify(new CourseCachePayload(cache));
      if (Utf8.bytes(text).length > CourseDTOCacheStore.maximumBytes) { throw new Error('COURSE_CACHE_SIZE'); }
      const raw: Record<string, Object> | null = JsonUtil.parseObject(text);
      if (raw === null) { throw new Error('COURSE_CACHE_FORMAT'); }
      this.parse(raw, cache.scope);
      await JsonFile.writeTextAtomic(this.path(), text);
      saved = current();
    });
    return saved;
  }
  async loadQM(scope: string): Promise<QMPlusSnapshot | null> {
    if (this.name !== 'qmplus' || !/^[0-9a-f]{32}$/.test(scope)) { return null; }
    try {
      let result: QMPlusSnapshot | null = null;
      await this.enqueue(async (): Promise<void> => {
        const text: string | null = await JsonFile.readText(this.path(), QMPlusSnapshotParser.maximumBytes * 2 + 1024);
        const raw: Record<string, Object> | null = text === null ? null : JsonUtil.parseObject(text);
        if (raw === null) { return; }
        this.keys(raw, ['schema', 'source', 'scope', 'snapshot']);
        if (raw['schema'] !== 1 || raw['source'] !== 'qmplus' || raw['scope'] !== scope || typeof raw['snapshot'] !== 'string') { return; }
        result = QMPlusSnapshotParser.parse(raw['snapshot'] as string);
      });
      return result;
    } catch (e) { return null; }
  }
  async saveQM(scope: string, raw: string, current: () => boolean): Promise<boolean> {
    if (this.name !== 'qmplus' || !/^[0-9a-f]{32}$/.test(scope)) { return false; }
    QMPlusSnapshotParser.parse(raw);
    let saved: boolean = false;
    await this.enqueue(async (): Promise<void> => {
      if (!current()) { return; }
      const envelope: Record<string, Object> = {}; envelope['schema'] = 1; envelope['source'] = this.name;
      envelope['scope'] = scope; envelope['snapshot'] = raw;
      const text: string = JSON.stringify(envelope);
      if (Utf8.bytes(text).length > QMPlusSnapshotParser.maximumBytes * 2 + 1024) { throw new Error('COURSE_CACHE_SIZE'); }
      await JsonFile.writeTextAtomic(this.path(), text);
      saved = current();
    });
    return saved;
  }
  async clear(): Promise<void> { await this.enqueue((): Promise<void> => JsonFile.removeFile(this.path())); }
}
