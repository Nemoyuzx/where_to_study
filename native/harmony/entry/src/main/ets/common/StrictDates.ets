// 与 iOS 端 StrictContractDateParser / Calendar.shanghai 对应的日期工具。
// 全部日期运算基于“上海时区墙上时钟的日历日”，以 1970-01-01 为第 0 天，
// 不依赖设备时区，保证任意时区设备上语义一致。
// 契约：日期字符串 YYYY-MM-DD；fetched_at 为不含小数秒的 RFC 3339。

export const SHANGHAI_OFFSET_MS: number = 8 * 60 * 60 * 1000;

export class DateParts {
  readonly year: number;
  readonly month: number; // 1..12
  readonly day: number; // 1..31

  constructor(year: number, month: number, day: number) {
    this.year = year;
    this.month = month;
    this.day = day;
  }

  equals(other: DateParts): boolean {
    return this.year === other.year && this.month === other.month && this.day === other.day;
  }
}

export class StrictDates {
  static isLeapYear(year: number): boolean {
    if (year % 4 !== 0) {
      return false;
    }
    if (year % 100 !== 0) {
      return true;
    }
    return year % 400 === 0;
  }

  static daysInMonth(year: number, month: number): number {
    if (month < 1 || month > 12) {
      return 0;
    }
    const base: number[] = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month === 2 && StrictDates.isLeapYear(year)) {
      return 29;
    }
    return base[month];
  }

  // Howard Hinnant 的 days_from_civil 算法：公历日期 -> 自 1970-01-01 的天数。
  static epochDay(year: number, month: number, day: number): number {
    let y = year;
    if (month <= 2) {
      y -= 1;
    }
    const era: number = Math.floor((y >= 0 ? y : y - 399) / 400);
    const yoe: number = y - era * 400;
    const adjustedMonth: number = month + (month > 2 ? -3 : 9);
    const doy: number = Math.floor((153 * adjustedMonth + 2) / 5) + day - 1;
    const doe: number = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    return era * 146097 + doe - 719468;
  }

  static partsFromEpochDay(epochDay: number): DateParts {
    let z = epochDay + 719468;
    const era: number = Math.floor((z >= 0 ? z : z - 146096) / 146097);
    const doe: number = z - era * 146097;
    const yoe: number = Math.floor(
      (doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    const y: number = yoe + era * 400;
    const doy: number = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    const mp: number = Math.floor((5 * doy + 2) / 153);
    const d: number = doy - Math.floor((153 * mp + 2) / 5) + 1;
    const m: number = mp + (mp < 10 ? 3 : -9);
    return new DateParts(y + (m <= 2 ? 1 : 0), m, d);
  }

  // 严格解析 YYYY-MM-DD：长度、分隔符、数字与真实日历日都必须合法。
  static parseDateString(value: string): DateParts | null {
    if (value.length !== 10) {
      return null;
    }
    if (value.charAt(4) !== '-' || value.charAt(7) !== '-') {
      return null;
    }
    for (let i = 0; i < 10; i++) {
      if (i === 4 || i === 7) {
        continue;
      }
      const c: number = value.charCodeAt(i);
      if (c < 0x30 || c > 0x39) {
        return null;
      }
    }
    const year: number = StrictDates.numberIn(value, 0, 4);
    const month: number = StrictDates.numberIn(value, 5, 2);
    const day: number = StrictDates.numberIn(value, 8, 2);
    if (year <= 0) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > StrictDates.daysInMonth(year, month)) {
      return null;
    }
    return new DateParts(year, month, day);
  }

  static formatDateParts(parts: DateParts): string {
    return StrictDates.pad4(parts.year) + '-' + StrictDates.pad2(parts.month) + '-' +
      StrictDates.pad2(parts.day);
  }

  // 上海时区“今天”的墙上日历日。
  static todayParts(): DateParts {
    const shifted: Date = new Date(Date.now() + SHANGHAI_OFFSET_MS);
    return new DateParts(shifted.getUTCFullYear(), shifted.getUTCMonth() + 1, shifted.getUTCDate());
  }

  static addDays(parts: DateParts, delta: number): DateParts {
    return StrictDates.partsFromEpochDay(
      StrictDates.epochDay(parts.year, parts.month, parts.day) + delta);
  }

  // 周一 = 1 ... 周日 = 7。1970-01-01 为周四（周一制第 4 天）。
  static weekdayMonday1(parts: DateParts): number {
    // 对 1970 年前（负纪元）也返回合法值：先归一化 e%7 到 0..6（BUG-001 修复）。
    const e: number = StrictDates.epochDay(parts.year, parts.month, parts.day);
    return (((e % 7) + 10) % 7) + 1;
  }

  // fetched_at 契约：不含小数秒的 RFC 3339，使用上海偏移 +08:00。
  static formatFetchedAt(epochMs: number): string {
    const shifted: Date = new Date(epochMs + SHANGHAI_OFFSET_MS);
    // 契约要求 4 位年份；超范围钳制（BUG-037 修复）。
    const year: number = Math.min(Math.max(shifted.getUTCFullYear(), 1), 9999);
    return StrictDates.pad4(year) + '-' + StrictDates.pad2(shifted.getUTCMonth() + 1) +
      '-' + StrictDates.pad2(shifted.getUTCDate()) + 'T' + StrictDates.pad2(shifted.getUTCHours()) +
      ':' + StrictDates.pad2(shifted.getUTCMinutes()) + ':' + StrictDates.pad2(shifted.getUTCSeconds()) +
      '+08:00';
  }

  // 解析 fetched_at（Z 或 ±hh:mm），返回 epoch 毫秒；非法返回 null。
  static parseFetchedAt(value: string): number | null {
    // 格式：YYYY-MM-DDTHH:mm:ss(Z|±hh:mm)
    if (value.length !== 20 && value.length !== 25) {
      return null;
    }
    if (value.charAt(4) !== '-' || value.charAt(7) !== '-' || value.charAt(10) !== 'T' ||
      value.charAt(13) !== ':' || value.charAt(16) !== ':') {
      return null;
    }
    for (const idx of [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]) {
      const c: number = value.charCodeAt(idx);
      if (c < 0x30 || c > 0x39) {
        return null;
      }
    }
    const year: number = StrictDates.numberIn(value, 0, 4);
    const month: number = StrictDates.numberIn(value, 5, 2);
    const day: number = StrictDates.numberIn(value, 8, 2);
    const hour: number = StrictDates.numberIn(value, 11, 2);
    const minute: number = StrictDates.numberIn(value, 14, 2);
    const second: number = StrictDates.numberIn(value, 17, 2);
    if (year <= 0) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > StrictDates.daysInMonth(year, month)) {
      return null;
    }
    if (hour > 23 || minute > 59 || second > 59) {
      return null;
    }
    let offsetMinutes: number = 0;
    if (value.length === 20) {
      if (value.charAt(19) !== 'Z') {
        return null;
      }
      offsetMinutes = 0;
    } else {
      if (value.charAt(22) !== ':') {
        return null;
      }
      const sign: string = value.charAt(19);
      const oh: number = StrictDates.numberIn(value, 20, 2);
      const om: number = StrictDates.numberIn(value, 23, 2);
      if ((sign !== '+' && sign !== '-') || oh > 23 || om > 59) {
        return null;
      }
      offsetMinutes = (sign === '+' ? 1 : -1) * (oh * 60 + om);
    }
    const localEpochDay: number = StrictDates.epochDay(year, month, day);
    const localMs: number = ((hour * 60 + minute) * 60 + second) * 1000;
    return localEpochDay * 86400000 + localMs - offsetMinutes * 60000;
  }

  private static numberIn(value: string, start: number, length: number): number {
    let result: number = 0;
    for (let i = start; i < start + length; i++) {
      result = result * 10 + (value.charCodeAt(i) - 0x30);
    }
    return result;
  }

  private static pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private static pad4(n: number): string {
    let s: string = n.toString();
    while (s.length < 4) {
      s = '0' + s;
    }
    return s;
  }
}
