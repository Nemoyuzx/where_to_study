// 网络传输层：基于 @ohos.net.http 的请求封装。
// 与 iOS 端 SJDURLSessionTransport + SJDNetworkPolicy 对齐：
// 1. 手动处理重定向，每一步都校验安全策略（HTTPS、固定主机、443 端口、无内嵌凭据）；
// 2. 响应体按上限截断检查（对应 .responseTooLarge）；
// 3. 传输失败统一转为可读错误信息。
import { http } from '@kit.NetworkKit';

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

  constructor() {
  }
}

export class HttpUtil {
  static readonly maximumRedirects: number = 5;

  static async perform(url: string, spec: HttpRequestSpec, allowedHost: string): Promise<HttpResult> {
    let currentUrl: string = url;
    for (let redirect = 0; redirect <= HttpUtil.maximumRedirects; redirect++) {
      if (!HttpUtil.allows(currentUrl, allowedHost)) {
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
          expectDataType: http.HttpDataType.STRING,
          maxRedirects: 0
        });
        const code: number = typeof response.responseCode === 'number' ? response.responseCode as number : 0;
        if (code >= 300 && code < 400) {
          const location: string | null = HttpUtil.headerValue(response.header, 'Location');
          if (location === null) {
            throw new Error('请求被重定向但没有目标地址。');
          }
          currentUrl = HttpUtil.resolveRedirect(currentUrl, location);
          continue;
        }
        const body: string = typeof response.result === 'string' ? response.result as string : '';
        if (body.length > spec.maxBytes) {
          throw new HttpTooLargeError();
        }
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

  // 与 SJDNetworkPolicy.allows 一致的安全策略检查。
  static allows(url: string, allowedHost: string): boolean {
    const schemeEnd: number = url.indexOf('://');
    if (schemeEnd < 0) {
      return false;
    }
    const scheme: string = url.substring(0, schemeEnd).toLowerCase();
    if (scheme !== 'https') {
      return false;
    }
    const rest: string = url.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    const authority: string = slash < 0 ? rest : rest.substring(0, slash);
    if (authority.indexOf('@') >= 0) {
      return false;
    }
    const colon: number = authority.indexOf(':');
    const host: string = (colon < 0 ? authority : authority.substring(0, colon)).toLowerCase();
    if (host !== allowedHost) {
      return false;
    }
    const port: number = colon < 0 ? 443 : Number(authority.substring(colon + 1));
    return port === 443;
  }

  // 相对重定向地址解析：绝对地址直接使用，其余按基础地址解析。
  static resolveRedirect(base: string, location: string): string {
    if (location.startsWith('https://') || location.startsWith('http://')) {
      return location;
    }
    const schemeEnd: number = base.indexOf('://');
    const scheme: string = base.substring(0, schemeEnd);
    const rest: string = base.substring(schemeEnd + 3);
    const slash: number = rest.indexOf('/');
    const authority: string = slash < 0 ? rest : rest.substring(0, slash);
    if (location.startsWith('/')) {
      return scheme + '://' + authority + location;
    }
    const basePath: string = slash < 0 ? '/' : rest.substring(slash, rest.lastIndexOf('/') + 1);
    return scheme + '://' + authority + basePath + location;
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
