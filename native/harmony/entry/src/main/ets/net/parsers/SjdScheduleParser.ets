// 移动教务课表响应解析（纯模块，无平台依赖，可被主机侧单元测试引用）。
// 与 iOS 端 SJDScheduleParser 一一对应。
import { Course, ScheduleSnapshot, SlotMetadata } from '../../common/Models';
import { ScheduleLogic } from '../../common/ScheduleLogic';
import { StrictDates, DateParts } from '../../common/StrictDates';
import { JsonUtil } from '../../common/JsonUtil';
import { RegexUtil } from '../../common/RegexUtil';
import { Sha1 } from '../../common/Sha1';
import { ScheduleClientError } from '../SjdErrors';

export class SJDScheduleParser {
  static parse(
    currentData: string, curriculumData: string, fallbackTermID: string,
    fallbackTermStartDate: string, fetchedAt?: string
  ): ScheduleSnapshot {
    const at: string = fetchedAt === undefined ? StrictDates.formatFetchedAt(Date.now()) : fetchedAt;
    const current: Record<string, Object> | null = JsonUtil.parseObject(currentData);
    const curriculum: Record<string, Object> | null = JsonUtil.parseObject(curriculumData);
    if (current === null || curriculum === null) {
      throw ScheduleClientError.invalidResponse('移动教务课表返回为空。');
    }
    const currentItems: Object[] = JsonUtil.array(current['data']);
    const curriculumItems: Object[] = JsonUtil.array(curriculum['data']);
    if (currentItems.length === 0 || curriculumItems.length === 0) {
      throw ScheduleClientError.invalidResponse('移动教务课表返回为空。');
    }
    const currentRoot: Record<string, Object> = JsonUtil.record(currentItems[0]);
    const curriculumRoot: Record<string, Object> = JsonUtil.record(curriculumItems[0]);

    let termID: string = JsonUtil.string(currentRoot['semesterId']);
    if (termID.length === 0) {
      termID = JsonUtil.string(currentRoot['xnxq01id']);
    }
    if (termID.length === 0) {
      const topInfo: Object[] = JsonUtil.array(currentRoot['topInfo']);
      if (topInfo.length > 0) {
        const top: Record<string, Object> = JsonUtil.record(topInfo[0]);
        termID = JsonUtil.string(top['semesterId']);
        if (termID.length === 0) {
          termID = JsonUtil.string(top['xnxq01id']);
        }
      }
    }
    if (termID.length === 0) {
      termID = fallbackTermID;
    }
    const termStartDate: string = SJDScheduleParser.inferTermStartDate(currentRoot) === null ?
      fallbackTermStartDate : SJDScheduleParser.inferTermStartDate(currentRoot) as string;

    let rawRoot: Object = curriculumRoot['item'];
    if (rawRoot === undefined || rawRoot === null) {
      rawRoot = curriculumRoot['courses'];
    }
    if (rawRoot === undefined || rawRoot === null) {
      rawRoot = [];
    }
    const rawCourses: Record<string, Object>[] = [];
    SJDScheduleParser.collectCourses(rawRoot, rawCourses, 0);

    const seen: Set<string> = new Set<string>();
    const courses: Course[] = [];
    for (const raw of rawCourses) {
      const course: Course | null = SJDScheduleParser.parseCourse(raw);
      if (course === null || seen.has(course.id)) {
        continue;
      }
      seen.add(course.id);
      courses.push(course);
    }
    const withExamWeeks: Course[] = ScheduleLogic.applyingExamWeeks(courses);
    withExamWeeks.sort((lhs: Course, rhs: Course) => {
      if (lhs.weekday !== rhs.weekday) {
        return lhs.weekday - rhs.weekday;
      }
      if (lhs.startSlot !== rhs.startSlot) {
        return lhs.startSlot - rhs.startSlot;
      }
      return lhs.name < rhs.name ? -1 : (lhs.name > rhs.name ? 1 : 0);
    });
    return new ScheduleSnapshot(termID, termStartDate, at, withExamWeeks);
  }

  // 与 iOS 参考实现的 64 层一致：防止畸形响应导致栈溢出（BUG-011 修复）。
  static readonly maximumCollectionDepth: number = 64;

