// 移动教务空教室响应解析（纯模块，无平台依赖，可被主机侧单元测试引用）。
// 与 iOS 端 SJDClassroomParser 一一对应。
import { CampusClassrooms, Classroom, ClassroomDefaults, ClassroomsCache } from '../../common/Models';
import { JsonUtil } from '../../common/JsonUtil';
import { RegexUtil } from '../../common/RegexUtil';
import { ClassroomClientError } from '../SjdErrors';
import { SJDAPIClient } from '../SjdApi';

class ParsedClassroom {
  readonly building: string;
  readonly room: string;
  readonly size: number | null;

  constructor(building: string, room: string, size: number | null) {
    this.building = building;
    this.room = room;
    this.size = size;
  }
}

class RoomAccumulator {
  readonly id: string;
  readonly building: string;
  readonly room: string;
  readonly name: string;
  size: number | null = null;
  availableSlots: Set<number> = new Set<number>();

  constructor(id: string, building: string, room: string, name: string, size: number | null) {
    this.id = id;
    this.building = building;
    this.room = room;
    this.name = name;
    this.size = size;
  }
}

export class SJDClassroomParser {
  private static readonly campusPrefixes: string[] = ['校本部', '西土城', '沙河'];
  private static readonly originalBuildings: string[] = [
    '教1', '教2', '教3', '教4', '主楼', '综合教学楼N', '综合教学楼S',
    '教学实验综合楼N', '教学实验综合楼S', '智慧教学楼'
  ];
  private static readonly northBuildings: string[] = [
    'N', 'N楼', 'N座', '北楼', '综合教学楼N', '综合教学楼N楼', '综合教学楼N座',
    '综合楼N', '综合楼N楼', '综合N'
  ];
  private static readonly southBuildings: string[] = [
    'S', 'S楼', 'S座', '南楼', '综合教学楼S', '综合教学楼S楼', '综合教学楼S座',
    '综合楼S', '综合楼S楼', '综合S'
  ];
  private static readonly experimentNorthBuildings: string[] = [
    '教学实验综合楼N', '教学实验综合楼N楼', '教学实验综合楼N座', '教学实验综合楼北',
    '教学实验综合楼北楼', '教学实验综合楼-N', '教学实验综合楼-N楼',
    '教学实验综合楼(综教)N', '教学实验综合楼（综教）N', '教学实验综合楼N(综教)',
    '教学实验综合楼N（综教）', '综教N', '综教N楼', '综教N座', '综教北', '综教北楼',
    '综教-N', '综教-N楼'
  ];
  private static readonly experimentSouthBuildings: string[] = [
    '教学实验综合楼S', '教学实验综合楼S楼', '教学实验综合楼S座', '教学实验综合楼南',
    '教学实验综合楼南楼', '教学实验综合楼-S', '教学实验综合楼-S楼',
    '教学实验综合楼(综教)S', '教学实验综合楼（综教）S', '教学实验综合楼S(综教)',
    '教学实验综合楼S（综教）', '综教S', '综教S楼', '综教S座', '综教南', '综教南楼',
    '综教-S', '综教-S楼'
  ];

  static parse(payloads: Map<string, string>, targetDate: string, fetchedAt: string): ClassroomsCache {
    const campuses: CampusClassrooms[] = [];
    for (const campus of ClassroomDefaults.campuses) {
      const data: string | undefined = payloads.get(campus.id);
      if (data === undefined) {
        throw ClassroomClientError.service('缺少' + campus.name + '校区实时教室数据。');
      }
      const payload: Record<string, Object> | null = JsonUtil.parseObject(data);
      if (payload === null || !SJDAPIClient.isSuccessful(payload)) {
        throw ClassroomClientError.service(campus.name + '校区实时教室数据格式不正确。');
      }
      campuses.push(SJDClassroomParser.parseCampus(
        campus.id, campus.name, JsonUtil.array(payload['data']), targetDate, fetchedAt));
    }
    return new ClassroomsCache(
      ClassroomDefaults.cacheVersion, targetDate, fetchedAt, true, 'sjd', campuses);
  }

