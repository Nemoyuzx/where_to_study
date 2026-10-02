import { describe, it, expect } from '@ohos/hypium';
import {
  AlmanacInfo, AlmanacResponseParser, AssignmentDeadlineItem,
  AssignmentDeadlineResponseParser, PublicDeadlineItem, PublicDeadlineKind,
  PublicDeadlineResponseParser, CalendarDailyInfoClient, CalendarDailyInfoSources,
  ContestFeedMetadata,
  CustomDeadlineURLPolicy, FavoriteDeadlineCodec, FixedPublicJsonFetching,
  PublicDeadlineSnapshot, PublicDeadlineSource
} from '../main/ets/net/CalendarDailyInfoClient';
import { UCloudAssignmentClient } from '../main/ets/net/UCloudAssignmentClient';
import { Credentials } from '../main/ets/store/CredentialStore';
import { customDeadlineFeedText } from './fixtures/custom-deadline-feed';

export default function calendarDailyInfoClientTest() {
  describe('CalendarDailyInfoClientTest', () => {
    it('almanac_parsers_keep_yi_ji_and_validate_date', 0, () => {
      const base: AlmanacInfo = AlmanacResponseParser.parseBase('{' +
        '"datetime":"2026-08-22 12:00:00","weekday_cn":"星期六",' +
        '"lunar_month_cn":"七月","lunar_day_cn":"初十",' +
        '"ganzhi_year":"丙午","ganzhi_month":"丙申","ganzhi_day":"戊辰",' +
        '"zodiac":"马"}', '2026-08-22');
      const advice: string[] = AlmanacResponseParser.parseAdvice('{' +
        '"errno":0,"data":{"year":2026,"month":8,"day":22,' +
        '"almanac":{"yi":"学习、交流","ji":"拖延、熬夜"}}}', '2026-08-22');
      expect(base.lunarDate).assertEqual('七月初十');
      expect(advice[0]).assertEqual('学习、交流');
      expect(advice[1]).assertEqual('拖延、熬夜');
      let threw: boolean = false;
      try {
        AlmanacResponseParser.parseAdvice('{' +
          '"errno":0,"data":{"year":2026,"month":8,"day":22,' +
          '"almanac":{"yi":"宜","ji":"忌"}}}', '2026-08-23');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('public_deadline_parser_filters_date_kinds_and_unsafe_links', 0, () => {
      const parsed: PublicDeadlineItem[] = PublicDeadlineResponseParser.parse('{' +
        '"items":[' +
        '{"id":"c1","name":"数据库竞赛","event_type":"competition",' +
        '"primary_deadline":"2026-08-22T18:00:00+08:00",' +
        '"official_url":"https://example.com/c1"},' +
        '{"id":"h1","name":"校园黑客松","event_type":"hackathon",' +
        '"primary_deadline":"2026-08-22T23:59:59+08:00",' +
        '"official_url":"http://example.com"},' +
        '{"id":"s1","name":"夏令营","event_type":"summer_camp",' +
        '"primary_deadline":"2026-08-23T23:59:59+08:00"},' +
        '{"id":"x1","name":"未知","event_type":"other",' +
        '"primary_deadline":"2026-08-22T12:00:00+08:00"}' +
        ']}', '2026-08-22');
      expect(parsed.length).assertEqual(2);
      expect(parsed[0].id).assertEqual('c1');
      expect(parsed[0].officialURL).assertEqual('https://example.com/c1');
      expect(parsed[1].id).assertEqual('h1');
      expect(parsed[1].officialURL).assertNull();
    });

    it('public_deadline_parser_and_favorites_preserve_query_metadata', 0, () => {
      const parsed: PublicDeadlineItem[] = PublicDeadlineResponseParser.parse('{' +
        '"items":[{"id":"conf","name":"AI Conference","event_type":"conference",' +
        '"primary_deadline":"2026-09-22T18:00:00+08:00",' +
        '"categories":["人工智能","交叉/综合/新兴"],"tags":["CCF A","学术会议"],' +
        '"level":"CCF A","location":"Phoenix","description":"AI research",' +
        '"eligibility":"Researchers","notes":"Check official website","archived":false,' +
        '"source":{"name":"CCFDDL","url":"https://ccfddl.com/",' +
        '"source_type":"trusted_community","authority":4}}]}', '2026-09-22');
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].categories[0]).assertEqual('人工智能');
      expect(parsed[0].tags[0]).assertEqual('CCF A');
      expect(parsed[0].level).assertEqual('CCF A');
      expect(parsed[0].location).assertEqual('Phoenix');
      expect(parsed[0].description).assertEqual('AI research');
      expect(parsed[0].eligibility).assertEqual('Researchers');
      expect(parsed[0].notes).assertEqual('Check official website');
      expect(parsed[0].sourceName).assertEqual('CCFDDL');
      expect(parsed[0].sourceHomepage).assertEqual('https://ccfddl.com/');
      expect(parsed[0].upstreamSourceType).assertEqual('trusted_community');
      expect(parsed[0].sourceAuthority).assertEqual(4);
      const restored: PublicDeadlineItem[] = FavoriteDeadlineCodec.decode(
        FavoriteDeadlineCodec.encode(parsed));
      expect(restored[0].categories[1]).assertEqual('交叉/综合/新兴');
      expect(restored[0].location).assertEqual('Phoenix');
      expect(restored[0].sourceAuthority).assertEqual(4);
    });

    it('school_notice_parser_expands_deadlines_on_selected_day', 0, () => {
      const parsed: PublicDeadlineItem[] = PublicDeadlineResponseParser.parseSchoolNotices('{' +
        '"items":[{"id":"bupt-ucloud-1","name":"校内创新竞赛",' +
        '"deadlines":[' +
        '{"date":"2026-08-22T10:00:00+08:00","label":"材料提交"},' +
        '{"date":"2026-08-23T23:59:59+08:00","label":"报名截止"}],' +
        '"source":"北京邮电大学教学云平台",' +
        '"source_url":"https://ucloud.bupt.edu.cn/#/consulting?type=1&id=1"}]}',
      '2026-08-22');
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].kind).assertEqual(PublicDeadlineKind.competition);
      expect(parsed[0].organizer).assertEqual('北京邮电大学教学云平台 · 材料提交');
      expect(parsed[0].officialURL).assertEqual(
        'https://ucloud.bupt.edu.cn/#/consulting?type=1&id=1');
    });

    it('assignment_parser_supports_course_and_homepage_contracts', 0, () => {
      const courseItems: AssignmentDeadlineItem[] = AssignmentDeadlineResponseParser.parse('{' +
        '"data":{"records":[' +
        '{"id":7,"assignmentTitle":"第四次作业","siteName":"课程",' +
        '"assignmentEndTime":"2026-06-30 23:59:00","assignmentStatus":99},' +
        '{"id":8,"assignmentTitle":"第三次作业",' +
        '"assignmentEndTime":"2026-06-21 23:59:00","assignmentStatus":0}' +
        ']}}', '2026-06-30');
      expect(courseItems.length).assertEqual(1);
      expect(courseItems[0].id).assertEqual('7');
      expect(courseItems[0].status).assertEqual('未提交');

      const undone: AssignmentDeadlineItem[] = AssignmentDeadlineResponseParser.parse('{' +
        '"data":{"undoneList":[' +
        '{"activityId":"a1","activityName":"课程作业","type":3,' +
        '"endTime":"2026-08-22 18:00:00"},' +
        '{"activityId":"q1","activityName":"课程测验","type":4,' +
        '"endTime":"2026-08-22 20:00:00"}' +
        ']}}', '2026-08-22');
      expect(undone.length).assertEqual(1);
      expect(undone[0].id).assertEqual('a1');
    });

    it('assignment_parser_injects_course_name', 0, () => {
      const root: Record<string, Object> = JSON.parse('{' +
        '"data":{"records":[{"id":"a1","assignmentTitle":"作业一",' +
        '"assignmentEndTime":"2026-08-22 23:59:00","assignmentStatus":99}]}}') as
        Record<string, Object>;
      const items: AssignmentDeadlineItem[] =
        AssignmentDeadlineResponseParser.parseAll(root, '示例课程');
      expect(items.length).assertEqual(1);
      expect(items[0].courseName).assertEqual('示例课程');
    });

    it('assignment_parser_does_not_report_malformed_payload_as_empty', 0, () => {
      for (const payload of ['{}', '{"data":{}}', '{"data":{"records":{}}}']) {
        let rejected: boolean = false;
        try { AssignmentDeadlineResponseParser.parse(payload, '2026-09-19'); } catch (e) { rejected = true; }
        expect(rejected).assertTrue();
      }
      expect(AssignmentDeadlineResponseParser.parse('{"data":{"records":[]}}', '2026-09-19').length).assertEqual(0);
    });

    it('ucloud_cas_parser_pins_host_and_supports_attribute_order', 0, () => {
      expect(UCloudAssignmentClient.parseExecution(
        '<input value=\'e1&amp;s1\' type=\'hidden\' name=\'execution\'>')).assertEqual('e1&s1');
      expect(UCloudAssignmentClient.parseExecution(
        '<input name=execution value=token-2>')).assertEqual('token-2');
      expect(UCloudAssignmentClient.ticketFrom(
        'https://ucloud.bupt.edu.cn/?ticket=ST-test')).assertEqual('ST-test');
      expect(UCloudAssignmentClient.ticketFrom(
        'http://ucloud.bupt.edu.cn/?ticket=ST-test')).assertNull();
      expect(UCloudAssignmentClient.ticketFrom(
        'https://evil.example/?ticket=ST-test')).assertNull();
    });

    it('ucloud_cookie_parser_keeps_repeated_cookie_pairs', 0, () => {
      const headers: Record<string, Object> = {};
      headers['Set-Cookie'] = '_route=first; Path=/, SESSION=second; Path=/; ' +
        'expires=Tue, 19 Aug 2036 15:07:51 GMT; HttpOnly';
      expect(UCloudAssignmentClient.cookieHeaderFrom(headers))
        .assertEqual('_route=first; SESSION=second');
    });

    it('ucloud_concurrent_dates_share_one_account_range_fetch', 0, async () => {
      let fetchCount: number = 0;
      const client: UCloudAssignmentClient = new UCloudAssignmentClient(
        async (credentials: Credentials): Promise<AssignmentDeadlineItem[]> => {
          fetchCount++;
          return [
            new AssignmentDeadlineItem('first', 'First', null,
              '2026-08-22 20:00:00', '未提交'),
            new AssignmentDeadlineItem('second', 'Second', null,
              '2026-08-23 20:00:00', '未提交')
          ];
        });
      const credentials: Credentials = new Credentials('2023000000', 'password');
      const results: AssignmentDeadlineItem[][] = await Promise.all([
        client.fetch(credentials, '2026-08-22'), client.fetch(credentials, '2026-08-23')
      ]);
      expect(fetchCount).assertEqual(1);
      expect(results[0][0].id).assertEqual('first');
      expect(results[1][0].id).assertEqual('second');
    });

    it('ucloud_uses_cloud_override_and_invalidates_on_effective_password_change', 0, async () => {
      const seen: string[] = [];
      const client: UCloudAssignmentClient = new UCloudAssignmentClient(
        async (credentials: Credentials): Promise<AssignmentDeadlineItem[]> => {
          seen.push(credentials.password);
          return [];
        });
      await client.fetch(new Credentials('student', 'academic', 'cloud'), '2026-09-11');
      await client.fetch(new Credentials('student', 'changed-academic', 'cloud'), '2026-09-12');
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual('cloud');
      await client.fetch(new Credentials('student', 'changed-academic', 'new-cloud'), '2026-09-11');
      await client.fetch(new Credentials('student', 'changed-academic'), '2026-09-11');
      expect(seen.join(',')).assertEqual('cloud,new-cloud,changed-academic');
    });

    it('ucloud_old_inflight_password_cannot_overwrite_new_cache', 0, async () => {
      let releaseOld: () => void = (): void => {};
      const gate: Promise<void> = new Promise<void>((resolve) => {
        releaseOld = (): void => resolve();
      });
      let count: number = 0;
      const client: UCloudAssignmentClient = new UCloudAssignmentClient(
        async (credentials: Credentials): Promise<AssignmentDeadlineItem[]> => {
          count++;
          if (credentials.password === 'old-cloud') {
            await gate;
          }
          return [new AssignmentDeadlineItem(credentials.password === 'old-cloud' ? 'old' : 'new',
            'Assignment', null, '2026-09-11 20:00:00', '未提交')];
        });
      const old: Promise<AssignmentDeadlineItem[]> = client.fetch(
        new Credentials('student', 'academic', 'old-cloud'), '2026-09-11');
      await client.fetch(new Credentials('student', 'academic', 'new-cloud'), '2026-09-11');
      releaseOld();
      await old;
      const cached: AssignmentDeadlineItem[] = await client.fetch(
        new Credentials('student', 'academic', 'new-cloud'), '2026-09-11');
      expect(cached[0].id).assertEqual('new');
      expect(count).assertEqual(2);
    });

    it('startup_warmup_shares_one_range_fetch_and_page_changes_filter_in_memory', 0, async () => {
      const transport: CountingDeadlineTransport = new CountingDeadlineTransport();
      let contestParses: number = 0;
      let schoolParses: number = 0;
      const client: CalendarDailyInfoClient = new CalendarDailyInfoClient(
        transport,
        (payload: string): Map<string, PublicDeadlineItem[]> => {
          contestParses++;
          return PublicDeadlineResponseParser.parseIndex(payload);
        },
        (payload: string): Map<string, PublicDeadlineItem[]> => {
          schoolParses++;
          return PublicDeadlineResponseParser.parseSchoolNoticesIndex(payload);
        });
      const results: PublicDeadlineSnapshot[] = await Promise.all([
        client.prewarmDeadlines('2026-08-22'), client.fetchDeadlines('2026-08-23')
      ]);
      expect(results[0].items.length).assertEqual(1);
      expect(results[0].items[0].id).assertEqual('first');
      expect(results[1].items.length).assertEqual(1);
      expect(results[1].items[0].id).assertEqual('second');
      expect(transport.primaryCalls).assertEqual(1);
      expect(transport.mirrorCalls).assertEqual(1);
      expect(transport.schoolCalls).assertEqual(1);
      await client.fetchImportantEvents();
      expect(transport.primaryCalls).assertEqual(1);
      expect(transport.schoolCalls).assertEqual(1);
      expect(contestParses).assertEqual(2);
      expect(schoolParses).assertEqual(1);

      const catalog: PublicDeadlineItem[] = await client.fetchImportantEvents();
      expect(catalog.length).assertEqual(2);
      expect(transport.primaryCalls).assertEqual(1);
      expect(transport.mirrorCalls).assertEqual(1);
      expect(transport.schoolCalls).assertEqual(1);

      await client.fetchDeadlines('2026-08-24');
      expect(transport.primaryCalls).assertEqual(1);
      expect(transport.mirrorCalls).assertEqual(1);
      expect(transport.schoolCalls).assertEqual(1);
      expect(contestParses).assertEqual(2);
      expect(schoolParses).assertEqual(1);

      await client.prewarmDeadlines('2026-08-23', true);
      expect(transport.primaryCalls).assertEqual(2);
      expect(transport.mirrorCalls).assertEqual(2);
      expect(transport.schoolCalls).assertEqual(2);
      expect(contestParses).assertEqual(4);
      expect(schoolParses).assertEqual(2);
    });

    it('mirror_wins_only_when_its_validated_generation_is_newer', 0, async () => {
      for (const generation of [
        '2026-08-23T10:00:00+08:00',
        '2026-08-22T10:00:00+08:00',
        '2026-08-21T10:00:00+08:00'
      ]) {
        const client: CalendarDailyInfoClient = new CalendarDailyInfoClient(
          new ContestSelectionTransport(
            contestPayload('primary', '2026-08-22T10:00:00+08:00'),
            contestPayload('mirror', generation)));
        const snapshot: PublicDeadlineSnapshot = await client.fetchDeadlines('2026-08-22');
        const newer: boolean = generation === '2026-08-23T10:00:00+08:00';
        expect(snapshot.items[0].id).assertEqual(newer ? 'mirror' : 'primary');
        expect(snapshot.usedBackup).assertEqual(newer);
        expect(snapshot.source).assertEqual(newer ? CalendarDailyInfoSources.deadlineMirror :
          CalendarDailyInfoSources.deadlinePrimary);
      }
    });

    it('invalid_mirror_keeps_primary_and_primary_failure_uses_mirror', 0, async () => {
      const invalidMirror: string = '{"schema_version":"2.0","timezone":"Asia/Shanghai",' +
        '"generated_at":"2026-08-23T10:00:00+08:00","items":[]}';
      const withPrimary: CalendarDailyInfoClient = new CalendarDailyInfoClient(
        new ContestSelectionTransport(
          contestPayload('primary', '2026-08-22T10:00:00+08:00'), invalidMirror));
      const primarySnapshot: PublicDeadlineSnapshot = await withPrimary.fetchDeadlines('2026-08-22');
      expect(primarySnapshot.items[0].id).assertEqual('primary');

      const withMirror: CalendarDailyInfoClient = new CalendarDailyInfoClient(
        new ContestSelectionTransport(null, contestPayload('mirror', '2026-08-23T10:00:00+08:00')));
      const mirrorSnapshot: PublicDeadlineSnapshot = await withMirror.fetchDeadlines('2026-08-22');
      expect(mirrorSnapshot.items[0].id).assertEqual('mirror');
      expect(mirrorSnapshot.usedBackup).assertTrue();
    });

    it('api_backup_remains_available_after_both_versioned_sources_fail', 0, async () => {
      const transport: ContestSelectionTransport = new ContestSelectionTransport(
        null, '{"schema_version":"1.4","timezone":"Asia/Shanghai","generated_at":"bad","items":[]}',
        contestPayload('api', '2026-08-20T10:00:00+08:00'));
      const snapshot: PublicDeadlineSnapshot = await new CalendarDailyInfoClient(transport)
        .fetchDeadlines('2026-08-22');
      expect(snapshot.items[0].id).assertEqual('api');
      expect(snapshot.source).assertEqual(CalendarDailyInfoSources.deadlineBackup);
      expect(snapshot.usedBackup).assertTrue();
      expect(transport.requests.join(',')).assertEqual([
        CalendarDailyInfoSources.deadlinePrimary,
        CalendarDailyInfoSources.deadlineMirror,
        CalendarDailyInfoSources.deadlineBackup,
        CalendarDailyInfoSources.schoolContestNotices
      ].join(','));
    });

    it('newer_valid_empty_mirror_clears_obsolete_contest_items', 0, async () => {
      const client: CalendarDailyInfoClient = new CalendarDailyInfoClient(
        new ContestSelectionTransport(
          contestPayload('obsolete', '2026-08-22T10:00:00+08:00'),
          '{"schema_version":"1.4","timezone":"Asia/Shanghai",' +
            '"generated_at":"2026-08-23T10:00:00+08:00","items":[]}'));
      const snapshot: PublicDeadlineSnapshot = await client.fetchDeadlines('2026-08-22');
      expect(snapshot.items.length).assertEqual(0);
      expect(snapshot.source).assertEqual(CalendarDailyInfoSources.deadlineMirror);
    });

    it('contest_generation_metadata_validates_schema_and_timezones', 0, () => {
      expect(ContestFeedMetadata.generatedAtMillis(
        contestPayload('a', '2026-08-22T10:00:00+08:00'))).assertEqual(
        ContestFeedMetadata.generatedAtMillis(contestPayload('a', '2026-08-22T02:00:00Z')));
      for (const invalid of [
        '{"generated_at":"2026-08-22T10:00:00+08:00","items":[]}',
        '{"schema_version":"1.4","timezone":"Asia/Shanghai","generated_at":"2026-13-22T10:00:00+08:00","items":[]}',
        '{"schema_version":"1.4","timezone":"Asia/Shanghai","generated_at":"2026-08-22T10:00:00+08:00","items":{}}',
        '{"schema_version":"1.4","timezone":"UTC","generated_at":"2026-08-22T10:00:00+08:00","items":[]}'
      ]) {
        let rejected: boolean = false;
        try { ContestFeedMetadata.generatedAtMillis(invalid); } catch (e) { rejected = true; }
        expect(rejected).assertTrue();
      }
      const oversized: string = '{"schema_version":"1.4","timezone":"Asia/Shanghai",' +
        '"generated_at":"2026-08-22T10:00:00+08:00","items":[' +
        Array(5001).fill('{}').join(',') + ']}';
      let oversizedRejected: boolean = false;
      try { ContestFeedMetadata.generatedAtMillis(oversized); } catch (e) { oversizedRejected = true; }
      expect(oversizedRejected).assertTrue();
    });

    it('custom_feed_and_favorites_follow_the_shared_v1_contract', 0, () => {
      const index: Map<string, PublicDeadlineItem[]> =
        PublicDeadlineResponseParser.parseCustomIndex(customDeadlineFeedText);
      const customItems: PublicDeadlineItem[] = index.get('2026-09-18') ?? [];
      expect(customItems.length).assertEqual(1);
      const item: PublicDeadlineItem = customItems[0];
      expect(item.kind).assertEqual(PublicDeadlineKind.custom);
      expect(item.source).assertEqual(PublicDeadlineSource.custom);
      const decoded: PublicDeadlineItem[] = FavoriteDeadlineCodec.decode(
        FavoriteDeadlineCodec.encode([item]));
      expect(decoded.length).assertEqual(1);
      expect(decoded[0].id).assertEqual('custom:example-registration');
      expect(decoded[0].sourceName).assertEqual('示例自定义日程');
      expect(decoded[0].sourceHomepage).assertEqual('https://example.com/calendar');
      expect(CustomDeadlineURLPolicy.allows('https://calendar.example.com/feed.json')).assertTrue();
      expect(CustomDeadlineURLPolicy.allows('http://calendar.example.com/feed.json')).assertFalse();
      expect(CustomDeadlineURLPolicy.allows('https://127.0.0.1/feed.json')).assertFalse();
    });

    it('custom_feed_rejects_invalid_envelopes_and_skips_unsafe_entries', 0, () => {
      const invalidPayloads: string[] = [
        '{"version":1,"source":"Missing items"}',
        '{"version":1,"source":"Bad homepage","homepage":"http://example.com","items":[]}',
        '{"version":1,"source":"Bad update","updated_at":"2026-08-24","items":[]}',
        '{"version":1,"source":"Extra key","items":[],"unknown":true}'
      ];
      for (const payload of invalidPayloads) {
        let threw: boolean = false;
        try {
          PublicDeadlineResponseParser.parseCustomIndex(payload);
        } catch (e) {
          threw = true;
        }
        expect(threw).assertTrue();
      }
      const oversizedOrganizer: string = 'x'.repeat(201);
      const entryPayload: string = '{"version":1,"source":"Example","items":[' +
        '{"id":"unsafe","name":"Unsafe","event_type":"custom",' +
        '"primary_deadline":"2026-09-18T12:00:00+08:00",' +
        '"official_url":"http://example.com"},' +
        '{"id":"organizer","name":"Organizer","event_type":"custom",' +
        '"primary_deadline":"2026-09-18T13:00:00+08:00",' +
        '"organizer":"' + oversizedOrganizer + '"}]}';
      expect(PublicDeadlineResponseParser.parseCustomIndex(entryPayload).size).assertEqual(0);
    });

    it('custom_feed_dates_share_one_in_flight_request_and_then_use_stale_cache', 0, async () => {
      const transport: CountingDeadlineTransport = new CountingDeadlineTransport();
      const client: CalendarDailyInfoClient = new CalendarDailyInfoClient(transport);
      const url: string = 'https://calendar.example.com/feed.json';
      const results: PublicDeadlineSnapshot[] = await Promise.all([
        client.fetchCustomDeadlines(url, '2026-09-18'),
        client.fetchCustomDeadlines(url, '2026-10-08')
      ]);
      expect(transport.customCalls).assertEqual(1);
      expect(results[0].items[0].id).assertEqual('custom:example-registration');
      expect(results[1].items[0].id).assertEqual('custom:example-competition');

      await client.fetchCustomDeadlines(url, '2026-09-18');
      expect(transport.customCalls).assertEqual(1);
    });
  });
}

