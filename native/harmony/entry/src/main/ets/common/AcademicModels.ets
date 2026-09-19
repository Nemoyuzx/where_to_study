import { JsonUtil } from './JsonUtil';
import { StrictDates } from './StrictDates';

// 只保留展示必需字段，不保存学校响应中的姓名、学号或原始响应。
export class AcademicTerm {
  readonly id: string;
  readonly name: string;
  constructor(id: string, name: string) { this.id = id; this.name = name; }
}

export class GradeOptions {
  readonly currentTermID: string;
  readonly terms: AcademicTerm[];
  constructor(currentTermID: string, terms: AcademicTerm[]) {
    this.currentTermID = currentTermID; this.terms = terms;
  }
}

export class GradeItem {
  readonly id: string;
  readonly name: string;
  readonly score: string | null;
  readonly credits: string | null;
  readonly courseCode: string;
  readonly courseAttribute: string;
  readonly courseNature: string;
  readonly examNature: string;
  readonly semesterName: string;
  readonly gradeStatus: string;
  constructor(id: string, name: string, score: string | null, credits: string | null,
    courseCode: string, courseAttribute: string, courseNature: string, examNature: string,
    semesterName: string = '', gradeStatus: string = '') {
    this.id = id; this.name = name; this.score = score; this.credits = credits;
    this.courseCode = courseCode; this.courseAttribute = courseAttribute;
    this.courseNature = courseNature; this.examNature = examNature;
    this.semesterName = semesterName; this.gradeStatus = gradeStatus;
  }
}

export class GradeSnapshot {
  readonly termID: string;
  readonly recordType: string;
  readonly fetchedAt: string;
  readonly averageGradePoint: string | null;
  readonly items: GradeItem[];
  constructor(termID: string, recordType: string, fetchedAt: string,
    averageGradePoint: string | null, items: GradeItem[]) {
    this.termID = termID; this.recordType = recordType; this.fetchedAt = fetchedAt;
    this.averageGradePoint = averageGradePoint; this.items = items;
  }
}

export class ExamArrangement {
  readonly id: string;
  readonly name: string;
  readonly date: string;
  readonly startTime: string;
  readonly endTime: string;
  readonly room: string;
  readonly seat: string;
  readonly timeText: string;
  constructor(id: string, name: string, date: string, startTime: string, endTime: string,
    room: string, seat: string, timeText: string) {
    this.id = id; this.name = name; this.date = date; this.startTime = startTime;
    this.endTime = endTime; this.room = room; this.seat = seat; this.timeText = timeText;
  }

  static fromJson(raw: Record<string, Object>): ExamArrangement {
    const date: string = JsonUtil.string(raw['date']);
    const start: string = JsonUtil.string(raw['start_time']);
    const end: string = JsonUtil.string(raw['end_time']);
    const validTime: boolean = AcademicTime.validInterval(start, end);
    return new ExamArrangement(JsonUtil.string(raw['id']), JsonUtil.string(raw['name']),
      StrictDates.parseDateString(date) === null ? '' : date,
      validTime ? start : '', validTime ? end : '', JsonUtil.string(raw['room']),
      JsonUtil.string(raw['seat']), JsonUtil.string(raw['time_text']));
  }

  toJson(): Record<string, Object> {
    return { 'id': this.id, 'name': this.name, 'date': this.date,
      'start_time': this.startTime, 'end_time': this.endTime, 'room': this.room,
      'seat': this.seat, 'time_text': this.timeText };
  }
}

export class ExamSchedule {
  readonly termID: string;
  readonly accountKey: string;
  readonly fetchedAt: string;
  readonly status: string;
  readonly message: string;
  readonly items: ExamArrangement[];
  constructor(termID: string, accountKey: string, fetchedAt: string, status: string,
    message: string, items: ExamArrangement[]) {
    this.termID = termID; this.accountKey = accountKey; this.fetchedAt = fetchedAt;
    this.status = status; this.message = message; this.items = items;
  }

  static fromJson(raw: Object | undefined): ExamSchedule | null {
    if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      return null;
    }
    const record: Record<string, Object> = raw as Record<string, Object>;
    const status: string = JsonUtil.string(record['status']);
    const owner: string = JsonUtil.string(record['account_key']);
    const term: string = JsonUtil.string(record['term_id']);
    if (owner.length === 0 || term.length === 0 || !Array.isArray(record['items']) ||
      ['fresh', 'stale', 'failed'].indexOf(status) < 0) {
      return null;
    }
    const items: ExamArrangement[] = [];
    for (const value of JsonUtil.array(record['items'])) {
      const item: ExamArrangement = ExamArrangement.fromJson(JsonUtil.record(value));
      if (item.id.length === 0 || item.name.length === 0) { return null; }
      items.push(item);
    }
    return new ExamSchedule(term, owner, JsonUtil.string(record['fetched_at']), status,
      JsonUtil.string(record['message']), status === 'failed' ? [] : items);
  }

  toJson(): Record<string, Object> {
    const items: Record<string, Object>[] = this.items.map((item: ExamArrangement) => item.toJson());
    return { 'term_id': this.termID, 'account_key': this.accountKey,
      'fetched_at': this.fetchedAt, 'status': this.status, 'message': this.message, 'items': items };
  }

  static resolveRefresh(incoming: ExamSchedule | null, previous: ExamSchedule | null,
    termID: string, accountKey: string): ExamSchedule | null {
    if (incoming !== null && incoming.termID === termID && incoming.accountKey === accountKey &&
      incoming.status === 'fresh') { return incoming; }
    const message: string = incoming?.message ?? '考试安排暂时无法获取。';
    if (previous !== null && previous.termID === termID && previous.accountKey === accountKey &&
      previous.status !== 'failed') {
      return new ExamSchedule(termID, accountKey, previous.fetchedAt, 'stale', message, previous.items);
    }
    return new ExamSchedule(termID, accountKey, '', 'failed', message, []);
  }
}

export class AcademicTime {
  static minute(value: string): number | null {
    if (!/^\d{2}:\d{2}$/.test(value)) { return null; }
    const hour: number = Number(value.substring(0, 2));
    const minute: number = Number(value.substring(3));
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  static validInterval(start: string, end: string): boolean {
    const left: number | null = AcademicTime.minute(start);
    const right: number | null = AcademicTime.minute(end);
    return left !== null && right !== null && right > left;
  }
}