  private static collectCourses(value: Object, out: Record<string, Object>[], depth: number): void {
    if (value === undefined || value === null || depth > SJDScheduleParser.maximumCollectionDepth) {
      return;
    }
    if (Array.isArray(value)) {
      const arr: Object[] = value as Object[];
      for (const child of arr) {
        SJDScheduleParser.collectCourses(child, out, depth + 1);
      }
      return;
    }
    if (typeof value !== 'object') {
      return;
    }
    const dict: Record<string, Object> = value as Record<string, Object>;
    if (dict['courseName'] !== undefined || dict['jx0408id'] !== undefined) {
      out.push(dict);
      return;
    }
    const children: Object[] = Object.values(dict);
    for (const child of children) {
      SJDScheduleParser.collectCourses(child, out, depth + 1);
    }
  }

  private static parseCourse(raw: Record<string, Object>): Course | null {
    const slotPair: number[] | null = SJDScheduleParser.slots(raw);
    if (slotPair === null) {
      return null;
    }
    const startSlot: number = slotPair[0];
    const endSlot: number = slotPair[1];

    let weekdayText: string = JsonUtil.string(raw['weekDay']);
    if (weekdayText.length === 0) {
      weekdayText = JsonUtil.string(raw['classTime']);
    }
    if (weekdayText.length === 0) {
      return null;
    }
    let weekday: number = Number(weekdayText.charAt(0));
    if (Number.isNaN(weekday) || weekday < 1 || weekday > 7) {
      // 兼容中文星期（周X/星期X），避免整门课被静默丢弃（BUG-043 修复）。
      const chineseMatch: string | null = RegexUtil.firstCapture(weekdayText, '[周星期]([一二三四五六日天])');
      if (chineseMatch !== null) {
        const chineseIndex: number = '一二三四五六日天'.indexOf(chineseMatch);
        if (chineseIndex >= 0) {
          weekday = chineseIndex + 1;
        }
      }
    }
    if (Number.isNaN(weekday) || weekday < 1 || weekday > 7) {
      return null;
    }

    let name: string = JsonUtil.string(raw['courseName']).trim();
    if (name.length === 0) {
      name = '未命名课程';
    }
    const teacher: string = JsonUtil.string(raw['teacherName']).trim();
    const building: string = JsonUtil.string(raw['buildingName']).trim();
    let rawRoom: string = JsonUtil.string(raw['classroomName']);
    if (rawRoom.trim().length === 0) {
      rawRoom = JsonUtil.string(raw['location']);
    }
    rawRoom = rawRoom.trim();
    const room: string = SJDScheduleParser.normalizeCourseRoom(rawRoom);
    let location: string;
    if (building.length > 0 && room.length > 0 && !room.includes(building)) {
      location = building + '-' + room;
    } else {
      location = room.length === 0 ? building : room;
    }

    let weekText: string = JsonUtil.string(raw['classWeek']);
    if (weekText.trim().length === 0) {
      weekText = JsonUtil.string(raw['classWeekDetails']);
    }
    weekText = weekText.trim();
    const weeks: number[] = SJDScheduleParser.weekNumbers(raw);

    const stable: string = [
      JsonUtil.string(raw['jx0408id']), name, teacher, location, weekText,
      weekday.toString(), startSlot.toString(), endSlot.toString()
    ].join('|');
    const id: string = Sha1.hexOfUtf8(stable).substring(0, 12);

    let startTime: string = JsonUtil.string(raw['startTime']);
    if (startTime.length === 0) {
      startTime = SlotMetadata.defaults[startSlot].start;
    }
    let endTime: string = JsonUtil.string(raw['endTIme']);
    if (endTime.length === 0) {
      endTime = JsonUtil.string(raw['endTime']);
    }
    if (endTime.length === 0) {
      endTime = SlotMetadata.defaults[endSlot].end;
    }

    return new Course(
      id, name, teacher, location, weekText, weeks, [], weekday,
      startSlot, endSlot, (startSlot + 1).toString() + '-' + (endSlot + 1).toString() + '节',
      startTime + '-' + endTime
    );
  }

  // 3-335 规范化为 335；双门教室号（202-203）与三位以上前缀完整保留。
  static normalizeCourseRoom(value: string): string {
    const normalized: string = value
      .replace(/－/g, '-')
      .replace(/—/g, '-')
      .replace(/–/g, '-')
      .trim();
    const parts: string[] = normalized.split('-');
    if (parts.length !== 2) {
      return normalized;
    }
    const first: string = parts[0];
    const buildingPrefix: string = first.startsWith('教') ? first.substring(1) : first;
    const digitRe: RegExp = new RegExp('^\\d{3}$');
    if (buildingPrefix.length === 1 && buildingPrefix >= '0' && buildingPrefix <= '9' &&
      parts[1].length === 3 && digitRe.test(parts[1])) {
      return parts[1];
    }
    return normalized;
  }