class CountingDeadlineTransport implements FixedPublicJsonFetching {
  primaryCalls: number = 0;
  mirrorCalls: number = 0;
  schoolCalls: number = 0;
  customCalls: number = 0;

  async fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string> {
    if (url === CalendarDailyInfoSources.deadlinePrimary) {
      this.primaryCalls++;
      return '{"schema_version":"1.4","timezone":"Asia/Shanghai","generated_at":"2026-08-22T10:00:00+08:00","items":[' +
        '{"id":"first","name":"First","event_type":"competition",' +
        '"primary_deadline":"2026-08-22T20:00:00+08:00"},' +
        '{"id":"second","name":"Second","event_type":"hackathon",' +
        '"primary_deadline":"2026-08-23T20:00:00+08:00"}' +
        ']}';
    }
    if (url === CalendarDailyInfoSources.deadlineMirror) {
      this.mirrorCalls++;
      return '{"schema_version":"1.4","timezone":"Asia/Shanghai","generated_at":"2026-08-21T10:00:00+08:00","items":[]}';
    }
    if (url === CalendarDailyInfoSources.schoolContestNotices) {
      this.schoolCalls++;
      return '{"items":[]}';
    }
    throw new Error('unexpected URL');
  }

  async fetchCustom(url: string, maximumBytes: number): Promise<string> {
    this.customCalls++;
    return customDeadlineFeedText;
  }
}

