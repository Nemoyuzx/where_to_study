// 学期（term）自动检测：对应 Tauri 端 planner-domain.js 的
// suggestTermForDate / isValidTermId / isValidTermStartDate / termMatchesCurrentPeriod。
// 全部日期运算复用 StrictDates（上海时区墙上日历日），与课表周次计算同源。
// 业务约定：获取/刷新课表成功后，教务返回的 term 会覆盖本地设置，本模块仅用于
// 手动填写辅助与一致性提示。

import { DateParts, StrictDates } from './StrictDates';

export class SemesterSuggestion {
  readonly termID: string;
  readonly termStartDate: string;

  constructor(termID: string, termStartDate: string) {
    this.termID = termID;
    this.termStartDate = termStartDate;
  }
}

export class SemesterLogic {
  // 北邮校历约定：春季学期（term 2）3 月初开学，秋季学期（term 1）9 月初开学。
  private static readonly termIDPattern: RegExp = /^\d{4}-\d{4}-[12]$/;

  // 包含给定日期的那个周的周一。
  private static mondayOfWeekContaining(year: number, month: number, day: number): string {
    const parts: DateParts = new DateParts(year, month, day);
    const offset: number = StrictDates.weekdayMonday1(parts) - 1; // 周一 = 1
    return StrictDates.formatDateParts(StrictDates.addDays(parts, -offset));
  }

  // 按给定日期建议当前学期：2-7 月为春季 (year-1)-year-2（开学日=包含 3 月 2 日那周的周一）；
  // 8-12 月为秋季 year-(year+1)-1（开学日=包含 9 月 1 日那周的周一）；
  // 1 月仍属于上一年的秋季学期。
  static suggestForDate(today: DateParts): SemesterSuggestion {
    const month: number = today.month;
    const year: number = today.year;
    if (month >= 2 && month <= 7) {
      return new SemesterSuggestion(
        (year - 1) + '-' + year + '-2',
        SemesterLogic.mondayOfWeekContaining(year, 3, 2)
      );
    }
    const fallStartYear: number = month === 1 ? year - 1 : year;
    return new SemesterSuggestion(
      fallStartYear + '-' + (fallStartYear + 1) + '-1',
      SemesterLogic.mondayOfWeekContaining(fallStartYear, 9, 1)
    );
  }

  // 按上海时区“今天”建议当前学期。
  static suggestCurrentPeriod(): SemesterSuggestion {
    return SemesterLogic.suggestForDate(StrictDates.todayParts());
  }

  // 学期编号形如 2025-2026-2 / 2025-2026-1；首尾空白容忍。
  static isValidTermID(value: string): boolean {
    return SemesterLogic.termIDPattern.test(value.trim());
  }

  // 第一周周一为严格 YYYY-MM-DD 且是真实日历日。
  static isValidTermStartDate(value: string): boolean {
    return StrictDates.parseDateString(value.trim()) !== null;
  }

  // 指定日期下的学期一致性：两字段都合法且与建议值完全一致。
  static matchesPeriod(termID: string, termStartDate: string, today: DateParts): boolean {
    if (!SemesterLogic.isValidTermID(termID)) {
      return false;
    }
    const suggested: SemesterSuggestion = SemesterLogic.suggestForDate(today);
    return termID.trim() === suggested.termID && termStartDate.trim() === suggested.termStartDate;
  }

  // 与当前周期的一致性（内部以“今天”为基准）。
  static matchesCurrentPeriod(termID: string, termStartDate: string): boolean {
    return SemesterLogic.matchesPeriod(termID, termStartDate, StrictDates.todayParts());
  }
}
