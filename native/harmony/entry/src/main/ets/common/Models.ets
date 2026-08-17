// contracts/v1 数据契约的 ArkTS 模型，与 iOS 端 Models.swift 一一对应。
// 字段命名与 Swift 端 camelCase 相同；JSON 序列化使用契约的 snake_case。
// 所有模型不可变（readonly），更新通过构造新对象完成。

import { JsonUtil } from './JsonUtil';

export class SlotMetadata {
  readonly index: number;
  readonly label: string;
  readonly start: string;
  readonly end: string;

  constructor(index: number, label: string, start: string, end: string) {
    this.index = index;
    this.label = label;
    this.start = start;
    this.end = end;
  }

  static readonly defaults: SlotMetadata[] = [
    new SlotMetadata(0, '1', '08:00', '08:45'),
    new SlotMetadata(1, '2', '08:50', '09:35'),
    new SlotMetadata(2, '3', '09:50', '10:35'),
    new SlotMetadata(3, '4', '10:40', '11:25'),
    new SlotMetadata(4, '5', '11:30', '12:15'),
    new SlotMetadata(5, '6', '13:00', '13:45'),
    new SlotMetadata(6, '7', '13:50', '14:35'),
    new SlotMetadata(7, '8', '14:45', '15:30'),
    new SlotMetadata(8, '9', '15:40', '16:25'),
    new SlotMetadata(9, '10', '16:35', '17:20'),
    new SlotMetadata(10, '11', '17:25', '18:10'),
    new SlotMetadata(11, '12', '18:30', '19:15'),
    new SlotMetadata(12, '13', '19:20', '20:05'),
    new SlotMetadata(13, '14', '20:10', '20:55')
  ];
}

export class Course {
  readonly id: string;
  readonly name: string;
  readonly teacher: string;
  readonly room: string;
  readonly weekText: string;
  readonly weekNumbers: number[];
  readonly examWeekNumbers: number[];
  readonly weekday: number;
  readonly startSlot: number;
  readonly endSlot: number;
  readonly sectionText: string;
  readonly timeRange: string;

  constructor(
    id: string, name: string, teacher: string, room: string, weekText: string,
    weekNumbers: number[], examWeekNumbers: number[], weekday: number,
    startSlot: number, endSlot: number, sectionText: string, timeRange: string
  ) {
    this.id = id;
    this.name = name;
    this.teacher = teacher;
    this.room = room;
    this.weekText = weekText;
    this.weekNumbers = weekNumbers;
    this.examWeekNumbers = examWeekNumbers;
    this.weekday = weekday;
    this.startSlot = startSlot;
    this.endSlot = endSlot;
    this.sectionText = sectionText;
    this.timeRange = timeRange;
  }

  static fromJson(raw: Record<string, Object>): Course {
    return new Course(
      JsonUtil.string(raw['id']),
      JsonUtil.string(raw['name']),
      JsonUtil.string(raw['teacher']),
      JsonUtil.string(raw['room']),
      JsonUtil.string(raw['week_text']),
      JsonUtil.numberArray(raw['week_numbers']),
      JsonUtil.numberArray(raw['exam_week_numbers']),
      JsonUtil.number(raw['weekday']),
      JsonUtil.number(raw['start_slot']),
      JsonUtil.number(raw['end_slot']),
      JsonUtil.string(raw['section_text']),
      JsonUtil.string(raw['time_range'])
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['id'] = this.id;
    out['name'] = this.name;
    out['teacher'] = this.teacher;
    out['room'] = this.room;
    out['week_text'] = this.weekText;
    out['week_numbers'] = this.weekNumbers;
    out['exam_week_numbers'] = this.examWeekNumbers;
    out['weekday'] = this.weekday;
    out['start_slot'] = this.startSlot;
    out['end_slot'] = this.endSlot;
    out['section_text'] = this.sectionText;
    out['time_range'] = this.timeRange;
    return out;
  }
}

export class ScheduleSnapshot {
  readonly termID: string;
  readonly termStartDate: string;
  readonly fetchedAt: string;
  readonly courses: Course[];

  constructor(termID: string, termStartDate: string, fetchedAt: string, courses: Course[]) {
    this.termID = termID;
    this.termStartDate = termStartDate;
    this.fetchedAt = fetchedAt;
    this.courses = courses;
  }