function contestPayload(id: string, generatedAt: string): string {
  return '{"schema_version":"1.4","timezone":"Asia/Shanghai","generated_at":"' + generatedAt + '","items":[' +
    '{"id":"' + id + '","name":"' + id + '","event_type":"competition",' +
    '"primary_deadline":"2026-08-22T20:00:00+08:00"}]}';
}

class ContestSelectionTransport implements FixedPublicJsonFetching {
  readonly requests: string[] = [];
  private readonly primary: string | null;
  private readonly mirror: string | null;
  private readonly backup: string | null;

  constructor(primary: string | null, mirror: string | null, backup: string | null = null) {
    this.primary = primary;
    this.mirror = mirror;
    this.backup = backup;
  }

  async fetch(url: string, scheme: string, host: string, maximumBytes: number): Promise<string> {
    this.requests.push(url);
    let payload: string | null = null;
    if (url === CalendarDailyInfoSources.deadlinePrimary) {
      payload = this.primary;
    } else if (url === CalendarDailyInfoSources.deadlineMirror) {
      payload = this.mirror;
    } else if (url === CalendarDailyInfoSources.deadlineBackup) {
      payload = this.backup;
    } else if (url === CalendarDailyInfoSources.schoolContestNotices) {
      payload = '{"items":[]}';
    }
    if (payload === null) {
      throw new Error('source unavailable');
    }
    return payload;
  }

  async fetchCustom(url: string, maximumBytes: number): Promise<string> {
    throw new Error('unexpected custom source');
  }
}
