// 与 iOS 端 StrictContractDateParser/Calendar.shanghai 行为对齐的测试。
import { describe, it, expect } from '@ohos/hypium';
import { StrictDates, DateParts, SHANGHAI_OFFSET_MS } from '../main/ets/common/StrictDates';

export default function strictDatesTest() {
  describe('StrictDatesTest', () => {
    it('parseDateString_accepts_contract_dates', 0, () => {
      const parts: DateParts | null = StrictDates.parseDateString('2026-03-02');
      expect(parts !== null).assertTrue();
      if (parts !== null) {
        expect(parts.year).assertEqual(2026);
        expect(parts.month).assertEqual(3);
        expect(parts.day).assertEqual(2);
      }
      expect(StrictDates.formatDateParts(StrictDates.parseDateString('2026-03-02') as DateParts))
        .assertEqual('2026-03-02');
    });

    it('parseDateString_rejects_invalid_dates', 0, () => {
      for (const value of ['2026-02-30', '2026-13-01', '2026-1-01', '2026-00-10',
        '2026-03-0a', 'abcd-ef-gh', '2026-03-02T00:00:00+08:00', '']) {
        expect(StrictDates.parseDateString(value)).assertNull();
      }
    });

    it('weekday_monday_first_matches_shanghai_calendar', 0, () => {
      expect(StrictDates.weekdayMonday1(new DateParts(2026, 3, 2))).assertEqual(1);
      expect(StrictDates.weekdayMonday1(new DateParts(2026, 3, 8))).assertEqual(7);
      expect(StrictDates.weekdayMonday1(new DateParts(1970, 1, 1))).assertEqual(4);
    });

    it('weekday_monday_first_is_valid_before_1970', 0, () => {
      // BUG-001：1970 年前日期不得返回 0 或负数。
      expect(StrictDates.weekdayMonday1(new DateParts(1969, 12, 28))).assertEqual(7);
      expect(StrictDates.weekdayMonday1(new DateParts(1969, 12, 29))).assertEqual(1);
      expect(StrictDates.weekdayMonday1(new DateParts(1968, 12, 29))).assertEqual(7);
      expect(StrictDates.weekdayMonday1(new DateParts(1900, 1, 1))).assertEqual(1);
    });

    it('iso_week_number_handles_year_boundaries', 0, () => {
      expect(StrictDates.isoWeekNumber(new DateParts(2026, 1, 1))).assertEqual(1);
      expect(StrictDates.isoWeekNumber(new DateParts(2026, 8, 25))).assertEqual(35);
      expect(StrictDates.isoWeekNumber(new DateParts(2021, 1, 1))).assertEqual(53);
      expect(StrictDates.isoWeekNumber(new DateParts(2021, 1, 4))).assertEqual(1);
    });

    it('epoch_day_round_trips', 0, () => {
      expect(StrictDates.epochDay(1970, 1, 1)).assertEqual(0);
      const parts: DateParts = StrictDates.partsFromEpochDay(20000);
      expect(StrictDates.epochDay(parts.year, parts.month, parts.day)).assertEqual(20000);
    });

    it('add_days_crosses_month_and_year', 0, () => {
      const feb: DateParts = new DateParts(2026, 2, 28);
      expect(StrictDates.formatDateParts(StrictDates.addDays(feb, 1))).assertEqual('2026-03-01');
      const dec: DateParts = new DateParts(2026, 12, 31);
      expect(StrictDates.formatDateParts(StrictDates.addDays(dec, 1))).assertEqual('2027-01-01');
    });

    it('leap_year_rules_match_gregorian', 0, () => {
      expect(StrictDates.isLeapYear(2024)).assertTrue();
      expect(StrictDates.isLeapYear(1900)).assertFalse();
      expect(StrictDates.isLeapYear(2000)).assertTrue();
      expect(StrictDates.daysInMonth(2024, 2)).assertEqual(29);
      expect(StrictDates.daysInMonth(2026, 2)).assertEqual(28);
    });

    it('fetched_at_round_trips_without_fractional_seconds', 0, () => {
      const epoch: number = StrictDates.parseFetchedAt('2026-01-05T08:00:00+08:00') as number;
      expect(epoch).assertEqual(StrictDates.epochDay(2026, 1, 5) * 86400000);
      expect(StrictDates.formatFetchedAt(epoch)).assertEqual('2026-01-05T08:00:00+08:00');
      expect(StrictDates.parseFetchedAt('2026-01-05T00:00:00Z'))
        .assertEqual(StrictDates.epochDay(2026, 1, 5) * 86400000);
      expect(StrictDates.parseFetchedAt('2026-01-05T08:00:00.000+08:00')).assertNull();
      expect(StrictDates.parseFetchedAt('2026-01-05T25:00:00+08:00')).assertNull();
    });

    it('fetched_at_rejects_year_zero_and_clamps_year_format', 0, () => {
      // BUG-002：year<=0 必须拒绝（与 parseDateString 一致）。
      expect(StrictDates.parseFetchedAt('0000-01-01T00:00:00Z')).assertNull();
      expect(StrictDates.parseFetchedAt('0000-02-29T00:00:00Z')).assertNull();
      // BUG-037：formatFetchedAt 对超范围年份钳制为 4 位，保证自身输出可回读。
      const year10000: number = StrictDates.parseFetchedAt('9999-12-31T23:59:59Z') as number;
      const formatted: string = StrictDates.formatFetchedAt(year10000 + 86400000);
      expect(formatted.startsWith('9999-')).assertTrue();
      expect(StrictDates.parseFetchedAt(formatted) !== null).assertTrue();
    });
  });
}
