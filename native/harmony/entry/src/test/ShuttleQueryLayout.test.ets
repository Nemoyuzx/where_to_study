import { describe, it, expect } from '@ohos/hypium';
import { ShuttleQueryLayout } from '../main/ets/view/ShuttleQueryLayout';
import { PhoneNavigationLayout } from '../main/ets/common/DeviceState';
import { AppLanguage, AppLocalization } from '../main/ets/common/AppLocalization';
import {
  ShuttleBusDailyView, ShuttleBusPeriod, ShuttleBusPeriodState, ShuttleBusRow,
  ShuttleBusSchedule, ShuttleBusService, ShuttleBusNotice, ShuttleBusStop
} from '../main/ets/net/ShuttleBusClient';

export default function shuttleQueryLayoutTest() {
  describe('ShuttleQueryLayoutTest', () => {
    it('adapts_routes_at_280vp_instead_of_a_fixed_tablet_breakpoint', 0, () => {
      expect(ShuttleQueryLayout.routeColumns(320)).assertEqual(1);
      expect(ShuttleQueryLayout.routeColumns(390)).assertEqual(1);
      expect(ShuttleQueryLayout.routeColumns(607)).assertEqual(1);
      expect(ShuttleQueryLayout.routeColumns(608)).assertEqual(2);
      expect(ShuttleQueryLayout.routeColumns(760)).assertEqual(2);
      expect(ShuttleQueryLayout.routeColumns(1024)).assertEqual(3);
      expect(ShuttleQueryLayout.contentWidth(1600)).assertEqual(1148);
    });

    it('keeps_86vp_departure_cells_with_gaps_inside_actual_card_padding', 0, () => {
      expect(ShuttleQueryLayout.departureColumns(320)).assertEqual(2);
      expect(ShuttleQueryLayout.departureColumns(390)).assertEqual(3);
      expect(ShuttleQueryLayout.departureColumns(760)).assertEqual(3);
      expect(ShuttleQueryLayout.departureColumns(1024)).assertEqual(3);
      expect(ShuttleQueryLayout.columnIndices(3).join(',')).assertEqual('0,1,2');
    });

    it('static_rows_keep_every_departure_once_and_preserve_partial_last_row', 0, () => {
      const departures: string[] = ['06:30', '08:30', '12:00', '17:30', '18:00'];
      const rows: string[][] = ShuttleQueryLayout.rows(departures, 3);
      expect(rows.length).assertEqual(2);
      expect(rows[0].join(',')).assertEqual('06:30,08:30,12:00');
      expect(rows[1].join(',')).assertEqual('17:30,18:00');
      expect(ShuttleQueryLayout.columnIndices(3).length).assertEqual(3);
      expect(ShuttleQueryLayout.rows(departures, 1).length).assertEqual(5);
      expect(ShuttleQueryLayout.rows(departures, 0).length).assertEqual(5);
      expect(ShuttleQueryLayout.rows(departures, 0.5).length).assertEqual(5);
      expect(ShuttleQueryLayout.rows<string>([], 3).length).assertEqual(0);
    });

    it('large_font_layout_keeps_every_track_inside_the_page_and_card', 0, () => {
      for (const width of [320, 390, 760, 1024]) {
        for (const scale of [1, 1.3, 2]) {
          const routes: number = ShuttleQueryLayout.routeColumns(width, scale);
          const routeWidth: number = ShuttleQueryLayout.routeWidth(width, scale);
          const pageWidth: number = ShuttleQueryLayout.contentWidth(width);
          expect(routeWidth * routes + 16 * (routes - 1) <= pageWidth + 0.001).assertTrue();
          const content: number = routeWidth - 32;
          const columns: number = ShuttleQueryLayout.departureColumns(width, scale);
          const tileWidth: number = (content - 8 * (columns - 1)) / columns;
          expect(tileWidth * columns + 8 * (columns - 1) <= content + 0.001).assertTrue();
          expect(columns === 1 || tileWidth >= 86 * scale).assertTrue();
          expect(columns >= 1 && routes >= 1).assertTrue();
        }
      }
    });

    it('narrow_or_unmeasured_pages_always_keep_one_usable_track', 0, () => {
      expect(ShuttleQueryLayout.routeColumns(0)).assertEqual(1);
      expect(ShuttleQueryLayout.departureColumns(180, 2)).assertEqual(1);
      expect(ShuttleQueryLayout.fontScale(0)).assertEqual(1);
      expect(ShuttleQueryLayout.fontScale(-1)).assertEqual(1);
      expect(ShuttleQueryLayout.fontScale(0.8)).assertEqual(1);
      expect(PhoneNavigationLayout.minimumContentBottomInsetVp >=
        PhoneNavigationLayout.navigationHeightVp + PhoneNavigationLayout.minimumBottomClearanceVp)
        .assertTrue();
    });

    it('counts_scheduled_departures_not_vehicle_quantity_or_other_weekdays', 0, () => {
      const daily: ShuttleBusDailyView = activeDaily();
      expect(ShuttleQueryLayout.departureCount(daily)).assertEqual(2);
      expect(ShuttleQueryLayout.statusTitle(daily)).assertEqual('今日班车按时刻表运行');
      const noService: ShuttleBusDailyView = new ShuttleBusDailyView(daily.date, 'sunday',
        daily.state, daily.period, daily.schedules, null, null, false);
      expect(ShuttleQueryLayout.departureCount(noService)).assertEqual(0);
      expect(ShuttleQueryLayout.statusTitle(noService)).assertEqual('今日没有计划班次');
    });

    it('inactive_and_empty_schedules_never_look_like_running_service', 0, () => {
      const daily: ShuttleBusDailyView = activeDaily();
      const inactive: ShuttleBusDailyView = new ShuttleBusDailyView(daily.date, daily.weekdayKey,
        ShuttleBusPeriodState.inactive, daily.period, daily.schedules, null, null, false);
      expect(ShuttleQueryLayout.departureCount(inactive)).assertEqual(0);
      expect(ShuttleQueryLayout.statusTitle(inactive)).assertEqual('今日暂无生效的班车时刻表');
      const empty: ShuttleBusDailyView = new ShuttleBusDailyView(daily.date, daily.weekdayKey,
        ShuttleBusPeriodState.active, null, [], null, null, false);
      expect(ShuttleQueryLayout.statusTitle(empty)).assertEqual('今日暂无生效的班车时刻表');
    });

    it('keeps_unmatched_departure_locations_available_in_the_status_notes', 0, () => {
      const daily: ShuttleBusDailyView = activeDaily();
      const notice: ShuttleBusNotice = new ShuttleBusNotice('notice', '原始通知', '2026-09-01',
        null, daily.schedules, [new ShuttleBusStop('西土城', '教三楼'),
          new ShuttleBusStop('沙河', '南门'), new ShuttleBusStop('其他校区', '图书馆')], ['原文说明']);
      const withNotice: ShuttleBusDailyView = new ShuttleBusDailyView(daily.date, daily.weekdayKey,
        daily.state, daily.period, daily.schedules, notice, notice, false);
      expect(ShuttleQueryLayout.unmatchedStops(withNotice).length).assertEqual(1);
      expect(ShuttleQueryLayout.unmatchedStops(withNotice)[0].location).assertEqual('图书馆');
      expect(ShuttleQueryLayout.unmatchedStops(daily).length).assertEqual(0);
    });

    it('summary_and_notice_labels_localize_without_translating_notice_contents', 0, () => {
      expect(AppLocalization.text('信息查询', AppLanguage.english, 'en-US'))
        .assertEqual('Information Search');
      const summary: string = '今日共 {routes} 个方向、{departures} 个计划班次';
      expect(AppLocalization.text(summary, AppLanguage.english, 'en-US')
        .replace('{routes}', '2').replace('{departures}', '15'))
        .assertEqual('2 routes · 15 scheduled departures today');
      expect(AppLocalization.text(summary, AppLanguage.simplifiedChinese, 'zh-CN')
        .replace('{routes}', '2').replace('{departures}', '15'))
        .assertEqual('今日共 2 个方向、15 个计划班次');
      expect(AppLocalization.text('后勤部通知 · ', AppLanguage.english, 'en-US'))
        .assertEqual('Logistics notice · ');
      expect(AppLocalization.text('2026 秋季学期班车调整通知', AppLanguage.english, 'en-US'))
        .assertEqual('2026 秋季学期班车调整通知');
    });
  });
}

function activeDaily(): ShuttleBusDailyView {
  const period: ShuttleBusPeriod = new ShuttleBusPeriod('秋季', '2026-09-01', '2026-12-31');
  const weekday: Map<string, ShuttleBusService> = new Map<string, ShuttleBusService>();
  weekday.set('monday', new ShuttleBusService('大巴', 3));
  const otherDay: Map<string, ShuttleBusService> = new Map<string, ShuttleBusService>();
  otherDay.set('saturday', new ShuttleBusService('大巴', 1));
  const routes: ShuttleBusSchedule[] = [
    new ShuttleBusSchedule(period, '西土城', '沙河', [
      new ShuttleBusRow('07:00', weekday), new ShuttleBusRow('08:00', otherDay)
    ]),
    new ShuttleBusSchedule(period, '沙河', '西土城', [new ShuttleBusRow('09:00', weekday)])
  ];
  return new ShuttleBusDailyView('2026-09-07', 'monday', ShuttleBusPeriodState.active,
    period, routes, null, null, false);
}