  static fromJson(raw: Record<string, Object>): ScheduleSnapshot {
    const courses: Course[] = [];
    for (const item of JsonUtil.array(raw['courses'])) {
      courses.push(Course.fromJson(JsonUtil.record(item)));
    }
    return new ScheduleSnapshot(
      JsonUtil.string(raw['term_id']),
      JsonUtil.string(raw['term_start_date']),
      JsonUtil.string(raw['fetched_at']),
      courses
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['term_id'] = this.termID;
    out['term_start_date'] = this.termStartDate;
    out['fetched_at'] = this.fetchedAt;
    const courseList: Record<string, Object>[] = [];
    for (const c of this.courses) {
      courseList.push(c.toJson());
    }
    out['courses'] = courseList;
    return out;
  }
}

export class Classroom {
  readonly id: string;
  readonly building: string;
  readonly room: string;
  readonly name: string;
  readonly size: number | null;
  readonly type: string;
  readonly availableSlots: number[];
  readonly source: string;

  constructor(
    id: string, building: string, room: string, name: string, size: number | null,
    type: string, availableSlots: number[], source: string
  ) {
    this.id = id;
    this.building = building;
    this.room = room;
    this.name = name;
    this.size = size;
    this.type = type;
    this.availableSlots = availableSlots;
    this.source = source;
  }

  static fromJson(raw: Record<string, Object>): Classroom {
    return new Classroom(
      JsonUtil.string(raw['id']),
      JsonUtil.string(raw['building']),
      JsonUtil.string(raw['room']),
      JsonUtil.string(raw['name']),
      JsonUtil.nullableNumber(raw['size']),
      JsonUtil.string(raw['type']),
      JsonUtil.numberArray(raw['available_slots']),
      JsonUtil.string(raw['source'])
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['id'] = this.id;
    out['building'] = this.building;
    out['room'] = this.room;
    out['name'] = this.name;
    out['size'] = this.size;
    out['type'] = this.type;
    out['available_slots'] = this.availableSlots;
    out['source'] = this.source;
    return out;
  }
}

export class CampusClassrooms {
  readonly campusID: string;
  readonly campusName: string;
  readonly targetDate: string;
  readonly fetchedAt: string;
  readonly realtime: boolean;
  readonly provider: string;
  readonly rooms: Classroom[];

  constructor(
    campusID: string, campusName: string, targetDate: string, fetchedAt: string,
    realtime: boolean, provider: string, rooms: Classroom[]
  ) {
    this.campusID = campusID;
    this.campusName = campusName;
    this.targetDate = targetDate;
    this.fetchedAt = fetchedAt;
    this.realtime = realtime;
    this.provider = provider;
    this.rooms = rooms;
  }

  static fromJson(raw: Record<string, Object>): CampusClassrooms {
    const rooms: Classroom[] = [];
    for (const item of JsonUtil.array(raw['rooms'])) {
      rooms.push(Classroom.fromJson(JsonUtil.record(item)));
    }
    return new CampusClassrooms(
      JsonUtil.string(raw['campus_id']),
      JsonUtil.string(raw['campus_name']),
      JsonUtil.string(raw['target_date']),
      JsonUtil.string(raw['fetched_at']),
      JsonUtil.bool(raw['realtime']),
      JsonUtil.string(raw['provider']),
      rooms
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['campus_id'] = this.campusID;
    out['campus_name'] = this.campusName;
    out['target_date'] = this.targetDate;
    out['fetched_at'] = this.fetchedAt;
    out['realtime'] = this.realtime;
    out['provider'] = this.provider;
    const roomList: Record<string, Object>[] = [];
    for (const r of this.rooms) {
      roomList.push(r.toJson());
    }
    out['rooms'] = roomList;
    return out;
  }
}

export class ClassroomsCache {
  readonly cacheVersion: number;
  readonly targetDate: string;
  readonly fetchedAt: string;
  readonly realtime: boolean;
  readonly provider: string;
  readonly campuses: CampusClassrooms[];

  constructor(
    cacheVersion: number, targetDate: string, fetchedAt: string, realtime: boolean,
    provider: string, campuses: CampusClassrooms[]
  ) {
    this.cacheVersion = cacheVersion;
    this.targetDate = targetDate;
    this.fetchedAt = fetchedAt;
    this.realtime = realtime;
    this.provider = provider;
    this.campuses = campuses;
  }

