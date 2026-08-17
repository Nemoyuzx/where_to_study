// 系统日历导入的纯逻辑（计划/草稿/同步计划/标记），对应 iOS 端
// CalendarImportLogic。无平台依赖，可被主机侧单元测试引用。
import { Course, ScheduleSnapshot, SlotMetadata } from '../common/Models';
import { StrictDates, DateParts } from '../common/StrictDates';
import { Utf8 } from '../common/Utf8';


export class CalendarEventDraft {
  readonly marker: string;
  readonly title: string;
  readonly location: string;
  readonly notes: string;
  readonly startEpochMs: number;
  readonly endEpochMs: number;

  constructor(marker: string, title: string, location: string, notes: string,
    startEpochMs: number, endEpochMs: number) {
    this.marker = marker;
    this.title = title;
    this.location = location;
    this.notes = notes;
    this.startEpochMs = startEpochMs;
    this.endEpochMs = endEpochMs;
  }
}

export class CalendarImportScope {
  readonly startEpochMs: number;
  readonly endEpochMs: number;

  constructor(startEpochMs: number, endEpochMs: number) {
    this.startEpochMs = startEpochMs;
    this.endEpochMs = endEpochMs;
  }

  contains(epochMs: number): boolean {
    return epochMs >= this.startEpochMs && epochMs < this.endEpochMs;
  }
}

export class CalendarScheduleImportPlan {
  readonly scope: CalendarImportScope;
  readonly drafts: CalendarEventDraft[];

  constructor(scope: CalendarImportScope, drafts: CalendarEventDraft[]) {
    this.scope = scope;
    this.drafts = drafts;
  }
}

export class CalendarExistingEvent {
  readonly identifier: string;
  readonly marker: string | null;
  readonly title: string;
  readonly location: string;
  readonly notes: string;
  readonly startEpochMs: number;
  readonly endEpochMs: number;
  readonly calendarIdentifier: string;
  readonly timeZoneIdentifier: string | null;
  readonly reminderMinutes: number[];

  constructor(identifier: string, marker: string | null, title: string, location: string,
    notes: string, startEpochMs: number, endEpochMs: number, calendarIdentifier: string,
    timeZoneIdentifier: string | null, reminderMinutes: number[]) {
    this.identifier = identifier;
    this.marker = marker;
    this.title = title;
    this.location = location;
    this.notes = notes;
    this.startEpochMs = startEpochMs;
    this.endEpochMs = endEpochMs;
    this.calendarIdentifier = calendarIdentifier;
    this.timeZoneIdentifier = timeZoneIdentifier;
    this.reminderMinutes = reminderMinutes;
  }
}

export class CalendarSyncMatch {
  readonly existingIdentifier: string;
  readonly draft: CalendarEventDraft;
  readonly needsUpdate: boolean;

  constructor(existingIdentifier: string, draft: CalendarEventDraft, needsUpdate: boolean) {
    this.existingIdentifier = existingIdentifier;
    this.draft = draft;
    this.needsUpdate = needsUpdate;
  }
}

export class CalendarSyncPlan {
  readonly inserts: CalendarEventDraft[];
  readonly matches: CalendarSyncMatch[];
  readonly deleteIdentifiers: string[];

  constructor(inserts: CalendarEventDraft[], matches: CalendarSyncMatch[], deleteIdentifiers: string[]) {
    this.inserts = inserts;
    this.matches = matches;
    this.deleteIdentifiers = deleteIdentifiers;
  }
}

export class CalendarImportResult {
  readonly inserted: number;
  readonly updated: number;
  readonly deleted: number;
  readonly unchanged: number;

  constructor(inserted: number, updated: number, deleted: number, unchanged: number) {
    this.inserted = inserted;
    this.updated = updated;
    this.deleted = deleted;
    this.unchanged = unchanged;
  }

  total(): number {
    return this.inserted + this.updated + this.deleted + this.unchanged;
  }
}

export class CalendarImportError extends Error {
  constructor(message: string) {
    super(message);
  }

  static noSchedule(): CalendarImportError {
    return new CalendarImportError('请先获取/刷新个人课表。');
  }

  static invalidTermStartDate(): CalendarImportError {
    return new CalendarImportError('第一周周一日期格式不正确。');
  }

  static invalidCourse(name: string): CalendarImportError {
    return new CalendarImportError('课程“' + name + '”的日期或节次信息不正确。');
  }

  static permissionDenied(): CalendarImportError {
    return new CalendarImportError('没有日历完整访问权限，请在系统设置中允许后重试。');
  }

  static noWritableCalendar(): CalendarImportError {
    return new CalendarImportError('系统中没有可写入的默认日历。');
  }
}

export class CalendarImportLogic {
  static readonly markerPrefix: string = 'where-to-study:event:';
  static readonly minimumTermWeeks: number = 18;
  static readonly reminderOffsetMinutes: number = -5;
  static readonly shanghaiTimeZoneId: string = 'Asia/Shanghai';

