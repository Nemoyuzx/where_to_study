// 系统日历导入纯逻辑（与 iOS CalendarImportTests 对齐的关键断言）。
import { describe, it, expect } from '@ohos/hypium';
import { ScheduleSnapshot } from '../main/ets/common/Models';
import {
  CalendarEventDraft, CalendarExistingEvent, CalendarImportLogic, CalendarSyncPlan
} from '../main/ets/calendar/CalendarImportLogic';
import { scheduleText } from './fixtures/schedule';

export default function calendarImportLogicTest() {
  describe('CalendarImportLogicTest', () => {
    it('event_drafts_expand_weekly_courses_with_markers', 0, () => {
      const snapshot: ScheduleSnapshot = ScheduleSnapshot.fromJson(
        JSON.parse(scheduleText) as Record<string, Object>);
      const drafts: CalendarEventDraft[] = CalendarImportLogic.eventDrafts(snapshot);
      expect(drafts.length > 0).assertTrue();
      const markers: Set<string> = new Set<string>();
      for (const draft of drafts) {
        expect(draft.marker.startsWith(CalendarImportLogic.markerPrefix)).assertTrue();
        expect(draft.startEpochMs < draft.endEpochMs).assertTrue();
        expect(draft.notes.includes('由 Where To Study 导入')).assertTrue();
        markers.add(draft.marker);
      }
      expect(markers.size).assertEqual(drafts.length);
    });

    it('event_drafts_reject_invalid_term_start', 0, () => {
      const snapshot: ScheduleSnapshot = ScheduleSnapshot.fromJson(
        JSON.parse(scheduleText) as Record<string, Object>);
      const invalid: ScheduleSnapshot = new ScheduleSnapshot(
        snapshot.termID, '2026-02-30', snapshot.fetchedAt, snapshot.courses);
      let threw: boolean = false;
      try {
        CalendarImportLogic.eventDrafts(invalid);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('sync_plan_inserts_all_when_calendar_empty', 0, () => {
      const snapshot: ScheduleSnapshot = ScheduleSnapshot.fromJson(
        JSON.parse(scheduleText) as Record<string, Object>);
      const drafts: CalendarEventDraft[] = CalendarImportLogic.eventDrafts(snapshot);
      const plan: CalendarSyncPlan = CalendarImportLogic.syncPlan(
        drafts, CalendarImportLogic.schedulePlan(snapshot).scope, [], '');
      expect(plan.inserts.length).assertEqual(drafts.length);
      expect(plan.matches.length).assertEqual(0);
      expect(plan.deleteIdentifiers.length).assertEqual(0);
    });

    it('sync_plan_keeps_matching_event_unchanged', 0, () => {
      const snapshot: ScheduleSnapshot = ScheduleSnapshot.fromJson(
        JSON.parse(scheduleText) as Record<string, Object>);
      const drafts: CalendarEventDraft[] = CalendarImportLogic.eventDrafts(snapshot);
      const first: CalendarEventDraft = drafts[0];
      const existing: CalendarExistingEvent = new CalendarExistingEvent(
        'id-1', first.marker, first.title, first.location, first.notes,
        first.startEpochMs, first.endEpochMs, '', 'Asia/Shanghai', [-5]);
      const plan: CalendarSyncPlan = CalendarImportLogic.syncPlan(
        drafts, CalendarImportLogic.schedulePlan(snapshot).scope, [existing], '');
      expect(plan.inserts.length).assertEqual(drafts.length - 1);
      expect(plan.matches.length).assertEqual(1);
      expect(plan.matches[0].needsUpdate).assertFalse();
    });

    it('marker_in_notes_finds_first_prefixed_line', 0, () => {
      expect(CalendarImportLogic.markerInNotes('教师：张三\n' +
        CalendarImportLogic.markerPrefix + 'abc\n其他'))
        .assertEqual(CalendarImportLogic.markerPrefix + 'abc');
      expect(CalendarImportLogic.markerInNotes('无标记')).assertNull();
    });
  });
}