  static fromJson(raw: Record<string, Object>): ClassroomsCache {
    const campuses: CampusClassrooms[] = [];
    for (const item of JsonUtil.array(raw['campuses'])) {
      campuses.push(CampusClassrooms.fromJson(JsonUtil.record(item)));
    }
    return new ClassroomsCache(
      JsonUtil.number(raw['cache_version']),
      JsonUtil.string(raw['target_date']),
      JsonUtil.string(raw['fetched_at']),
      JsonUtil.bool(raw['realtime']),
      JsonUtil.string(raw['provider']),
      campuses
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['cache_version'] = this.cacheVersion;
    out['target_date'] = this.targetDate;
    out['fetched_at'] = this.fetchedAt;
    out['realtime'] = this.realtime;
    out['provider'] = this.provider;
    const campusList: Record<string, Object>[] = [];
    for (const c of this.campuses) {
      campusList.push(c.toJson());
    }
    out['campuses'] = campusList;
    return out;
  }
}

export class HolidayItem {
  readonly date: string;
  readonly name: string;
  readonly type: string; // "holiday" | "workday"

  constructor(date: string, name: string, type: string) {
    this.date = date;
    this.name = name;
    this.type = type;
  }

  id(): string {
    return this.date + '|' + this.type + '|' + this.name;
  }

  static fromJson(raw: Record<string, Object>): HolidayItem {
    return new HolidayItem(
      JsonUtil.string(raw['date']),
      JsonUtil.string(raw['name']),
      JsonUtil.string(raw['type'])
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['date'] = this.date;
    out['name'] = this.name;
    out['type'] = this.type;
    return out;
  }
}

export class HolidaysSnapshot {
  readonly year: number;
  readonly source: string;
  readonly fetchedAt: string;
  readonly items: HolidayItem[];

  constructor(year: number, source: string, fetchedAt: string, items: HolidayItem[]) {
    this.year = year;
    this.source = source;
    this.fetchedAt = fetchedAt;
    this.items = items;
  }

  static fromJson(raw: Record<string, Object>): HolidaysSnapshot {
    const items: HolidayItem[] = [];
    for (const item of JsonUtil.array(raw['items'])) {
      items.push(HolidayItem.fromJson(JsonUtil.record(item)));
    }
    return new HolidaysSnapshot(
      JsonUtil.number(raw['year']),
      JsonUtil.string(raw['source']),
      JsonUtil.string(raw['fetched_at']),
      items
    );
  }

  toJson(): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['year'] = this.year;
    out['source'] = this.source;
    out['fetched_at'] = this.fetchedAt;
    const itemList: Record<string, Object>[] = [];
    for (const it of this.items) {
      itemList.push(it.toJson());
    }
    out['items'] = itemList;
    return out;
  }
}

export class CampusInfo {
  readonly id: string;
  readonly name: string;

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

export class ScheduleDefaults {
  static readonly termID: string = '2025-2026-2';
  static readonly termStartDate: string = '2026-03-02';
}

export class HolidayDefaults {
  static readonly source: string = 'https://unpkg.com/holiday-calendar@1.3.3/data/CN';
  static readonly supportedYearsStart: number = 1900;
  static readonly supportedYearsEnd: number = 2100;
  static readonly refreshIntervalMs: number = 7 * 24 * 60 * 60 * 1000;
}

export class ClassroomDefaults {
  static readonly cacheVersion: number = 2;
  static readonly campuses: CampusInfo[] = [
    new CampusInfo('01', '西土城'),
    new CampusInfo('04', '沙河')
  ];

  private static readonly buildingsByCampusID: Map<string, string[]> = ClassroomDefaults.buildBuildingsMap();

  private static buildBuildingsMap(): Map<string, string[]> {
    const result: Map<string, string[]> = new Map<string, string[]>();
    result.set('01', ['教1', '教2', '教3', '教4', '主楼']);
    result.set('04', ['综合教学楼N', '综合教学楼S', '教学实验综合楼N', '教学实验综合楼S', '智慧教学楼']);
    return result;
  }

  static buildings(campusID: string): string[] {
    const result: string[] | undefined = ClassroomDefaults.buildingsByCampusID.get(campusID);
    return result === undefined ? [] : result;
  }
}
