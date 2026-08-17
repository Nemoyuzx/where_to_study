// 与 iOS 端 ScheduleClient.swift 的 SJDAPIClient / SJDNetworkPolicy /
// SJDResponseLimits / SJDFormURLEncoder 对应的移动教务 HTTP 客户端。
import { http } from '@kit.NetworkKit';
import { Credentials } from '../store/CredentialStore';
import { JsonUtil } from '../common/JsonUtil';
import { HttpTooLargeError, HttpRequestSpec, HttpResult, HttpUtil } from './HttpUtil';

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
    return HttpUtil.allows(url, SJDNetworkPolicy.allowedHost);
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

export class ScheduleClientError extends Error {
  constructor(message: string) {
    super(message);
  }

  static missingCredentials(): ScheduleClientError {
    return new ScheduleClientError('请先在设置中填写并保存教务账号和密码。');
  }

  static invalidResponse(message: string): ScheduleClientError {
    return new ScheduleClientError(message);
  }

  static service(message: string): ScheduleClientError {
    return new ScheduleClientError(message);
  }
}

export class SJDAPIClient {
  static readonly origin: string = 'https://jwglweixin.bupt.edu.cn';
  static readonly loginReferer: string = SJDAPIClient.origin + '/sjd/#/login';
  static readonly classroomReferer: string = SJDAPIClient.origin + '/sjd/#/restClassroom';
  static readonly loginURL: string = SJDAPIClient.origin + '/bjyddx/login';
  static readonly curriculumURL: string = SJDAPIClient.origin + '/bjyddx/student/curriculum';
  static readonly classroomsURL: string = SJDAPIClient.origin + '/bjyddx/todayClassrooms';

  async login(credentials: Credentials): Promise<string> {
    const account: string = credentials.account.trim();
    if (account.length === 0 || credentials.password.length === 0) {
      throw ScheduleClientError.missingCredentials();
    }
    const form: Map<string, string> = new Map<string, string>();
    form.set('userNo', account);
    form.set('pwd', credentials.password);
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = http.RequestMethod.POST;
    spec.connectTimeoutMs = 20000;
    spec.readTimeoutMs = 20000;
    spec.maxBytes = SJDResponseLimits.maximumLoginBytes;
    spec.body = SJDFormURLEncoder.encode(form);
    spec.headers = SJDAPIClient.headersFor(SJDAPIClient.loginReferer, null);

    const payload: Record<string, Object> = await this.responseObject(
      SJDAPIClient.loginURL, spec, '无法连接移动教务服务。');
    if (!SJDAPIClient.isSuccessful(payload)) {
      throw ScheduleClientError.service(SJDAPIClient.message(payload, '移动教务登录失败。'));
    }
    const data: Record<string, Object> = JsonUtil.record(payload['data']);
    const token: string = JsonUtil.string(data['token']).trim();
    if (token.length === 0) {
      throw ScheduleClientError.invalidResponse('移动教务登录成功但没有返回 token。');
    }
    return token;
  }

  async curriculum(token: string, week: string): Promise<string> {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = http.RequestMethod.POST;
    spec.connectTimeoutMs = 30000;
    spec.readTimeoutMs = 30000;
    spec.maxBytes = SJDResponseLimits.maximumCurriculumBytes;
    spec.headers = SJDAPIClient.headersFor(SJDAPIClient.classroomReferer, token);
    const url: string = SJDAPIClient.curriculumURL + '?week=' + encodeURIComponent(week);

    const result: HttpResult = await this.responseData(url, spec, SJDResponseEndpoint.curriculum);
    if (result.statusCode < 200 || result.statusCode >= 400) {
      throw ScheduleClientError.service('移动教务课表获取失败。');
    }
    let payload: Record<string, Object>;
    try {
      payload = JSON.parse(result.body) as Record<string, Object>;
    } catch (e) {
      throw ScheduleClientError.invalidResponse('移动教务课表返回了无法识别的数据。');
    }
    if (!SJDAPIClient.isSuccessful(payload)) {
      throw ScheduleClientError.invalidResponse('移动教务课表返回了无法识别的数据。');
    }
    return result.body;
  }

  async classrooms(token: string, campusID: string): Promise<string> {
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = http.RequestMethod.GET;
    spec.connectTimeoutMs = 30000;
    spec.readTimeoutMs = 30000;
    spec.maxBytes = SJDResponseLimits.maximumClassroomsBytes;
    spec.headers = SJDAPIClient.headersFor(SJDAPIClient.classroomReferer, token);
    const url: string = SJDAPIClient.classroomsURL + '?campusId=' + encodeURIComponent(campusID);

    const result: HttpResult = await this.responseData(url, spec, SJDResponseEndpoint.classrooms);
    if (result.statusCode < 200 || result.statusCode >= 400) {
      throw ScheduleClientError.service('实时教室数据获取失败，请稍后重试。');
    }
    let payload: Record<string, Object>;
    try {
      payload = JSON.parse(result.body) as Record<string, Object>;
    } catch (e) {
      throw ScheduleClientError.invalidResponse('实时教室服务返回了无法识别的数据。');
    }
    if (!SJDAPIClient.isSuccessful(payload)) {
      throw ScheduleClientError.service(SJDAPIClient.message(payload, '实时教室数据获取失败。'));
    }
    return result.body;
  }

  private async responseObject(
    url: string, spec: HttpRequestSpec, failureMessage: string
  ): Promise<Record<string, Object>> {
    let result: HttpResult;
    try {
      result = await this.responseData(url, spec, SJDResponseEndpoint.login);
    } catch (e) {
      if (e instanceof ScheduleClientError) {
        throw e;
      }
      throw ScheduleClientError.service(failureMessage);
    }
    if (result.statusCode < 200 || result.statusCode >= 400) {
      throw ScheduleClientError.service(failureMessage);
    }
    let payload: Record<string, Object>;
    try {
      payload = JSON.parse(result.body) as Record<string, Object>;
    } catch (e) {
      throw ScheduleClientError.invalidResponse('移动教务返回了无法识别的数据。');
    }
    return payload;
  }

  private async responseData(
    url: string, spec: HttpRequestSpec, endpoint: SJDResponseEndpoint
  ): Promise<HttpResult> {
    if (!SJDNetworkPolicy.allows(url)) {
      throw ScheduleClientError.invalidResponse('移动教务请求地址不符合安全策略。');
    }
    try {
      return await HttpUtil.perform(url, spec, SJDNetworkPolicy.allowedHost);
    } catch (e) {
      if (e instanceof HttpTooLargeError) {
        throw ScheduleClientError.invalidResponse(SJDResponseLimits.oversizedMessage(endpoint));
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error('网络请求失败。');
    }
  }

  private static headersFor(referer: string, token: string | null): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Origin'] = SJDAPIClient.origin;
    headers['Referer'] = referer;
    headers['User-Agent'] = 'Mozilla/5.0';
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    if (token !== null) {
      headers['token'] = token;
    }
    return headers;
  }

  static isSuccessful(payload: Record<string, Object>): boolean {
    return SJDAPIClient.string(payload['code']) === '1';
  }

  static message(payload: Record<string, Object>, fallback: string): string {
    const msg: string = SJDAPIClient.string(payload['Msg']);
    if (msg.length > 0) {
      return msg;
    }
    const lowerMsg: string = SJDAPIClient.string(payload['msg']);
    return lowerMsg.length > 0 ? lowerMsg : fallback;
  }

  static string(value: Object | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    if (typeof value === 'string') {
      return value as string;
    }
    if (typeof value === 'number') {
      return (value as number).toString();
    }
    return '';
  }
}
