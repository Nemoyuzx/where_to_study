// 纯 ArkTS 的 SHA-1 实现，与 iOS 端 CryptoKit Insecure.SHA1 输出一致，
// 用于从课表字段生成稳定的课程 ID（取十六进制摘要前 12 位）。
// 输入按 UTF-8 编码后计算，含代理对与多字节字符处理。
export class Sha1 {
  static hexOfUtf8(data: string): string {
    const bytes: number[] = [];
    for (let i = 0; i < data.length; i++) {
      const code: number = data.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
      } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < data.length &&
        data.charCodeAt(i + 1) >= 0xDC00 && data.charCodeAt(i + 1) <= 0xDFFF) {
        const hi: number = code - 0xD800;
        const lo: number = data.charCodeAt(i + 1) - 0xDC00;
        const cp: number = 0x10000 + (hi << 10) + lo;
        bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F),
          0x80 | (cp & 0x3F));
        i++;
      } else {
        bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
    }
    return Sha1.hexOfBytes(bytes);
  }

  private static hexOfBytes(msg: number[]): string {
    const padded: number[] = msg.slice();
    padded.push(0x80);
    while (padded.length % 64 !== 56) {
      padded.push(0);
    }
    // 消息长度按 64 位大端写入；本项目长度远小于 2^32。
    const bitLen: number = msg.length * 8;
    padded.push(0, 0, 0, 0,
      (bitLen >>> 24) & 0xFF, (bitLen >>> 16) & 0xFF, (bitLen >>> 8) & 0xFF, bitLen & 0xFF);

    let h0: number = 0x67452301;
    let h1: number = 0xEFCDAB89;
    let h2: number = 0x98BADCFE;
    let h3: number = 0x10325476;
    let h4: number = 0xC3D2E1F0;
    const w: number[] = new Array<number>(80);

    for (let off = 0; off < padded.length; off += 64) {
      for (let i = 0; i < 16; i++) {
        const base: number = off + 4 * i;
        w[i] = ((padded[base] << 24) | (padded[base + 1] << 16) | (padded[base + 2] << 8) |
          padded[base + 3]) | 0;
      }
      for (let i = 16; i < 80; i++) {
        const v: number = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
        w[i] = ((v << 1) | (v >>> 31)) | 0;
      }
      let a: number = h0;
      let b: number = h1;
      let c: number = h2;
      let d: number = h3;
      let e: number = h4;
      for (let i = 0; i < 80; i++) {
        let f: number = 0;
        let k: number = 0;
        if (i < 20) {
          f = (b & c) | (~b & d);
          k = 0x5A827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ED9EBA1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8F1BBCDC;
        } else {
          f = b ^ c ^ d;
          k = 0xCA62C1D6;
        }
        const temp: number = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) | 0;
        e = d;
        d = c;
        c = ((b << 30) | (b >>> 2)) | 0;
        b = a;
        a = temp;
      }
      h0 = (h0 + a) | 0;
      h1 = (h1 + b) | 0;
      h2 = (h2 + c) | 0;
      h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0;
    }

    const words: number[] = [h0 >>> 0, h1 >>> 0, h2 >>> 0, h3 >>> 0, h4 >>> 0];
    let out: string = '';
    for (const word of words) {
      for (let shift = 28; shift >= 0; shift -= 4) {
        out += ((word >>> shift) & 0xF).toString(16);
      }
    }
    return out;
  }
}
