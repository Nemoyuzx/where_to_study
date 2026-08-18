// 正则辅助：对应 Swift 端 NSRegularExpression 的 matches/firstMatch/firstCapture。
export class RegexUtil {
  static matches(text: string, pattern: string): string[] {
    const re: RegExp = new RegExp(pattern, 'g');
    const result: RegExpMatchArray | null = text.match(re);
    return result === null ? [] : result;
  }

  static firstMatch(text: string, pattern: string): string | null {
    const re: RegExp = new RegExp(pattern);
    const result: RegExpMatchArray | null = text.match(re);
    return result === null ? null : result[0];
  }

  static firstCapture(text: string, pattern: string): string | null {
    const re: RegExp = new RegExp(pattern);
    const result: RegExpMatchArray | null = text.match(re);
    if (result === null || result.length < 2) {
      return null;
    }
    const capture: string | undefined = result[1];
    return capture === undefined ? null : capture;
  }

  // 首个匹配的起始下标；无匹配返回 null。
  static firstMatchIndex(text: string, pattern: string): number | null {
    const re: RegExp = new RegExp(pattern);
    const result: RegExpMatchArray | null = text.match(re);
    if (result === null || result.index === undefined) {
      return null;
    }
    return result.index;
  }

  static integerMatches(text: string): number[] {
    const result: number[] = [];
    for (const piece of RegexUtil.matches(text, '\\d+')) {
      const value: number = Number(piece);
      if (!Number.isNaN(value)) {
        result.push(value);
      }
    }
    return result;
  }

  // 按指定模式取整（例如两位数字的节次节点）。
  static integerMatchesOf(text: string, pattern: string): number[] {
    const result: number[] = [];
    for (const piece of RegexUtil.matches(text, pattern)) {
      const value: number = Number(piece);
      if (!Number.isNaN(value)) {
        result.push(value);
      }
    }
    return result;
  }
}