  private static parseCampus(
    campusID: string, campusName: string, items: Object[], targetDate: string, fetchedAt: string
  ): CampusClassrooms {
    const roomMap: Map<string, RoomAccumulator> = new Map<string, RoomAccumulator>();
    for (const rawItem of items) {
      if (typeof rawItem !== 'object') {
        continue;
      }
      const item: Record<string, Object> = rawItem as Record<string, Object>;
      const nodeName: string = SJDClassroomParser.firstString(item,
        ['NODENAME', 'nodeName', 'nodename']);
      const slot: number | null = SJDClassroomParser.nodeNameToSlot(nodeName);
      if (slot === null) {
        continue;
      }
      const classroomsText: string = SJDClassroomParser.firstString(item,
        ['CLASSROOMS', 'classrooms', 'Classrooms']);
      const rawRooms: string[] = classroomsText.split(',').map((value: string) => value.trim());
      for (const raw of rawRooms) {
        if (raw.length === 0) {
          continue;
        }
        const parsed: ParsedClassroom | null = SJDClassroomParser.parseClassroom(raw);
        if (parsed === null) {
          continue;
        }
        const inferredBuilding: string = SJDClassroomParser.normalizeBuildingName(parsed.building);
        const side: string[] = SJDClassroomParser.inferTeachingExperimentSide(inferredBuilding, parsed.room);
        const building: string = side[0];
        const room: string = side[1];
        if (!SJDClassroomParser.originalBuildings.includes(building)) {
          continue;
        }
        const roomName: string | null = SJDClassroomParser.extractRoomName(room, building);
        if (roomName === null) {
          continue;
        }
        const key: string = building + '-' + roomName;
        const existing: RoomAccumulator | undefined = roomMap.get(key);
        if (existing === undefined) {
          roomMap.set(key, new RoomAccumulator(key, building, roomName, key, parsed.size));
        } else {
          if (existing.size === null) {
            existing.size = parsed.size;
          }
        }
        const accumulator: RoomAccumulator = roomMap.get(key) as RoomAccumulator;
        accumulator.availableSlots.add(slot);
      }
    }
    const rooms: Classroom[] = [];
    for (const entry of roomMap.values()) {
      const slots: number[] = [];
      for (const slot of entry.availableSlots) {
        slots.push(slot);
      }
      slots.sort((a: number, b: number) => a - b);
      rooms.push(new Classroom(
        entry.id, entry.building, entry.room, entry.name, entry.size, '', slots, 'sjd'));
    }
    rooms.sort((lhs: Classroom, rhs: Classroom) => {
      if (lhs.building !== rhs.building) {
        return lhs.building < rhs.building ? -1 : 1;
      }
      return lhs.room < rhs.room ? -1 : (lhs.room > rhs.room ? 1 : 0);
    });
    return new CampusClassrooms(campusID, campusName, targetDate, fetchedAt, true, 'sjd', rooms);
  }

  private static parseClassroom(raw: string): ParsedClassroom | null {
    let clean: string = raw.trim();
    if (clean.length === 0) {
      return null;
    }
    const sizeText: string | null = RegexUtil.firstCapture(clean, '[（(]\\s*(\\d+)\\s*[）)]');
    const size: number | null = sizeText === null ? null : Number(sizeText);
    const sizeIndex: number | null = RegexUtil.firstMatchIndex(clean, '[（(]\\s*\\d+\\s*[）)]');
    if (sizeIndex !== null) {
      clean = clean.substring(0, sizeIndex).trim();
    }
    clean = SJDClassroomParser.normalizeSeparators(clean);
    const parts: string[] = clean.split('-')
      .map((value: string) => value.trim())
      .filter((value: string) => value.length > 0);
    let building: string;
    let room: string;
    if (parts.length >= 3 && SJDClassroomParser.campusPrefixes.includes(parts[0])) {
      const roomIndex: number = clean.indexOf(parts[2]);
      building = clean.substring(0, roomIndex);
      building = SJDClassroomParser.trimSeparators(building);
      room = clean.substring(roomIndex).trim();
    } else {
      const separator: number = clean.indexOf('-');
      if (separator >= 0) {
        building = clean.substring(0, separator).trim();
        room = clean.substring(separator + 1).trim();
      } else {
        building = '未知教学楼';
        room = clean;
      }
    }
    building = building.length === 0 ? '未知教学楼' : building;
    room = room.length === 0 ? clean : room;
    return new ParsedClassroom(building, room, size);
  }

