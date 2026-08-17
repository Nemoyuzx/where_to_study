// JSON 解析/构造辅助：与 Swift 端 Codable 的严格程度对齐。
// 所有缓存读写都必须经过这里，保证缺失字段、错误类型不会静默污染内存模型。

export class JsonUtil {
  static record(value: Object | undefined | null): Record<string, Object> {
    if (value === undefined || value === null || typeof value !== 'object') {
      return {};
    }
    return value as Record<string, Object>;
  }

  static string(value: Object | undefined | null, fallback: string = ''): string {
    if (value === undefined || value === null || typeof value !== 'string') {
      return fallback;
    }
    return value as string;
  }

  static number(value: Object | undefined | null, fallback: number = 0): number {
    if (value === undefined || value === null || typeof value !== 'number') {
      return fallback;
    }
    return value as number;
  }

  static bool(value: Object | undefined | null, fallback: boolean = false): boolean {
    if (value === undefined || value === null || typeof value !== 'boolean') {
      return fallback;
    }
    return value as boolean;
  }

  static nullableNumber(value: Object | undefined | null): number | null {
    if (value === undefined || value === null) {
      return null;
    }
    if (typeof value !== 'number') {
      return null;
    }
    return value as number;
  }

  static array(value: Object | undefined | null): Object[] {
    if (value === undefined || value === null || !Array.isArray(value)) {
      return [];
    }
    return value as Object[];
  }

  static numberArray(value: Object | undefined | null): number[] {
    const result: number[] = [];
    const arr: Object[] = JsonUtil.array(value);
    for (const item of arr) {
      if (typeof item === 'number') {
        result.push(item as number);
      }
    }
    return result;
  }
}
