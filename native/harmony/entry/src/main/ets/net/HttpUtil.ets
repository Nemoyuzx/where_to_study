// 网络传输层：基于 @ohos.net.http 的请求封装。
// 与 iOS 端 SJDURLSessionTransport + SJDNetworkPolicy 对齐：
// 1. 手动处理重定向，每一步都校验安全策略（HTTPS、固定主机、443 端口、无内嵌凭据）；
// 2. 响应体按上限截断检查（对应 .responseTooLarge）；
// 3. 传输失败统一转为可读错误信息。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { UrlPolicy } from './UrlPolicy';
import { Utf8 } from '../common/Utf8';

export class HttpTooLargeError extends Error {
  constructor() {
    super('响应过大。');
  }
}

export class HttpResult {
  readonly statusCode: number;
  readonly body: string;

  constructor(statusCode: number, body: string) {
    this.statusCode = statusCode;
    this.body = body;
  }
}

export class HttpRequestSpec {
  method: http.RequestMethod = http.RequestMethod.GET;
  headers: Record<string, string> = {};
  body: string = '';
  connectTimeoutMs: number = 20000;
  readTimeoutMs: number = 30000;
  maxBytes: number = 2 * 1024 * 1024;
  maxRedirects: number = 5;

  constructor() {
  }
}

export class HttpUtil {
  static readonly maximumRedirects: number = 5;

  static async perform(url: string, spec: HttpRequestSpec, allowedHost: string): Promise<HttpResult> {
    let currentUrl: string = url;
    const maximumRedirects: number = Math.max(0, Math.min(spec.maxRedirects, HttpUtil.maximumRedirects));
    for (let redirect = 0; redirect <= maximumRedirects; redirect++) {
      if (!UrlPolicy.allows(currentUrl, allowedHost)) {
        throw new Error('请求地址不符合安全策略。');
      }
      const client: http.HttpRequest = http.createHttp();
      try {
        const response: http.HttpResponse = await client.request(currentUrl, {
          method: spec.method,
          header: spec.headers,
          extraData: spec.body,
          connectTimeout: spec.connectTimeoutMs,
          readTimeout: spec.readTimeoutMs,
          // 以字节为单位接收并校验上限，避免 UTF-16 字符数与字节数的偏差（BUG-004 修复）。
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          maxRedirects: 0
        });
        const code: number = typeof response.responseCode === 'number' ? response.responseCode as number : 0;
        if (code >= 300 && code < 400) {
          if (redirect >= maximumRedirects) {
            throw new Error('请求重定向次数过多。');
          }
          const location: string | null = HttpUtil.headerValue(response.header, 'Location');
          if (location === null) {
            throw new Error('请求被重定向但没有目标地址。');
          }
          currentUrl = UrlPolicy.resolveRedirect(currentUrl, location);
          continue;
        }
        const body: string = HttpUtil.responseBody(response.result, spec.maxBytes);
        return new HttpResult(code, body);
      } catch (e) {
        if (e instanceof HttpTooLargeError) {
          throw e;
        }
        if (e instanceof Error) {
          const message: string = e.message;
          if (message === '请求地址不符合安全策略。' || message === '请求被重定向但没有目标地址。' ||
            message === '请求重定向次数过多。' || message === '响应过大。') {
            throw e;
          }
        }
        throw new Error('无法连接服务器，请检查网络后重试。');
      } finally {
        client.destroy();
      }
    }
    throw new Error('请求重定向次数过多。');
  }

  // 校验字节上限后再解码；超限不执行解码（BUG-005：尽早拒绝，降低内存放大）。
  private static responseBody(result: Object | undefined, maxBytes: number): string {
    if (result instanceof ArrayBuffer) {
      if (result.byteLength > maxBytes) {
        throw new HttpTooLargeError();
      }
      return new util.TextDecoder('utf-8').decode(new Uint8Array(result));
    }
    if (typeof result === 'string') {
      if (Utf8.bytes(result as string).length > maxBytes) {
        throw new HttpTooLargeError();
      }
      return result as string;
    }
    return '';
  }

  private static headerValue(header: Object, name: string): string | null {
    const record: Record<string, Object> = header as Record<string, Object>;
    const direct: Object | undefined = record[name];
    if (typeof direct === 'string') {
      return direct as string;
    }
    const lower: Object | undefined = record[name.toLowerCase()];
    if (typeof lower === 'string') {
      return lower as string;
    }
    return null;
  }
}
