// 系统日历导入纯逻辑（与 iOS CalendarImportTests 对齐的关键断言）。
import { describe, it, expect } from '@ohos/hypium';
import { ScheduleSnapshot } from '../main/ets/common/Models';
import {
  CalendarEventDraft, CalendarExistingEvent, CalendarImportLogic, CalendarSyncPlan
} from '../main/ets/calendar/CalendarImportLogic';
import { scheduleText } from './fixtures/schedule';
import {
  PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineSource
} from '../main/ets/net/CalendarDailyInfoClient';

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

    it('favorite_drafts_keep_stable_markers_and_exact_deadline_instant', 0, () => {
      const item: PublicDeadlineItem = favorite('contest-42',
        '2026-05-01T23:59:00.123+08:00');
      const first: CalendarEventDraft[] = CalendarImportLogic.favoriteDrafts([item, item]);
      const second: CalendarEventDraft[] = CalendarImportLogic.favoriteDrafts([item]);
      expect(first.length).assertEqual(1);
      expect(first[0].marker).assertEqual(second[0].marker);
      expect(first[0].marker.startsWith(CalendarImportLogic.favoriteMarkerPrefix)).assertTrue();
      expect(first[0].endEpochMs - first[0].startEpochMs).assertEqual(30 * 60 * 1000);
      expect(first[0].notes.includes('由 Where To Study 导入')).assertTrue();
      expect(CalendarImportLogic.favoritePlan([item]).drafts.length).assertEqual(1);
    });

    it('favorite_sync_updates_one_copy_without_touching_course_markers', 0, () => {
      const draft: CalendarEventDraft[] = CalendarImportLogic.favoriteDrafts([
        favorite('keep', '2026-05-01T23:59:00+08:00')]);
      const existing: CalendarExistingEvent[] = [
        existingEvent('favorite-1', draft[0]),
        existingEvent('favorite-2', draft[0]),
        new CalendarExistingEvent(
          'course-1', CalendarImportLogic.markerPrefix + 'course', '课程', '', '',
          draft[0].startEpochMs, draft[0].endEpochMs, '', 'Asia/Shanghai', [-5])
      ];
      const plan: CalendarSyncPlan = CalendarImportLogic.syncPlan(
        draft, CalendarImportLogic.favoritePlan([
          favorite('keep', '2026-05-01T23:59:00+08:00')]).scope,
        existing, '', CalendarImportLogic.favoriteMarkerPrefix);
      expect(plan.matches.length).assertEqual(1);
      expect(plan.deleteIdentifiers.length).assertEqual(1);
      expect(plan.deleteIdentifiers[0]).assertEqual('favorite-2');
    });
  });
}

function favorite(id: string, deadline: string): PublicDeadlineItem {
  return new PublicDeadlineItem(id, '收藏日程 ' + id, PublicDeadlineKind.competition,
    PublicDeadlineSource.contestDDL, deadline, '测试组织方', 'https://example.com/' + id,
    'Contest DDL', 'https://example.com');
}

function existingEvent(identifier: string, draft: CalendarEventDraft): CalendarExistingEvent {
  return new CalendarExistingEvent(
    identifier, draft.marker, draft.title, draft.location, draft.notes,
    draft.startEpochMs, draft.endEpochMs, '', 'Asia/Shanghai', [-5]);
}
