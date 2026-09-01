import { describe, it, expect } from '@ohos/hypium';
import {
  ImportantEventFilter, ImportantEventQueryLogic, QueryPageContract, QueryPageTab
} from '../main/ets/common/QueryLogic';
import { DeadlineVisual, DeadlineVisualKind } from '../main/ets/common/DeadlineVisual';
import {
  PublicDeadlineItem, PublicDeadlineKind, PublicDeadlineResponseParser,
  PublicDeadlineSource
} from '../main/ets/net/CalendarDailyInfoClient';

export default function queryLogicTest() {
  describe('QueryLogicTest', () => {
    it('query_contract_has_two_segmented_tabs_and_all_categories', 0, () => {
      expect(QueryPageContract.tabs.length).assertEqual(2);
      expect(QueryPageContract.tabs[0]).assertEqual(QueryPageTab.shuttle);
      expect(QueryPageContract.tabs[1]).assertEqual(QueryPageTab.events);
      expect(QueryPageContract.filters.indexOf(ImportantEventFilter.conference) >= 0).assertTrue();
      expect(QueryPageContract.filters.indexOf(ImportantEventFilter.schoolNotice) >= 0).assertTrue();
      expect(QueryPageContract.tabAccessibilityID(QueryPageTab.events))
        .assertEqual('query.tab.events');
    });

    it('all_supported_public_types_enter_the_catalog_but_assignment_does_not', 0, () => {
      const index: Map<string, PublicDeadlineItem[]> = PublicDeadlineResponseParser.parseIndex('{' +
        '"items":[' +
        event('competition', 'Competition', '2026-09-02T12:00:00+08:00') + ',' +
        event('conference', 'Conference', '2026-09-03T12:00:00+08:00') + ',' +
        event('journal_special_issue', 'Journal', '2026-09-04T12:00:00+08:00') + ',' +
        event('hackathon', 'Hackathon', '2026-09-05T12:00:00+08:00') + ',' +
        event('summer_camp', 'Summer', '2026-09-06T12:00:00+08:00') + ',' +
        event('pre_admission', 'Admission', '2026-09-07T12:00:00+08:00') + ',' +
        event('assignment', 'Assignment', '2026-09-08T12:00:00+08:00') +
        ']}');
      const items: PublicDeadlineItem[] = [];
      index.forEach((dated: PublicDeadlineItem[]): void => {
        for (const item of dated) {
          items.push(item);
        }
      });
      expect(items.length).assertEqual(6);
      expect(items.some((item: PublicDeadlineItem): boolean =>
        item.kind === PublicDeadlineKind.conference)).assertTrue();
      expect(items.some((item: PublicDeadlineItem): boolean => item.name === 'Assignment'))
        .assertFalse();
    });

    it('filters_search_fields_and_sorts_deadlines_ascending', 0, () => {
      const remote: PublicDeadlineItem[] = [
        new PublicDeadlineItem('later', '系统会议', PublicDeadlineKind.conference,
          PublicDeadlineSource.contestDDL, '2026-10-02T12:00:00+08:00', 'IEEE', null,
          'CCFDDL', 'https://ccfddl.com/', ['人工智能'], ['CCF A'], 'CCF A',
          'Phoenix', 'Systems research', 'Researchers', 'Official site first'),
        new PublicDeadlineItem('early', '算法竞赛', PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-09-02T12:00:00+08:00', 'ACM', null),
        new PublicDeadlineItem('school', '校内创新赛', PublicDeadlineKind.competition,
          PublicDeadlineSource.schoolNotice, '2026-09-08T12:00:00+08:00', '北邮', null)
      ];
      const result: PublicDeadlineItem[] = ImportantEventQueryLogic.filter(
        ImportantEventQueryLogic.mergeCatalog(remote, []), 'Phoenix',
        ImportantEventFilter.conference, '人工智能', false,
        new Date('2026-08-31T00:00:00+08:00').getTime());
      expect(result.length).assertEqual(1);
      expect(result[0].id).assertEqual('later');
      const all: PublicDeadlineItem[] = ImportantEventQueryLogic.filter(
        remote, '', ImportantEventFilter.all, '', false,
        new Date('2026-08-31T00:00:00+08:00').getTime());
      expect(all[0].id).assertEqual('early');
      expect(all[2].id).assertEqual('later');
      expect(ImportantEventQueryLogic.availableCategories(remote,
        ImportantEventFilter.all, false,
        new Date('2026-08-31T00:00:00+08:00').getTime())[0]).assertEqual('人工智能');
    });

    it('only_exposes_event_types_present_in_remote_or_favorites', 0, () => {
      const remote: PublicDeadlineItem[] = [
        new PublicDeadlineItem('contest', 'Contest', PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-09-02T12:00:00+08:00', null, null),
        new PublicDeadlineItem('conference', 'Conference', PublicDeadlineKind.conference,
          PublicDeadlineSource.contestDDL, '2026-09-03T12:00:00+08:00', null, null)
      ];
      let filters: ImportantEventFilter[] = ImportantEventQueryLogic.availableFilters(
        ImportantEventQueryLogic.mergeCatalog(remote, []));
      expect(filters.indexOf(ImportantEventFilter.competition) >= 0).assertTrue();
      expect(filters.indexOf(ImportantEventFilter.conference) >= 0).assertTrue();
      expect(filters.indexOf(ImportantEventFilter.journalSpecialIssue) < 0).assertTrue();
      expect(filters.indexOf(ImportantEventFilter.preAdmission) < 0).assertTrue();

      const favorite: PublicDeadlineItem = new PublicDeadlineItem(
        'favorite-journal', 'Favorite Journal', PublicDeadlineKind.journalSpecialIssue,
        PublicDeadlineSource.contestDDL, '2026-10-04T12:00:00+08:00', null, null);
      filters = ImportantEventQueryLogic.availableFilters(
        ImportantEventQueryLogic.mergeCatalog(remote, [favorite]));
      expect(filters.indexOf(ImportantEventFilter.journalSpecialIssue) >= 0).assertTrue();
      expect(filters.indexOf(ImportantEventFilter.preAdmission) < 0).assertTrue();
    });

    it('metadata_categories_follow_the_selected_event_type', 0, () => {
      const items: PublicDeadlineItem[] = [
        new PublicDeadlineItem('contest', 'Contest', PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-09-02T12:00:00+08:00', null, null,
          null, null, ['程序设计']),
        new PublicDeadlineItem('conference', 'Conference', PublicDeadlineKind.conference,
          PublicDeadlineSource.contestDDL, '2026-09-03T12:00:00+08:00', null, null,
          null, null, ['人工智能'])
      ];
      const categories: string[] = ImportantEventQueryLogic.availableCategories(
        items, ImportantEventFilter.conference, false,
        new Date('2026-08-31T00:00:00+08:00').getTime());
      expect(categories.length).assertEqual(1);
      expect(categories[0]).assertEqual('人工智能');
    });

    it('ended_and_archived_events_are_hidden_by_default', 0, () => {
      const items: PublicDeadlineItem[] = [
        new PublicDeadlineItem('past', 'Past', PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-08-01T12:00:00+08:00', null, null),
        new PublicDeadlineItem('active', 'Active', PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-09-02T12:00:00+08:00', null, null),
        new PublicDeadlineItem('archived', 'Archived', PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-09-03T12:00:00+08:00', null, null,
          null, null, [], [], null, null, null, null, null, true)
      ];
      const now: number = new Date('2026-08-31T00:00:00+08:00').getTime();
      const current: PublicDeadlineItem[] = ImportantEventQueryLogic.filter(
        items, '', ImportantEventFilter.all, '', false, now);
      expect(current.length).assertEqual(1);
      expect(current[0].id).assertEqual('active');
      const all: PublicDeadlineItem[] = ImportantEventQueryLogic.filter(
        items, '', ImportantEventFilter.all, '', true, now);
      expect(all.length).assertEqual(3);
    });

    it('important_events_render_in_twenty_item_batches_near_the_list_end', 0, () => {
      const items: PublicDeadlineItem[] = [];
      for (let index: number = 0; index < 45; index++) {
        items.push(new PublicDeadlineItem('item-' + index.toString(),
          'Item ' + index.toString(), PublicDeadlineKind.competition,
          PublicDeadlineSource.contestDDL, '2026-09-30T12:00:00+08:00', null, null));
      }
      const initial: number = ImportantEventQueryLogic.initialRequestedCount();
      expect(initial).assertEqual(20);
      expect(ImportantEventQueryLogic.visiblePage(items, initial).length).assertEqual(20);
      expect(ImportantEventQueryLogic.shouldAppend(15, 20, 45)).assertFalse();
      expect(ImportantEventQueryLogic.shouldAppend(16, 20, 45)).assertTrue();
      const second: number = ImportantEventQueryLogic.nextRequestedCount(initial, items.length);
      expect(second).assertEqual(40);
      expect(ImportantEventQueryLogic.visiblePage(items, second).length).assertEqual(40);
      const finalCount: number = ImportantEventQueryLogic.nextRequestedCount(second, items.length);
      expect(finalCount).assertEqual(45);
      expect(ImportantEventQueryLogic.shouldAppend(44, 45, 45)).assertFalse();
      // 搜索/筛选/数据变化均回到这个纯逻辑入口，不继承上一份结果的 40/45 条额度。
      expect(ImportantEventQueryLogic.visiblePage(items, initial).length).assertEqual(20);
    });

    it('deadline_visual_mapping_keeps_switch_groups_and_two_layer_priority', 0, () => {
      const competition: PublicDeadlineItem = visualEvent('competition',
        PublicDeadlineKind.competition, PublicDeadlineSource.contestDDL);
      const conference: PublicDeadlineItem = visualEvent('conference',
        PublicDeadlineKind.conference, PublicDeadlineSource.contestDDL);
      const journal: PublicDeadlineItem = visualEvent('journal',
        PublicDeadlineKind.journalSpecialIssue, PublicDeadlineSource.contestDDL);
      const school: PublicDeadlineItem = visualEvent('school',
        PublicDeadlineKind.competition, PublicDeadlineSource.schoolNotice);
      const summer: PublicDeadlineItem = visualEvent('summer',
        PublicDeadlineKind.summerCamp, PublicDeadlineSource.contestDDL);
      const admission: PublicDeadlineItem = visualEvent('admission',
        PublicDeadlineKind.preAdmission, PublicDeadlineSource.contestDDL);
      const hackathon: PublicDeadlineItem = visualEvent('hackathon',
        PublicDeadlineKind.hackathon, PublicDeadlineSource.contestDDL);
      const custom: PublicDeadlineItem = visualEvent('custom',
        PublicDeadlineKind.competition, PublicDeadlineSource.custom);
      expect(DeadlineVisual.kind(competition)).assertEqual(DeadlineVisualKind.competition);
      expect(DeadlineVisual.kind(conference)).assertEqual(DeadlineVisualKind.conferenceOrJournal);
      expect(DeadlineVisual.kind(journal)).assertEqual(DeadlineVisualKind.conferenceOrJournal);
      expect(DeadlineVisual.kind(school)).assertEqual(DeadlineVisualKind.schoolNotice);
      expect(DeadlineVisual.kind(summer)).assertEqual(DeadlineVisualKind.summerCampOrPreAdmission);
      expect(DeadlineVisual.kind(admission)).assertEqual(DeadlineVisualKind.summerCampOrPreAdmission);
      expect(DeadlineVisual.kind(hackathon)).assertEqual(DeadlineVisualKind.hackathon);
      expect(DeadlineVisual.kind(custom)).assertEqual(DeadlineVisualKind.custom);

      const assignmentFirst: DeadlineVisualKind[] = DeadlineVisual.borderKinds(
        1, [conference, school, competition]);
      expect(assignmentFirst.length).assertEqual(2);
      expect(assignmentFirst[0]).assertEqual(DeadlineVisualKind.assignment);
      expect(assignmentFirst[1]).assertEqual(DeadlineVisualKind.schoolNotice);
      const schoolFirst: DeadlineVisualKind[] = DeadlineVisual.borderKinds(
        0, [conference, school]);
      expect(schoolFirst[0]).assertEqual(DeadlineVisualKind.schoolNotice);
      expect(schoolFirst[1]).assertEqual(DeadlineVisualKind.conferenceOrJournal);
    });
  });
}

function event(kind: string, name: string, deadline: string): string {
  return '{"id":"' + name + '","name":"' + name + '","event_type":"' + kind +
    '","primary_deadline":"' + deadline + '"}';
}

function visualEvent(id: string, kind: PublicDeadlineKind,
  source: PublicDeadlineSource): PublicDeadlineItem {
  return new PublicDeadlineItem(id, id, kind, source,
    '2026-09-30T12:00:00+08:00', null, null);
}
