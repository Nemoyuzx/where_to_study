import { describe, it, expect } from '@ohos/hypium';
import { CampusWeather, WeatherSourceParser } from '../main/ets/net/DailyInfoClient';
import { WeatherCardPolicy } from '../main/ets/common/WeatherCardPolicy';

export default function dailyInfoClientTest() {
  describe('DailyInfoClientTest', () => {
    it('weather_targets_match_campus_district_adcodes', 0, () => {
      expect(WeatherSourceParser.target('01').adcode).assertEqual('110108');
      expect(WeatherSourceParser.target('4').adcode).assertEqual('110114');
      let threw: boolean = false;
      try {
        WeatherSourceParser.target('99');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('weather_parser_keeps_two_days_and_rounds_values', 0, () => {
      const payload: string = '{' +
        '"district":"海淀区","weather":"多云","temperature":27.4,"report_time":"8 分钟前发布",' +
        '"forecast":[' +
        '{"date":"2026-08-22","week":"星期六","temp_max":32.6,"temp_min":22.6,' +
        '"weather_day":"雷阵雨","weather_night":"雷阵雨","pop":59.6},' +
        '{"date":"2026-08-23","week":"星期日","temp_max":33,"temp_min":23,' +
        '"weather_day":"多云","weather_night":"多云"},' +
        '{"date":"2026-08-24","week":"星期一","temp_max":30,"temp_min":22,' +
        '"weather_day":"晴","weather_night":"晴","pop":0}' +
        ']}';
      const parsed: CampusWeather = WeatherSourceParser.parse(payload, '01', '西土城');
      expect(parsed.district).assertEqual('海淀区');
      expect(parsed.currentTemperature).assertEqual(27);
      expect(parsed.days.length).assertEqual(2);
      expect(parsed.days[0].temperatureMaximum).assertEqual(33);
      expect(parsed.days[0].temperatureMinimum).assertEqual(23);
      expect(parsed.days[0].precipitationProbability).assertEqual(60);
      expect(parsed.days[1].precipitationProbability).assertNull();
    });

    it('weather_parser_rejects_invalid_dates', 0, () => {
      const payload: string = '{' +
        '"district":"海淀区","weather":"晴","temperature":20,"report_time":"刚刚",' +
        '"forecast":[' +
        '{"date":"2026-02-30","week":"星期六","temp_max":30,"temp_min":20,' +
        '"weather_day":"晴","weather_night":"晴","pop":40},' +
        '{"date":"2026-08-23","week":"星期日","temp_max":31,"temp_min":21,' +
        '"weather_day":"晴","weather_night":"多云","pop":20}' +
        ']}';
      let threw: boolean = false;
      try {
        WeatherSourceParser.parse(payload, '01', '西土城');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('weather_card_starts_collapsed', 0, () => {
      expect(WeatherCardPolicy.startsExpanded).assertFalse();
      expect(WeatherCardPolicy.toggled(WeatherCardPolicy.startsExpanded)).assertTrue();
    });
  });
}
