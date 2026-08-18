// SJD 端点常量、响应上限、安全策略与表单编码（纯模块，可被主机侧单元测试引用）。
import { UrlPolicy } from './UrlPolicy';

export enum SJDResponseEndpoint {
  login = 0,
  curriculum = 1,
  classrooms = 2
}

export class SJDResponseLimits {
  static readonly maximumLoginBytes: number = 64 * 1024;
  static readonly maximumCurriculumBytes: number = 2 * 1024 * 1024;
  static readonly maximumClassroomsBytes: number = 2 * 1024 * 1024;

  static maximumBytes(endpoint: SJDResponseEndpoint): number {
    if (endpoint === SJDResponseEndpoint.login) {
      return SJDResponseLimits.maximumLoginBytes;
    }
    if (endpoint === SJDResponseEndpoint.curriculum) {
      return SJDResponseLimits.maximumCurriculumBytes;
    }
    return SJDResponseLimits.maximumClassroomsBytes;
  }

  static oversizedMessage(endpoint: SJDResponseEndpoint): string {
    if (endpoint === SJDResponseEndpoint.login) {
      return '移动教务登录响应过大。';
    }
    if (endpoint === SJDResponseEndpoint.curriculum) {
      return '移动教务课表响应过大。';
    }
    return '实时教室数据响应过大。';
  }
}

export class SJDNetworkPolicy {
  static readonly allowedScheme: string = 'https';
  static readonly allowedHost: string = 'jwglweixin.bupt.edu.cn';
  static readonly allowedPort: number = 443;

  static allows(url: string): boolean {
    return UrlPolicy.allows(url, SJDNetworkPolicy.allowedHost);
  }

  // 重定向仅在源、目标都满足安全策略且主机端口一致时允许；
  // 实际实现由 HttpUtil 在每一步重新校验后继续请求。
  static allowsRedirect(from: string, to: string): boolean {
    return SJDNetworkPolicy.allows(from) && SJDNetworkPolicy.allows(to);
  }
}

export class SJDFormURLEncoder {
  // 与 Swift 实现一致：按键排序拼接；字母数字与 * - . _ 保留，
  // 空格转 +，其余字节转 %XX（大写十六进制）。
  static encode(values: Map<string, string>): string {
    const keys: string[] = [];
    for (const key of values.keys()) {
      keys.push(key);
    }
    keys.sort();
    const parts: string[] = [];
    for (const key of keys) {
      const value: string | undefined = values.get(key);
      parts.push(SJDFormURLEncoder.encodeComponent(key) + '=' +
        SJDFormURLEncoder.encodeComponent(value === undefined ? '' : value));
    }
    return parts.join('&');
  }

  private static encodeComponent(value: string): string {
    const hex: string = '0123456789ABCDEF';
    const bytes: number[] = [];
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
      } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < value.length &&
        value.charCodeAt(i + 1) >= 0xDC00 && value.charCodeAt(i + 1) <= 0xDFFF) {
        const hi: number = code - 0xD800;
        const lo: number = value.charCodeAt(i + 1) - 0xDC00;
        const cp: number = 0x10000 + (hi << 10) + lo;
        bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F),
          0x80 | (cp & 0x3F));
        i++;
      } else {
        bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
    }
    let out: string = '';
    for (const byte of bytes) {
      if ((byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) || byte === 0x2A || byte === 0x2D ||
        byte === 0x2E || byte === 0x5F) {
        out += String.fromCharCode(byte);
      } else if (byte === 0x20) {
        out += '+';
      } else {
        out += '%' + hex.charAt(byte >> 4) + hex.charAt(byte & 0x0F);
      }
    }
    return out;
  }
}
