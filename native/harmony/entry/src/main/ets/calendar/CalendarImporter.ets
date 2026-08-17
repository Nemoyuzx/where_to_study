// 系统日历导入的鸿蒙实现，对应 iOS 端 EventKitCalendarImporter。
// 纯逻辑见 CalendarImportLogic.ets。
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, Permissions, PermissionRequestResult } from '@kit.AbilityKit';
import { ScheduleSnapshot } from '../common/Models';
import { AppContext } from '../store/AppContext';
import {
  CalendarEventDraft, CalendarExistingEvent, CalendarImportError, CalendarImportLogic,
  CalendarImportResult, CalendarImportScope, CalendarScheduleImportPlan, CalendarSyncPlan
} from './CalendarImportLogic';

export interface CalendarImporting {
  importSchedule(schedule: ScheduleSnapshot): Promise<CalendarImportResult>;
}

export class HarmonyCalendarImporter implements CalendarImporting {
  async importSchedule(schedule: ScheduleSnapshot): Promise<CalendarImportResult> {
    const importPlan: CalendarScheduleImportPlan = CalendarImportLogic.schedulePlan(schedule);
    const granted: boolean = await HarmonyCalendarImporter.requestAccess();
    if (!granted) {
      throw CalendarImportError.permissionDenied();
    }
    return await HarmonyCalendarImporter.write(importPlan);
  }

  private static async requestAccess(): Promise<boolean> {
    const permissions: Array<Permissions> = [
      'ohos.permission.READ_CALENDAR',
      'ohos.permission.WRITE_CALENDAR'
    ];
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(AppContext.get(), permissions);
      return result.authResults.length === permissions.length &&
        result.authResults.every((value: number) => value === 0);
    } catch (e) {
      return false;
    }
  }

  private static async write(importPlan: CalendarScheduleImportPlan): Promise<CalendarImportResult> {
    const calendar: calendarManager.Calendar =
      await calendarManager.getCalendarManager(AppContext.get()).getCalendar();

    const searchStart: number = importPlan.scope.startEpochMs - 366 * 24 * 60 * 60 * 1000;
    const searchEnd: number = importPlan.scope.endEpochMs + 366 * 24 * 60 * 60 * 1000;
    const filter: calendarManager.EventFilter = {
      startTime: searchStart,
      endTime: searchEnd
    };
    const events: Array<calendarManager.Event> = await calendar.getEvents(filter);

    const indexed: CalendarExistingEvent[] = [];
    const eventById: Map<string, calendarManager.Event> = new Map<string, calendarManager.Event>();
    let index: number = 0;
    for (const event of events) {
      const identifier: string = event.identifier !== undefined ? event.identifier :
        (event.id !== undefined ? event.id.toString() : 'index-' + index.toString());
      const reminderMinutes: number[] = [];
      if (event.reminderTime !== undefined) {
        for (const value of event.reminderTime) {
          reminderMinutes.push(value);
        }
        reminderMinutes.sort((a: number, b: number) => a - b);
      }
      const snapshot: CalendarExistingEvent = new CalendarExistingEvent(
        identifier,
        event.description !== undefined ?
          CalendarImportLogic.markerInNotes(event.description) : null,
        event.title !== undefined ? event.title : '',
        event.location !== undefined && event.location.location !== undefined ?
          event.location.location as string : '',
        event.description !== undefined ? event.description : '',
        event.startTime,
        event.endTime,
        '',
        event.timeZone !== undefined ? event.timeZone : null,
        reminderMinutes
      );
      indexed.push(snapshot);
      eventById.set(identifier, event);
      index++;
    }

    const syncPlan: CalendarSyncPlan = CalendarImportLogic.syncPlan(
      importPlan.drafts, importPlan.scope, indexed, '');

    for (const identifier of syncPlan.deleteIdentifiers) {
      const event: calendarManager.Event | undefined = eventById.get(identifier);
      if (event === undefined || event.id === undefined) {
        throw new Error('系统日历在同步期间发生变化，请重试。');
      }
      try {
        await calendar.deleteEvent(event.id);
      } catch (e) {
        throw new Error('系统日历在同步期间发生变化，请重试。');
      }
    }

    let updated: number = 0;
    let unchanged: number = 0;
    for (const match of syncPlan.matches) {
      const event: calendarManager.Event | undefined = eventById.get(match.existingIdentifier);
      if (event === undefined || event.id === undefined) {
        throw new Error('系统日历在同步期间发生变化，请重试。');
      }
      if (match.needsUpdate) {
        HarmonyCalendarImporter.apply(match.draft, event);
        try {
          await calendar.updateEvent(event);
        } catch (e) {
          throw new Error('系统日历在同步期间发生变化，请重试。');
        }
        updated++;
      } else {
        unchanged++;
      }
    }

    for (const draft of syncPlan.inserts) {
      const event: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL,
        title: draft.title,
        location: { location: draft.location },
        description: draft.notes,
        startTime: draft.startEpochMs,
        endTime: draft.endEpochMs,
        isAllDay: false,
        timeZone: CalendarImportLogic.shanghaiTimeZoneId,
        reminderTime: [CalendarImportLogic.reminderOffsetMinutes]
      };
      await calendar.addEvent(event);
    }

    const inserted: number = syncPlan.inserts.length;
    const deleted: number = syncPlan.deleteIdentifiers.length;
    return new CalendarImportResult(inserted, updated, deleted, unchanged);
  }

  private static apply(draft: CalendarEventDraft, event: calendarManager.Event): void {
    event.title = draft.title;
    event.location = { location: draft.location };
    event.description = draft.notes;
    event.startTime = draft.startEpochMs;
    event.endTime = draft.endEpochMs;
    event.timeZone = CalendarImportLogic.shanghaiTimeZoneId;
    event.reminderTime = [CalendarImportLogic.reminderOffsetMinutes];
  }
}
