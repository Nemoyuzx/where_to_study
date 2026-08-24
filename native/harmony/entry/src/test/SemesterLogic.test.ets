// 学期自动检测：与 Tauri 端 planner-domain.js 的 suggestTermForDate /
// isValidTermId / isValidTermStartDate / termMatchesCurrentPeriod 行为对齐。
// 参考值由 Tauri 参考实现（src/planner-domain.js）在 Node 中运行得出。
import { describe, it, expect } from '@ohos/hypium';
import { DateParts, StrictDates } from '../main/ets/common/StrictDates';
import { ScheduleDefaults } from '../main/ets/common/Models';
import { SemesterLogic, SemesterSuggestion } from '../main/ets/common/SemesterLogic';

function suggestion(termID: string, termStartDate: string): SemesterSuggestion {
  return new SemesterSuggestion(termID, termStartDate);
}

export default function semesterLogicTest() {
  describe('SemesterLogicTest', () => {
    it('suggest_for_spring_months_uses_previous_year', 0, () => {
      // 2-7 月属于春季学期 (year-1)-year-2；开学日为包含 3 月 2 日那周的周一。
      const mar2026: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2026, 3, 2));
      expect(mar2026.termID).assertEqual('2025-2026-2');
      expect(mar2026.termStartDate).assertEqual('2026-03-02');
      // 同周内其他日期结果一致。
      const mar8: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2026, 3, 8));
      expect(mar8.termID).assertEqual('2025-2026-2');
      expect(mar8.termStartDate).assertEqual('2026-03-02');
      // 3 月 2 日不总落在周一：2025-02-24 / 2024-02-26 均为参考实现输出。
      const feb2025: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2025, 2, 24));
      expect(feb2025.termID).assertEqual('2024-2025-2');
      expect(feb2025.termStartDate).assertEqual('2025-02-24');
      const feb2024: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2024, 2, 26));
      expect(feb2024.termID).assertEqual('2023-2024-2');
      expect(feb2024.termStartDate).assertEqual('2024-02-26');
      // 春季学期最后一月（7 月）仍属当年春季。
      const jul2025: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2025, 7, 31));
      expect(jul2025.termID).assertEqual('2024-2025-2');
      expect(jul2025.termStartDate).assertEqual('2025-02-24');
    });

    it('suggest_for_fall_months_uses_current_year', 0, () => {
      // 8-12 月属于秋季学期 year-(year+1)-1；开学日为包含 9 月 1 日那周的周一。
      const sep2026: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2026, 9, 1));
      expect(sep2026.termID).assertEqual('2026-2027-1');
      expect(sep2026.termStartDate).assertEqual('2026-08-31');
      const dec2026: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2026, 12, 31));
      expect(dec2026.termID).assertEqual('2026-2027-1');
      expect(dec2026.termStartDate).assertEqual('2026-08-31');
      // 9 月 1 日不总落在周一：2025-09-01 恰为周一（参考实现输出）。
      const aug2025: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2025, 8, 1));
      expect(aug2025.termID).assertEqual('2025-2026-1');
      expect(aug2025.termStartDate).assertEqual('2025-09-01');
      const sep2025: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2025, 9, 1));
      expect(sep2025.termID).assertEqual('2025-2026-1');
      expect(sep2025.termStartDate).assertEqual('2025-09-01');
    });

    it('suggest_for_january_uses_previous_years_fall', 0, () => {
      // 1 月仍属于上一年的秋季学期。
      const jan2026: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2026, 1, 15));
      expect(jan2026.termID).assertEqual('2025-2026-1');
      expect(jan2026.termStartDate).assertEqual('2025-09-01');
      const jan2027: SemesterSuggestion = SemesterLogic.suggestForDate(new DateParts(2027, 1, 15));
      expect(jan2027.termID).assertEqual('2026-2027-1');
      expect(jan2027.termStartDate).assertEqual('2026-08-31');
    });

    it('automatic_launch_keeps_only_current_term_cache_metadata', 0, () => {
      const currentCache: SemesterSuggestion = SemesterLogic.resolveAutomaticLaunchTerm(
        '2026-2027-1', '2026-09-07', new DateParts(2026, 8, 24));
      expect(currentCache.termID).assertEqual('2026-2027-1');
      expect(currentCache.termStartDate).assertEqual('2026-09-07');
      expect(SemesterLogic.canUseAutomaticCachedSchedule(
        '2026-2027-1', '2026-09-07', new DateParts(2026, 8, 24))).assertTrue();

      const oldCache: SemesterSuggestion = SemesterLogic.resolveAutomaticLaunchTerm(
        '2025-2026-2', '2026-03-02', new DateParts(2026, 8, 24));
      expect(oldCache.termID).assertEqual('2026-2027-1');
      expect(oldCache.termStartDate).assertEqual('2026-08-31');
      expect(SemesterLogic.canUseAutomaticCachedSchedule(
        '2025-2026-2', '2026-03-02', new DateParts(2026, 8, 24))).assertFalse();

      const invalidDate: SemesterSuggestion = SemesterLogic.resolveAutomaticLaunchTerm(
        '2026-2027-1', '2026-02-30', new DateParts(2026, 12, 31));
      expect(invalidDate.termID).assertEqual('2026-2027-1');
      expect(invalidDate.termStartDate).assertEqual('2026-08-31');
      expect(SemesterLogic.canUseAutomaticCachedSchedule(
        '2026-2027-1', '2026-02-30', new DateParts(2026, 12, 31))).assertFalse();
    });

    it('automatic_launch_handles_january_february_year_boundary', 0, () => {
      const january: SemesterSuggestion = SemesterLogic.resolveAutomaticLaunchTerm(
        '2026-2027-2', '2027-03-01', new DateParts(2027, 1, 1));
      const february: SemesterSuggestion = SemesterLogic.resolveAutomaticLaunchTerm(
        '2026-2027-1', '2026-08-31', new DateParts(2027, 2, 1));
      expect(january.termID).assertEqual('2026-2027-1');
      expect(january.termStartDate).assertEqual('2026-08-31');
      expect(february.termID).assertEqual('2026-2027-2');
      expect(february.termStartDate).assertEqual('2027-03-01');
    });

    it('automatic_launch_refresh_requires_saved_credentials', 0, () => {
      expect(SemesterLogic.shouldRefreshAutomatically(true, true, 'student')).assertTrue();
      expect(SemesterLogic.shouldRefreshAutomatically(false, true, 'student')).assertFalse();
      expect(SemesterLogic.shouldRefreshAutomatically(true, false, 'student')).assertFalse();
      expect(SemesterLogic.shouldRefreshAutomatically(true, true, '   ')).assertFalse();
    });

    it('manual_refresh_preserves_validated_manual_term', 0, () => {
      const automatic: SemesterSuggestion = SemesterLogic.resolveFetchedTerm(
        true, '2026-2027-1', '2026-09-07', 'manual-term', '2026-08-31');
      const manual: SemesterSuggestion = SemesterLogic.resolveFetchedTerm(
        false, '2026-2027-1', '2026-09-07', 'manual-term', '2026-08-31');
      expect(automatic.termID).assertEqual('2026-2027-1');
      expect(automatic.termStartDate).assertEqual('2026-09-07');
      expect(manual.termID).assertEqual('manual-term');
      expect(manual.termStartDate).assertEqual('2026-08-31');
      const emptyManual: SemesterSuggestion = SemesterLogic.resolveFetchedTerm(
        false, '2026-2027-1', '2026-09-07', ScheduleDefaults.termID, ScheduleDefaults.termStartDate);
      expect(emptyManual.termID).assertEqual('');
      expect(emptyManual.termStartDate).assertEqual('');
    });

    it('persisted_term_defaults_are_empty_until_automatic_detection', 0, () => {
      expect(ScheduleDefaults.termID).assertEqual('');
      expect(ScheduleDefaults.termStartDate).assertEqual('');
      expect(SemesterLogic.isValidTermID(ScheduleDefaults.termID)).assertFalse();
      expect(SemesterLogic.isValidTermStartDate(ScheduleDefaults.termStartDate)).assertFalse();
    });

    it('suggest_current_period_equals_suggest_for_date_today', 0, () => {
      const today: DateParts = StrictDates.todayParts();
      const viaToday: SemesterSuggestion = SemesterLogic.suggestForDate(today);
      const viaCurrent: SemesterSuggestion = SemesterLogic.suggestCurrentPeriod();
      expect(viaCurrent.termID).assertEqual(viaToday.termID);
      expect(viaCurrent.termStartDate).assertEqual(viaToday.termStartDate);
    });

    it('is_valid_term_id_accepts_contract_shape', 0, () => {
      expect(SemesterLogic.isValidTermID('2025-2026-2')).assertTrue();
      expect(SemesterLogic.isValidTermID('2025-2026-1')).assertTrue();
      expect(SemesterLogic.isValidTermID(' 2025-2026-2 ')).assertTrue();
      expect(SemesterLogic.isValidTermID('2025-2026-3')).assertFalse();
      expect(SemesterLogic.isValidTermID('2025-2026')).assertFalse();
      expect(SemesterLogic.isValidTermID('25-26-2')).assertFalse();
      expect(SemesterLogic.isValidTermID('')).assertFalse();
    });

    it('is_valid_term_start_date_requires_real_date', 0, () => {
      expect(SemesterLogic.isValidTermStartDate('2026-03-02')).assertTrue();
      expect(SemesterLogic.isValidTermStartDate('2024-02-29')).assertTrue();
      expect(SemesterLogic.isValidTermStartDate('2026-02-30')).assertFalse();
      expect(SemesterLogic.isValidTermStartDate('2026-13-01')).assertFalse();
      expect(SemesterLogic.isValidTermStartDate('2026-3-02')).assertFalse();
      expect(SemesterLogic.isValidTermStartDate('2026-03-02T00:00:00+08:00')).assertFalse();
      expect(SemesterLogic.isValidTermStartDate('')).assertFalse();
    });

    it('matches_period_requires_both_fields_equal_to_suggestion', 0, () => {
      const today: DateParts = new DateParts(2026, 3, 2);
      expect(SemesterLogic.matchesPeriod('2025-2026-2', '2026-03-02', today)).assertTrue();
      // 首尾空白容忍（与参考实现一致）。
      expect(SemesterLogic.matchesPeriod(' 2025-2026-2 ', ' 2026-03-02 ', today)).assertTrue();
      // 日期不同但格式合法 → 不一致。
      expect(SemesterLogic.matchesPeriod('2025-2026-2', '2026-03-09', today)).assertFalse();
      // 学期编号不合法 → 不一致。
      expect(SemesterLogic.matchesPeriod('2025-2026-3', '2026-03-02', today)).assertFalse();
      // 日期格式非法 → 不一致。
      expect(SemesterLogic.matchesPeriod('2025-2026-2', 'not-a-date', today)).assertFalse();
    });

    it('matches_current_period_equals_matches_period_with_today', 0, () => {
      const today: DateParts = StrictDates.todayParts();
      const viaCurrent: SemesterSuggestion = SemesterLogic.suggestCurrentPeriod();
      expect(SemesterLogic.matchesCurrentPeriod(viaCurrent.termID, viaCurrent.termStartDate))
        .assertEqual(SemesterLogic.matchesPeriod(viaCurrent.termID, viaCurrent.termStartDate, today));
      expect(SemesterLogic.matchesCurrentPeriod('', '')).assertFalse();
    });

    it('suggestions_match_reference_implementation', 0, () => {
      // 直接从 Tauri 参考实现导出的完整对拍（仅列举跨年份边界与周首尾情况）。
      const cases: DateParts[] = [
        new DateParts(2026, 3, 2),
        new DateParts(2026, 3, 8),
        new DateParts(2025, 2, 24),
        new DateParts(2024, 2, 26),
        new DateParts(2026, 9, 1),
        new DateParts(2026, 12, 31),
        new DateParts(2027, 1, 15),
        new DateParts(2026, 1, 15),
        new DateParts(2025, 8, 1),
        new DateParts(2025, 9, 1),
        new DateParts(2025, 7, 31)
      ];
      const expected: SemesterSuggestion[] = [
        suggestion('2025-2026-2', '2026-03-02'),
        suggestion('2025-2026-2', '2026-03-02'),
        suggestion('2024-2025-2', '2025-02-24'),
        suggestion('2023-2024-2', '2024-02-26'),
        suggestion('2026-2027-1', '2026-08-31'),
        suggestion('2026-2027-1', '2026-08-31'),
        suggestion('2026-2027-1', '2026-08-31'),
        suggestion('2025-2026-1', '2025-09-01'),
        suggestion('2025-2026-1', '2025-09-01'),
        suggestion('2025-2026-1', '2025-09-01'),
        suggestion('2024-2025-2', '2025-02-24')
      ];
      for (let i = 0; i < cases.length; i++) {
        const actual: SemesterSuggestion = SemesterLogic.suggestForDate(cases[i]);
        expect(actual.termID).assertEqual(expected[i].termID);
        expect(actual.termStartDate).assertEqual(expected[i].termStartDate);
      }
    });
  });
}
