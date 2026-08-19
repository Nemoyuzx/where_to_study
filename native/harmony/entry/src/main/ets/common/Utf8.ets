// UTF-8 编码辅助：字符串 -> 字节数组、字节数组 -> 字符串，
// 以及纯 ArkTS 的标准 Base64 编码（替代 util.Base64Helper，保持纯模块可测）。
export class Utf8 {
  private static readonly base64Chars: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  static base64(bytes: number[]): string {
    let out: string = '';
    let i: number = 0;
    while (i + 3 <= bytes.length) {
      const value: number = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      out += Utf8.base64Chars.charAt((value >> 18) & 0x3F);
      out += Utf8.base64Chars.charAt((value >> 12) & 0x3F);
      out += Utf8.base64Chars.charAt((value >> 6) & 0x3F);
      out += Utf8.base64Chars.charAt(value & 0x3F);
      i += 3;
    }
    const remaining: number = bytes.length - i;
    if (remaining === 1) {
      const value: number = bytes[i] << 16;
      out += Utf8.base64Chars.charAt((value >> 18) & 0x3F);
      out += Utf8.base64Chars.charAt((value >> 12) & 0x3F);
      out += '==';
    } else if (remaining === 2) {
      const value: number = (bytes[i] << 16) | (bytes[i + 1] << 8);
      out += Utf8.base64Chars.charAt((value >> 18) & 0x3F);
      out += Utf8.base64Chars.charAt((value >> 12) & 0x3F);
      out += Utf8.base64Chars.charAt((value >> 6) & 0x3F);
      out += '=';
    }
    return out;
  }

  static bytes(value: string): number[] {
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
      } else if (code >= 0xD800 && code <= 0xDFFF) {
        // 孤立代理对替换为 U+FFFD（对齐 Swift，BUG-062 修复）。
        bytes.push(0xEF, 0xBF, 0xBD);
      } else {
        bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
    }
    return bytes;
  }
}