  static schedulePlan(schedule: ScheduleSnapshot, slots: SlotMetadata[] = SlotMetadata.defaults): CalendarScheduleImportPlan {
    const termStart: DateParts | null = StrictDates.parseDateString(schedule.termStartDate);
    if (termStart === null) {
      throw CalendarImportError.invalidTermStartDate();
    }
    let maximumWeek: number = CalendarImportLogic.minimumTermWeeks;
    for (const course of schedule.courses) {
      for (const week of course.weekNumbers) {
        if (week > 0 && week > maximumWeek) {
          maximumWeek = week;
        }
      }
    }
    if (maximumWeek > 53) {
      let courseName: string = '未知课程';
      for (const course of schedule.courses) {
        for (const week of course.weekNumbers) {
          if (week > 53) {
            courseName = course.name;
            break;
          }
        }
        if (courseName !== '未知课程') {
          break;
        }
      }
      throw CalendarImportError.invalidCourse(courseName);
    }
    const termWeeks: number = Math.max(CalendarImportLogic.minimumTermWeeks, maximumWeek);
    const termEnd: DateParts = StrictDates.addDays(termStart, termWeeks * 7);
    const drafts: CalendarEventDraft[] = CalendarImportLogic.eventDraftsFrom(schedule, termStart, slots);
    return new CalendarScheduleImportPlan(
      new CalendarImportScope(
        CalendarImportLogic.dayStartEpochMs(termStart),
        CalendarImportLogic.dayStartEpochMs(termEnd)
      ),
      drafts
    );
  }

  static eventDrafts(schedule: ScheduleSnapshot, slots: SlotMetadata[] = SlotMetadata.defaults): CalendarEventDraft[] {
    const termStart: DateParts | null = StrictDates.parseDateString(schedule.termStartDate);
    if (termStart === null) {
      throw CalendarImportError.invalidTermStartDate();
    }
    return CalendarImportLogic.eventDraftsFrom(schedule, termStart, slots);
  }

  private static eventDraftsFrom(
    schedule: ScheduleSnapshot, termStart: DateParts, slots: SlotMetadata[]
  ): CalendarEventDraft[] {
    const drafts: CalendarEventDraft[] = [];
    const markers: Set<string> = new Set<string>();
    for (const course of schedule.courses) {
      if (course.weekday < 1 || course.weekday > 7 ||
        course.startSlot < 0 || course.startSlot >= slots.length ||
        course.endSlot < 0 || course.endSlot >= slots.length ||
        course.startSlot > course.endSlot) {
        throw CalendarImportError.invalidCourse(course.name);
      }
      const startTime: string = slots[course.startSlot].start;
      const endTime: string = slots[course.endSlot].end;
      const weeks: number[] = [];
      const seen: Set<number> = new Set<number>();
      for (const week of course.weekNumbers) {
        if (week > 0 && !seen.has(week)) {
          seen.add(week);
          weeks.push(week);
        }
      }
      weeks.sort((a: number, b: number) => a - b);
      for (const week of weeks) {
        const dayOffset: number = (week - 1) * 7 + (course.weekday - 1);
        const day: DateParts = StrictDates.addDays(termStart, dayOffset);
        const startEpochMs: number | null = CalendarImportLogic.dateEpochMs(day, startTime);
        const endEpochMs: number | null = CalendarImportLogic.dateEpochMs(day, endTime);
        if (startEpochMs === null || endEpochMs === null || endEpochMs <= startEpochMs) {
          throw CalendarImportError.invalidCourse(course.name);
        }
        const marker: string = CalendarImportLogic.eventMarker(schedule.termID, course.id, week);
        if (markers.has(marker)) {
          continue;
        }
        markers.add(marker);
        const title: string = course.examWeekNumbers.includes(week) ? '试 ' + course.name : course.name;
        const detailLines: string[] = [];
        if (course.teacher.length > 0) {
          detailLines.push('教师：' + course.teacher);
        }
        if (course.sectionText.length > 0) {
          detailLines.push('节次：' + course.sectionText);
        }
        detailLines.push('由 Where To Study 导入');
        detailLines.push(marker);
        drafts.push(new CalendarEventDraft(
          marker, title, course.room, detailLines.join('\n'), startEpochMs, endEpochMs));
      }
    }
    drafts.sort((lhs: CalendarEventDraft, rhs: CalendarEventDraft) => {
      if (lhs.startEpochMs !== rhs.startEpochMs) {
        return lhs.startEpochMs - rhs.startEpochMs;
      }
      return lhs.marker < rhs.marker ? -1 : (lhs.marker > rhs.marker ? 1 : 0);
    });
    return drafts;
  }

