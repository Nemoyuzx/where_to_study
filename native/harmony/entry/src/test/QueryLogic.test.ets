import { describe, it, expect } from '@ohos/hypium';
import {
  ImportantEventFilter, ImportantEventQueryLogic, QueryPageContract, QueryPageTab
} from '../main/ets/common/QueryLogic';
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
  });
}

function event(kind: string, name: string, deadline: string): string {
  return '{"id":"' + name + '","name":"' + name + '","event_type":"' + kind +
    '","primary_deadline":"' + deadline + '"}';
}
