// UTF-8 编码辅助：字符串 -> 字节数组、字节数组 -> 字符串。
// 与 Swift 端 String.utf8 / String(decoding:as:) 的语义一致。
export class Utf8 {
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
      } else {
        bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
    }
    return bytes;
  }
}