  static syncPlan(
    drafts: CalendarEventDraft[], scope: CalendarImportScope,
    existingEvents: CalendarExistingEvent[], destinationCalendarIdentifier: string
  ): CalendarSyncPlan {
    const ownedEvents: CalendarExistingEvent[] = [];
    for (const event of existingEvents) {
      if (event.marker !== null && event.marker.startsWith(CalendarImportLogic.markerPrefix)) {
        ownedEvents.push(event);
      }
    }
    const scopedOwnedEvents: CalendarExistingEvent[] = [];
    for (const event of ownedEvents) {
      if (scope.contains(event.startEpochMs)) {
        scopedOwnedEvents.push(event);
      }
    }
    const desiredMarkers: Set<string> = new Set<string>();
    for (const draft of drafts) {
      desiredMarkers.add(draft.marker);
    }
    const eventsByMarker: Map<string, CalendarExistingEvent[]> = new Map<string, CalendarExistingEvent[]>();
    for (const event of ownedEvents) {
      if (event.marker === null) {
        continue;
      }
      const list: CalendarExistingEvent[] | undefined = eventsByMarker.get(event.marker);
      if (list === undefined) {
        eventsByMarker.set(event.marker, [event]);
      } else {
        list.push(event);
      }
    }
    for (const list of eventsByMarker.values()) {
      list.sort((lhs: CalendarExistingEvent, rhs: CalendarExistingEvent) => {
        return lhs.identifier < rhs.identifier ? -1 : (lhs.identifier > rhs.identifier ? 1 : 0);
      });
    }

    const inserts: CalendarEventDraft[] = [];
    const matches: CalendarSyncMatch[] = [];
    const deleteIdentifiers: Set<string> = new Set<string>();
    for (const draft of drafts) {
      const candidates: CalendarExistingEvent[] | undefined = eventsByMarker.get(draft.marker);
      if (candidates === undefined || candidates.length === 0) {
        inserts.push(draft);
        continue;
      }
      let selected: CalendarExistingEvent | null = null;
      for (const candidate of candidates) {
        if (CalendarImportLogic.eventMatches(candidate, draft, destinationCalendarIdentifier)) {
          selected = candidate;
          break;
        }
      }
      if (selected === null) {
        selected = candidates[0];
      }
      const needsUpdate: boolean = !CalendarImportLogic.eventMatches(
        selected, draft, destinationCalendarIdentifier);
      matches.push(new CalendarSyncMatch(selected.identifier, draft, needsUpdate));
      for (const duplicate of candidates) {
        if (duplicate.identifier !== selected.identifier) {
          deleteIdentifiers.add(duplicate.identifier);
        }
      }
    }

    for (const event of scopedOwnedEvents) {
      if (event.marker !== null && !desiredMarkers.has(event.marker)) {
        deleteIdentifiers.add(event.identifier);
      }
    }

    const deleteList: string[] = [];
    for (const id of deleteIdentifiers) {
      deleteList.push(id);
    }
    deleteList.sort();
    return new CalendarSyncPlan(inserts, matches, deleteList);
  }

  static eventMarker(termID: string, courseID: string, week: number): string {
    const identity: string = termID + String.fromCharCode(0) + courseID + String.fromCharCode(0) + week.toString();
    return CalendarImportLogic.markerPrefix + Utf8.base64(Utf8.bytes(identity));
  }

  static markerInNotes(notes: string): string | null {
    const lines: string[] = notes.split('\n');
    for (const line of lines) {
      if (line.startsWith(CalendarImportLogic.markerPrefix)) {
        return line;
      }
    }
    return null;
  }

  private static eventMatches(
    event: CalendarExistingEvent, draft: CalendarEventDraft, destinationCalendarIdentifier: string
  ): boolean {
    return event.title === draft.title &&
      event.location === draft.location &&
      event.notes === draft.notes &&
      event.startEpochMs === draft.startEpochMs &&
      event.endEpochMs === draft.endEpochMs &&
      event.calendarIdentifier === destinationCalendarIdentifier &&
      event.timeZoneIdentifier === CalendarImportLogic.shanghaiTimeZoneId &&
      CalendarImportLogic.equalReminderMinutes(event.reminderMinutes, [CalendarImportLogic.reminderOffsetMinutes]);
  }

  private static equalReminderMinutes(lhs: number[], rhs: number[]): boolean {
    if (lhs.length !== rhs.length) {
      return false;
    }
    for (let i = 0; i < lhs.length; i++) {
      if (lhs[i] !== rhs[i]) {
        return false;
      }
    }
    return true;
  }

  private static dateEpochMs(day: DateParts, time: string): number | null {
    const parts: string[] = time.split(':');
    if (parts.length !== 2) {
      return null;
    }
    const hour: number = Number(parts[0]);
    const minute: number = Number(parts[1]);
    if (Number.isNaN(hour) || Number.isNaN(minute) || hour < 0 || hour > 23 ||
      minute < 0 || minute > 59) {
      return null;
    }
    const dayEpoch: number = StrictDates.epochDay(day.year, day.month, day.day);
    return dayEpoch * 86400000 + hour * 3600000 + minute * 60000 - 8 * 3600000;
  }

  private static dayStartEpochMs(day: DateParts): number {
    const dayEpoch: number = StrictDates.epochDay(day.year, day.month, day.day);
    return dayEpoch * 86400000 - 8 * 3600000;
  }
}