  private static weekNumbers(raw: Record<string, Object>): number[] {
    const details: string = JsonUtil.string(raw['classWeekDetails']);
    const explicit: number[] = RegexUtil.integerMatches(details);
    if (explicit.length > 0) {
      const seen: Set<number> = new Set<number>(explicit);
      const result: number[] = [];
      for (const value of seen) {
        result.push(value);
      }
      result.sort((a: number, b: number) => a - b);
      return result;
    }

    const text: string = JsonUtil.string(raw['classWeek'])
      .replace(/周/g, '')
      .replace(/ /g, '');
    const odd: boolean = text.includes('单');
    const even: boolean = text.includes('双');
    const weeks: number[] = [];
    const items: string[] = text.replace(/，/g, ',').split(',');
    for (const item of items) {
      const numbers: number[] = RegexUtil.integerMatches(item);
      if (numbers.length >= 2) {
        for (let n = numbers[0]; n <= numbers[1]; n++) {
          weeks.push(n);
        }
      } else if (numbers.length === 1) {
        weeks.push(numbers[0]);
      }
    }
    const seen: Set<number> = new Set<number>();
    const result: number[] = [];
    for (const week of weeks) {
      const keep: boolean = (!odd || week % 2 !== 0) && (!even || week % 2 === 0);
      if (keep && !seen.has(week)) {
        seen.add(week);
        result.push(week);
      }
    }
    result.sort((a: number, b: number) => a - b);
    return result;
  }

  private static slots(raw: Record<string, Object>): number[] | null {
    const classTime: string = JsonUtil.string(raw['classTime']).substring(1);
    let nodes: number[] = RegexUtil.integerMatchesOf(classTime, '\\d{2}');
    if (nodes.length === 0) {
      nodes = RegexUtil.integerMatches(JsonUtil.string(raw['weekNoteDetail']));
    }
    if (nodes.length === 0) {
      return null;
    }
    let minimum: number = nodes[0];
    let maximum: number = nodes[0];
    for (const node of nodes) {
      if (node < minimum) {
        minimum = node;
      }
      if (node > maximum) {
        maximum = node;
      }
    }
    if (minimum < 1 || maximum > SlotMetadata.defaults.length || minimum > maximum) {
      return null;
    }
    return [minimum - 1, maximum - 1];
  }

  private static inferTermStartDate(root: Record<string, Object>): string | null {
    let dated: Record<string, Object> | null = null;
    const dateList: Object[] = JsonUtil.array(root['date']);
    for (const item of dateList) {
      const record: Record<string, Object> = JsonUtil.record(item);
      if (record['mxrq'] !== undefined && JsonUtil.string(record['zc']) !== 'all') {
        dated = record;
        break;
      }
    }
    if (dated === null) {
      return null;
    }
    let weekText: string = JsonUtil.string(dated['zc']);
    if (weekText.length === 0) {
      weekText = JsonUtil.string(root['week']);
    }
    if (weekText.length === 0) {
      const topInfo: Object[] = JsonUtil.array(root['topInfo']);
      if (topInfo.length > 0) {
        weekText = JsonUtil.string(JsonUtil.record(topInfo[0])['week']);
      }
    }
    if (weekText.length === 0) {
      return null;
    }
    const week: number = Number(weekText);
    // week=0 是开学前一周的真实响应；该周周一向后 7 天即第一周周一。
    if (Number.isNaN(week) || week < 0) {
      return null;
    }
    const day: DateParts | null = StrictDates.parseDateString(JsonUtil.string(dated['mxrq']));
    if (day === null) {
      return null;
    }
    const mondayBasedWeekday: number = StrictDates.weekdayMonday1(day);
    let weekday: number = mondayBasedWeekday;
    const xqidText: string = JsonUtil.string(dated['xqid']);
    if (xqidText.length > 0) {
      const parsed: number = Number(xqidText);
      if (!Number.isNaN(parsed)) {
        // 移动教务以 0 表示周日，其余为周一=1..周六=6。
        weekday = parsed === 0 ? 7 : (parsed >= 1 && parsed <= 7 ? parsed : mondayBasedWeekday);
      }
    }
    const monday: DateParts = StrictDates.addDays(day, -(weekday - 1));
    const termStart: DateParts = StrictDates.addDays(monday, -((week - 1) * 7));
    return StrictDates.formatDateParts(termStart);
  }
}
