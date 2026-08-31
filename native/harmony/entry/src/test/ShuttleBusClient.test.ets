import { describe, it, expect } from '@ohos/hypium';
import { DateParts } from '../main/ets/common/StrictDates';
import {
  ShuttleBusClient, ShuttleBusLogic, ShuttleBusPeriodState, ShuttleBusResponseParser,
  ShuttleBusSnapshot, ShuttleBusSources
} from '../main/ets/net/ShuttleBusClient';

export default function shuttleBusClientTest() {
  describe('ShuttleBusClientTest', () => {
    it('parses_real_schema_and_selects_active_today_routes', 0, () => {
      const payload: string = '{' +
        '"schema_version":"1.0","generated_at":"2026-08-31T01:00:00.000Z",' +
        '"status":"healthy","last_parsed_notice_id":"notice-1","items":[{' +
        '"id":"notice-1","title":"秋季学期班车运行安排","published_at":"2026-08-19",' +
        '"source_url":"https://hq.bupt.edu.cn/info/1010/1541.htm",' +
        '"stops":[{"campus":"西土城路校区","location":"教三楼西侧"}],' +
        '"notes":["请提前五分钟候车"],"schedules":[{' +
        '"period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},' +
        '"from":"西土城路校区","to":"沙河校区","parse_status":"parsed","rows":[' +
        '{"departure_time":"06:30","services":{"monday":{"vehicle":"大巴","count":1}}},' +
        '{"departure_time":"08:30","services":{"monday":{"vehicle":"大巴","count":1}}}' +
        ']}]}]}';
      const snapshot: ShuttleBusSnapshot = ShuttleBusResponseParser.parse(payload);
      const daily = ShuttleBusLogic.dailyView(snapshot, new DateParts(2026, 8, 31));
      expect(ShuttleBusSources.endpoint).assertEqual(
        'https://where-to-study.cn/api/shuttle-bus');
      expect(daily.state).assertEqual(ShuttleBusPeriodState.active);
      expect(daily.weekdayKey).assertEqual('monday');
      expect(daily.schedules.length).assertEqual(1);
      expect(ShuttleBusLogic.servicesForToday(daily.schedules[0], daily.weekdayKey).length)
        .assertEqual(2);
      expect(daily.scheduleNotice?.stopLocation('西土城路校区')).assertEqual('教三楼西侧');
      expect(ShuttleBusLogic.nextDepartureIndex(
        ShuttleBusLogic.servicesForToday(daily.schedules[0], daily.weekdayKey),
        daily.state, 7 * 60)).assertEqual(1);
    });

    it('rejects_unparsed_tables_instead_of_guessing_departures', 0, () => {
      const payload: string = '{' +
        '"schema_version":"1.0","generated_at":"2026-08-31T01:00:00.000Z",' +
        '"status":"healthy","items":[{' +
        '"id":"notice-2","title":"临时调整","published_at":"2026-08-30",' +
        '"schedules":[{"period":{"label":"临时"},"from":"西土城路校区",' +
        '"to":"沙河校区","parse_status":"needs_review","rows":[' +
        '{"departure_time":"07:00","services":{"monday":{"vehicle":"大巴","count":1}}}' +
        ']}]}]}';
      const snapshot: ShuttleBusSnapshot = ShuttleBusResponseParser.parse(payload);
      const daily = ShuttleBusLogic.dailyView(snapshot, new DateParts(2026, 8, 31));
      expect(daily.schedules.length).assertEqual(0);
      expect(daily.state).assertEqual(ShuttleBusPeriodState.unknown);
    });

    it('schedule_gap_never_uses_upcoming_or_ended_period_as_today', 0, () => {
      const payload: string = '{' +
        '"schema_version":"1.0","generated_at":"2026-08-31T01:00:00.000Z",' +
        '"status":"healthy","last_parsed_notice_id":"notice-gap","items":[{' +
        '"id":"notice-gap","title":"班车安排","published_at":"2026-08-19",' +
        '"schedules":[{' +
        '"period":{"label":"未来时段","start_date":"2026-09-07"},' +
        '"from":"西土城路校区","to":"沙河校区","parse_status":"parsed","rows":[' +
        '{"departure_time":"08:30","services":{"monday":{"vehicle":"大巴","count":1}}}' +
        ']}]}]}';
      const snapshot: ShuttleBusSnapshot = ShuttleBusResponseParser.parse(payload);
      const daily = ShuttleBusLogic.dailyView(snapshot, new DateParts(2026, 8, 31));
      expect(daily.state).assertEqual(ShuttleBusPeriodState.inactive);
      expect(daily.period).assertNull();
      expect(daily.schedules.length).assertEqual(0);
      const futureRows = snapshot.notices[0].schedules[0].rows;
      expect(ShuttleBusLogic.nextDepartureIndex(
        futureRows, ShuttleBusPeriodState.upcoming, 7 * 60)).assertEqual(-1);
    });

    it('fixed_public_endpoint_rejects_every_redirect', 0, () => {
      const spec = ShuttleBusClient.requestSpec();
      expect(spec.maxRedirects).assertEqual(0);
      expect(spec.headers['Accept']).assertEqual('application/json');
      expect(spec.maxBytes).assertEqual(ShuttleBusSources.maximumPayloadBytes);
    });
  });
}