  private static normalizeBuildingName(value: string): string {
    let normalized: string = SJDClassroomParser.normalizeSeparators(value.trim());
    for (const prefix of SJDClassroomParser.campusPrefixes) {
      const fullPrefix: string = prefix + '-';
      if (normalized.startsWith(fullPrefix)) {
        normalized = normalized.substring(fullPrefix.length).trim();
        break;
      }
    }
    const compact: string = normalized.replace(/ /g, '').replace(/　/g, '');
    if (compact === '1' || compact === '教一楼') {
      return '教1';
    }
    if (compact === '2' || compact === '教二楼') {
      return '教2';
    }
    if (compact === '3' || compact === '教三楼') {
      return '教3';
    }
    if (compact === '4' || compact === '教四楼') {
      return '教4';
    }
    if (compact === '未来学习大楼') {
      return '主楼';
    }
    if (SJDClassroomParser.northBuildings.includes(compact)) {
      return '综合教学楼N';
    }
    if (SJDClassroomParser.southBuildings.includes(compact)) {
      return '综合教学楼S';
    }
    if (SJDClassroomParser.experimentNorthBuildings.includes(compact)) {
      return '教学实验综合楼N';
    }
    if (SJDClassroomParser.experimentSouthBuildings.includes(compact)) {
      return '教学实验综合楼S';
    }
    if (compact === '智慧楼' || compact === '智慧教室楼' || compact === '智慧教室') {
      return '智慧教学楼';
    }
    if (compact.length === 0) {
      return '未知教学楼';
    }
    return normalized.trim();
  }

  // 返回 [building, room]：教学实验综合楼未分栋时按教室前缀 N/S/北/南 推断。
  private static inferTeachingExperimentSide(building: string, room: string): string[] {
    if (building !== '教学实验综合楼') {
      return [building, room];
    }
    const clean: string = SJDClassroomParser.normalizeSeparators(room.trim())
      .replace(/ /g, '')
      .replace(/　/g, '');
    if (clean.length === 0) {
      return [building, room];
    }
    const side: string = clean.charAt(0);
    let rest: string = clean.substring(1);
    while (rest.startsWith('-')) {
      rest = rest.substring(1);
    }
    if (rest.length === 0) {
      return [building, room];
    }
    const first: string = rest.charAt(0);
    if (!(first >= '0' && first <= '9')) {
      return [building, room];
    }
    if (side === 'N' || side === 'n' || side === '北') {
      return ['教学实验综合楼N', rest];
    }
    if (side === 'S' || side === 's' || side === '南') {
      return ['教学实验综合楼S', rest];
    }
    return [building, room];
  }

  private static extractRoomName(value: string, building: string): string | null {
    let clean: string = SJDClassroomParser.normalizeSeparators(value.trim());
    if (building.startsWith('教')) {
      const number: string = building.substring(1);
      const prefixes: string[] = [number + '-', '教' + number + '-'];
      for (const prefix of prefixes) {
        if (clean.startsWith(prefix)) {
          clean = clean.substring(prefix.length).trim();
          break;
        }
      }
    }
    return RegexUtil.firstMatch(clean, '\\d{3}(?:-\\d{3})?');
  }

  private static nodeNameToSlot(value: string): number | null {
    const match: string | null = RegexUtil.firstMatch(value, '\\d+');
    if (match === null) {
      return null;
    }
    const number: number = Number(match);
    if (Number.isNaN(number) || number < 1 || number > 14) {
      return null;
    }
    return number - 1;
  }

  private static firstString(object: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value: string = JsonUtil.string(object[key]);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private static normalizeSeparators(value: string): string {
    return value
      .replace(/－/g, '-')
      .replace(/—/g, '-')
      .replace(/–/g, '-');
  }

  private static trimSeparators(value: string): string {
    let start: number = 0;
    let end: number = value.length;
    while (start < end && (value.charAt(start) === '-' || value.charAt(start) === ' ')) {
      start++;
    }
    while (end > start && (value.charAt(end - 1) === '-' || value.charAt(end - 1) === ' ')) {
      end--;
    }
    return value.substring(start, end);
  }
}
