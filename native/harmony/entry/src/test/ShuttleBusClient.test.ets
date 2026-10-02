import { describe, it, expect } from '@ohos/hypium';
import { DateParts } from '../main/ets/common/StrictDates';
import {
  ShuttleBusClient, ShuttleBusLogic, ShuttleBusPeriodState, ShuttleBusResponseParser,
  ShuttleBusPeriod, ShuttleBusSchedule, ShuttleBusSnapshot, ShuttleBusSources
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
      expect(daily.scheduleNotice?.schedules.length).assertEqual(1);
      expect(ShuttleBusLogic.servicesForToday(daily.scheduleNotice?.schedules[0] as
        ShuttleBusSchedule, 'monday').length).assertEqual(1);
    });

    it('full_notice_retains_both_periods_directions_and_weekdays', 0, () => {
      const payload: string = '{"schema_version":"1.0",' +
        '"generated_at":"2026-08-31T01:00:00.000Z","status":"healthy",' +
        '"last_parsed_notice_id":"full","items":[{' +
        '"id":"full","title":"完整班车安排","published_at":"2026-08-19",' +
        '"schedules":[' +
        '{"period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},' +
        '"from":"西土城路校区","to":"沙河校区","parse_status":"parsed","rows":[' +
        '{"departure_time":"08:30","services":{"monday":{"vehicle":"大巴","count":1}}}]},' +
        '{"period":{"label":"第二时段","start_date":"2026-09-07"},' +
        '"from":"沙河校区","to":"西土城路校区","parse_status":"parsed","rows":[' +
        '{"departure_time":"17:30","services":{"sunday":{"vehicle":"大巴","count":2}}}]}]}]}';
      const daily = ShuttleBusLogic.dailyView(ShuttleBusResponseParser.parse(payload),
        new DateParts(2026, 8, 31));
      expect(daily.schedules.length).assertEqual(1);
      expect(daily.scheduleNotice?.schedules.length).assertEqual(2);
      expect(daily.scheduleNotice?.schedules[1].period.label).assertEqual('第二时段');
      expect(daily.scheduleNotice?.schedules[1].from).assertEqual('沙河校区');
      expect(ShuttleBusLogic.periodState(
        daily.scheduleNotice?.schedules[0].period as ShuttleBusPeriod,
        '2026-08-31')).assertEqual(ShuttleBusPeriodState.active);
      expect(ShuttleBusLogic.periodState(
        daily.scheduleNotice?.schedules[1].period as ShuttleBusPeriod,
        '2026-08-31')).assertEqual(ShuttleBusPeriodState.upcoming);
      expect(ShuttleBusLogic.servicesForToday(
        daily.scheduleNotice?.schedules[1] as ShuttleBusSchedule,
        'sunday').length).assertEqual(1);
    });

    it('overlapping_active_periods_prefer_the_later_start_date', 0, () => {
      const payload: string = '{"schema_version":"1.0",' +
        '"generated_at":"2026-09-02T01:00:00.000Z","status":"healthy",' +
        '"last_parsed_notice_id":"overlap","items":[{' +
        '"id":"overlap","title":"重叠时段","published_at":"2026-08-19",' +
        '"schedules":[' +
        '{"period":{"label":"旧时段","start_date":"2026-08-27","end_date":"2026-09-20"},' +
        '"from":"西土城路校区","to":"沙河校区","parse_status":"parsed","rows":[' +
        '{"departure_time":"08:30","services":{"wednesday":{"vehicle":"大巴","count":1}}}]},' +
        '{"period":{"label":"新时段","start_date":"2026-09-01","end_date":"2026-09-20"},' +
        '"from":"西土城路校区","to":"沙河校区","parse_status":"parsed","rows":[' +
        '{"departure_time":"09:30","services":{"wednesday":{"vehicle":"大巴","count":1}}}]}]}]}';
      const daily = ShuttleBusLogic.dailyView(ShuttleBusResponseParser.parse(payload),
        new DateParts(2026, 9, 2));
      expect(daily.period?.label).assertEqual('新时段');
      expect(daily.schedules.length).assertEqual(1);
      expect(daily.schedules[0].rows[0].departureTime).assertEqual('09:30');
    });

    it('fixed_public_endpoint_rejects_every_redirect', 0, () => {
      const spec = ShuttleBusClient.requestSpec();
      expect(spec.maxRedirects).assertEqual(0);
      expect(spec.headers['Accept']).assertEqual('application/json');
      expect(spec.maxBytes).assertEqual(ShuttleBusSources.maximumPayloadBytes);
    });
  });
}
