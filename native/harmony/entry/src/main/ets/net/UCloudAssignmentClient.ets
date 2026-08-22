// 北邮云课堂课程作业同步：复用 where_to_study-site 已验证的
// CAS execution + Cookie + ticket 登录，再换取 UCloud 临时 token。
// 仅向 auth.bupt.edu.cn 提交账号密码；不读取浏览器 Cookie/令牌，
// 不持久化 CAS Cookie、ticket 或 UCloud token。
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppMeta } from '../common/AppMeta';
import { JsonUtil } from '../common/JsonUtil';
import { StrictDates } from '../common/StrictDates';
import { Utf8 } from '../common/Utf8';
import { Credentials } from '../store/CredentialStore';
import { AssignmentDeadlineItem, AssignmentDeadlineResponseParser } from './CalendarDailyInfoClient';
import { SJDFormURLEncoder } from './SjdEncoding';

export interface AssignmentDeadlineFetching {
  fetch(credentials: Credentials, date: string): Promise<AssignmentDeadlineItem[]>;
  reset(): void;
}

class UCloudHTTPResult {
  readonly statusCode: number;
  readonly body: string;
  readonly headers: Record<string, Object>;

  constructor(statusCode: number, body: string, headers: Record<string, Object>) {
    this.statusCode = statusCode;
    this.body = body;
    this.headers = headers;
  }
}

class UCloudSession {
  readonly accessToken: string;
  readonly userID: string;

  constructor(accessToken: string, userID: string) {
    this.accessToken = accessToken;
    this.userID = userID;
  }
}

class UCloudCourse {
  readonly id: string;
  readonly name: string | null;

  constructor(id: string, name: string | null) {
    this.id = id;
    this.name = name;
  }
}

class UCloudAssignmentCache {
  readonly account: string;
  readonly fetchedAt: number;
  readonly items: AssignmentDeadlineItem[];

  constructor(account: string, fetchedAt: number, items: AssignmentDeadlineItem[]) {
    this.account = account;
    this.fetchedAt = fetchedAt;
    this.items = items;
  }
}

export class UCloudAssignmentClient implements AssignmentDeadlineFetching {
  private static readonly casLoginURL: string =
    'https://auth.bupt.edu.cn/authserver/login?service=https%3A%2F%2Fucloud.bupt.edu.cn';
  private static readonly serviceOrigin: string = 'https://ucloud.bupt.edu.cn';
  private static readonly apiOrigin: string = 'https://apiucloud.bupt.edu.cn';
  private static readonly portalAuthorization: string =
    'Basic  cG9ydGFsOnBvcnRhbF9zZWNyZXQ=';
  private static readonly maximumLoginBytes: number = 1024 * 1024;
  private static readonly maximumTokenBytes: number = 512 * 1024;
  private static readonly maximumAPIBytes: number = 8 * 1024 * 1024;
  private static readonly maximumCookieBytes: number = 16 * 1024;
  private static readonly maximumCourses: number = 100;
  private static readonly maximumAssignments: number = 5000;
  private static readonly cacheLifetimeMs: number = 10 * 60 * 1000;

  private cache: UCloudAssignmentCache | null = null;
  private inFlight: Promise<AssignmentDeadlineItem[]> | null = null;
  private inFlightAccount: string = '';
  private revision: number = 0;

  async fetch(credentials: Credentials, date: string): Promise<AssignmentDeadlineItem[]> {
    if (StrictDates.parseDateString(date) === null) {
      throw new Error('作业日期格式不正确。');
    }
    const account: string = credentials.account.trim();
    if (account.length === 0 || credentials.password.length === 0) {
      throw new Error('请先在设置中保存教务账号和密码。');
    }
    let allItems: AssignmentDeadlineItem[];
    const now: number = Date.now();
    if (this.cache !== null && this.cache.account === account &&
      now - this.cache.fetchedAt < UCloudAssignmentClient.cacheLifetimeMs) {
      allItems = this.cache.items;
    } else if (this.inFlight !== null && this.inFlightAccount === account) {
      allItems = await this.inFlight;
    } else {
      const requestRevision: number = this.revision;
      const work: Promise<AssignmentDeadlineItem[]> = this.fetchAll(
        new Credentials(account, credentials.password));
      this.inFlight = work;
      this.inFlightAccount = account;
      try {
        allItems = await work;
        if (requestRevision === this.revision) {
          this.cache = new UCloudAssignmentCache(account, Date.now(), allItems);
        }
      } finally {
        if (this.inFlight === work) {
          this.inFlight = null;
          this.inFlightAccount = '';
        }
      }
    }
    const result: AssignmentDeadlineItem[] = [];
    for (const item of allItems) {
      if (item.deadline.startsWith(date)) {
        result.push(item);
      }
    }
    return result;
  }

  reset(): void {
    this.revision++;
    this.cache = null;
    this.inFlight = null;
    this.inFlightAccount = '';
  }

  private async fetchAll(credentials: Credentials): Promise<AssignmentDeadlineItem[]> {
    const session: UCloudSession = await this.authenticate(credentials);
    const courseQuery: Map<string, string> = new Map<string, string>();
    courseQuery.set('size', '9999');
    courseQuery.set('current', '1');
    courseQuery.set('userId', session.userID);
    courseQuery.set('siteRoleCode', '2');
    const courseRoot: Record<string, Object> = await this.apiGet(
      '/ykt-site/site/list/student/current', courseQuery, session);
    const courses: UCloudCourse[] = UCloudAssignmentClient.courseRecords(courseRoot);
    const allItems: AssignmentDeadlineItem[] = [];
    let successfulCourseRequests: number = 0;
    let firstCourseError: Error | null = null;
    const courseCount: number = Math.min(courses.length, UCloudAssignmentClient.maximumCourses);
    for (let index = 0; index < courseCount; index++) {
      if (allItems.length >= UCloudAssignmentClient.maximumAssignments) {
        break;
      }
      const course: UCloudCourse = courses[index];
      const body: Record<string, Object> = {};
      body['siteId'] = course.id;
      body['userId'] = session.userID;
      body['keyword'] = '';
      body['chapterId'] = '';
      body['nodeId'] = '';
      body['current'] = 1;
      body['size'] = 9999;
      body['studentAssignmentStatus'] = '';
      body['status'] = '';
      body['sortColumn'] = '';
      body['sortType'] = '';
      try {
        const assignmentRoot: Record<string, Object> = await this.apiPost(
          '/ykt-site/work/student/list', body, session);
        successfulCourseRequests++;
        const courseItems: AssignmentDeadlineItem[] =
          AssignmentDeadlineResponseParser.parseAll(assignmentRoot, course.name);
        for (const item of courseItems) {
          allItems.push(item);
        }
      } catch (e) {
        if (firstCourseError === null) {
          firstCourseError = e instanceof Error ? e : new Error('教学云课程作业接口暂时不可用。');
        }
      }
    }
    if (courses.length > 0 && successfulCourseRequests === 0) {
      throw firstCourseError ?? new Error('教学云课程作业接口暂时不可用。');
    }

    try {
      const undoneQuery: Map<string, string> = new Map<string, string>();
      undoneQuery.set('userId', session.userID);
      const undoneRoot: Record<string, Object> = await this.apiGet(
        '/ykt-site/site/student/undone', undoneQuery, session);
      const undone: AssignmentDeadlineItem[] =
        AssignmentDeadlineResponseParser.parseAll(undoneRoot, null);
      for (const item of undone) {
        allItems.push(item);
      }
    } catch (e) {
      // 首页未完成列表仅用于补漏；课程作业列表成功时不因补漏失败而丢弃结果。
    }
    return UCloudAssignmentClient.merge(allItems);
  }

  private async authenticate(credentials: Credentials): Promise<UCloudSession> {
    const loginPage: UCloudHTTPResult = await UCloudAssignmentClient.request(
      UCloudAssignmentClient.casLoginURL, http.RequestMethod.GET,
      UCloudAssignmentClient.htmlHeaders(), '', UCloudAssignmentClient.maximumLoginBytes,
      'auth.bupt.edu.cn', 200, 299);
    const execution: string | null = UCloudAssignmentClient.parseExecution(loginPage.body);
    if (execution === null) {
      throw new Error('统一认证登录页缺少 execution 参数。');
    }
    const cookieHeader: string = UCloudAssignmentClient.cookieHeaderFrom(loginPage.headers);
    if (cookieHeader.length === 0 ||
      Utf8.bytes(cookieHeader).length > UCloudAssignmentClient.maximumCookieBytes) {
      throw new Error('统一认证未返回有效会话 Cookie。');
    }
    const loginFields: Map<string, string> = new Map<string, string>();
    loginFields.set('username', credentials.account);
    loginFields.set('password', credentials.password);
    loginFields.set('type', 'username_password');
    loginFields.set('execution', execution);
    loginFields.set('_eventId', 'submit');
    const loginHeaders: Record<string, string> = UCloudAssignmentClient.htmlHeaders();
    loginHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
    loginHeaders['Cookie'] = cookieHeader;
    loginHeaders['Referer'] = UCloudAssignmentClient.casLoginURL;
    const loginResult: UCloudHTTPResult = await UCloudAssignmentClient.request(
      UCloudAssignmentClient.casLoginURL, http.RequestMethod.POST, loginHeaders,
      SJDFormURLEncoder.encode(loginFields), UCloudAssignmentClient.maximumLoginBytes,
      'auth.bupt.edu.cn', 200, 399);
    const locations: string[] = UCloudAssignmentClient.headerValues(loginResult.headers, 'Location');
    const ticket: string | null = locations.length > 0 ?
      UCloudAssignmentClient.ticketFrom(locations[0]) : null;
    if (ticket === null) {
      throw new Error('统一认证未返回有效票据；请检查账号密码，若官方页面要求验证码请先完成验证。');
    }

    const tokenFields: Map<string, string> = new Map<string, string>();
    tokenFields.set('ticket', ticket);
    tokenFields.set('grant_type', 'third');
    const tokenHeaders: Record<string, string> = UCloudAssignmentClient.apiHeaders(null);
    tokenHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
    const tokenResult: UCloudHTTPResult = await UCloudAssignmentClient.request(
      UCloudAssignmentClient.apiOrigin + '/ykt-basics/oauth/token', http.RequestMethod.POST,
      tokenHeaders, SJDFormURLEncoder.encode(tokenFields), UCloudAssignmentClient.maximumTokenBytes,
      'apiucloud.bupt.edu.cn', 200, 299);
    const tokenRoot: Record<string, Object> | null = JsonUtil.parseObject(tokenResult.body);
    if (tokenRoot === null) {
      throw new Error('教学云令牌接口数据格式不正确。');
    }
    const accessToken: string = JsonUtil.string(tokenRoot['access_token']).trim();
    const userID: string = JsonUtil.string(
      tokenRoot['user_id'] !== undefined ? tokenRoot['user_id'] : tokenRoot['userId']).trim();
    if (accessToken.length === 0) {
      throw new Error('教学云令牌接口未返回访问令牌。');
    }
    if (userID.length === 0) {
      throw new Error('教学云令牌接口未返回用户标识。');
    }
    return new UCloudSession(accessToken, userID);
  }

  private async apiGet(
    path: string, query: Map<string, string>, session: UCloudSession
  ): Promise<Record<string, Object>> {
    const fields: string[] = [];
    for (const key of query.keys()) {
      fields.push(encodeURIComponent(key) + '=' + encodeURIComponent(query.get(key) ?? ''));
    }
    const result: UCloudHTTPResult = await UCloudAssignmentClient.request(
      UCloudAssignmentClient.apiOrigin + path + '?' + fields.join('&'), http.RequestMethod.GET,
      UCloudAssignmentClient.apiHeaders(session.accessToken), '',
      UCloudAssignmentClient.maximumAPIBytes, 'apiucloud.bupt.edu.cn', 200, 299);
    return UCloudAssignmentClient.apiObject(result.body);
  }

  private async apiPost(
    path: string, body: Record<string, Object>, session: UCloudSession
  ): Promise<Record<string, Object>> {
    const headers: Record<string, string> = UCloudAssignmentClient.apiHeaders(session.accessToken);
    headers['Content-Type'] = 'application/json';
    const result: UCloudHTTPResult = await UCloudAssignmentClient.request(
      UCloudAssignmentClient.apiOrigin + path, http.RequestMethod.POST, headers,
      JSON.stringify(body), UCloudAssignmentClient.maximumAPIBytes,
      'apiucloud.bupt.edu.cn', 200, 299);
    return UCloudAssignmentClient.apiObject(result.body);
  }

  private static apiObject(body: string): Record<string, Object> {
    const root: Record<string, Object> | null = JsonUtil.parseObject(body);
    if (root === null) {
      throw new Error('教学云数据接口没有返回有效 JSON。');
    }
    if (root['code'] !== undefined && JsonUtil.string(root['code']) !== '200') {
      const code: string = JsonUtil.string(root['code'], 'unknown');
      throw new Error('教学云数据接口返回业务状态 ' + code + '。');
    }
    return root;
  }

  private static async request(
    url: string, method: http.RequestMethod, headers: Record<string, string>, body: string,
    maximumBytes: number, expectedHost: string, minimumStatus: number, maximumStatus: number
  ): Promise<UCloudHTTPResult> {
    if (!UCloudAssignmentClient.allowsFixedHTTPS(url, expectedHost)) {
      throw new Error('教学云接口地址不受信任。');
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(url, {
        method: method,
        header: headers,
        extraData: body,
        connectTimeout: 8000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxRedirects: 0
      });
      const status: number = typeof response.responseCode === 'number' ?
        response.responseCode as number : 0;
      if (status < minimumStatus || status > maximumStatus) {
        if (status >= 300 && status < 400) {
          throw new Error('教学云接口返回了不受信任的重定向。');
        }
        throw new Error('教学云接口返回 HTTP ' + status.toString() + '。');
      }
      const responseBody: string = UCloudAssignmentClient.responseBody(
        response.result, maximumBytes);
      return new UCloudHTTPResult(status, responseBody,
        response.header as Record<string, Object>);
    } catch (e) {
      if (e instanceof Error && (e.message.startsWith('教学云接口') ||
        e.message.startsWith('统一认证'))) {
        throw e;
      }
      throw new Error('无法连接教学云服务，请检查网络后重试。');
    } finally {
      client.destroy();
    }
  }

  private static responseBody(result: Object | undefined, maximumBytes: number): string {
    if (result instanceof ArrayBuffer) {
      if (result.byteLength > maximumBytes) {
        throw new Error('教学云接口响应过大。');
      }
      return new util.TextDecoder('utf-8').decode(new Uint8Array(result));
    }
    if (typeof result === 'string') {
      const text: string = result as string;
      if (Utf8.bytes(text).length > maximumBytes) {
        throw new Error('教学云接口响应过大。');
      }
      return text;
    }
    return '';
  }

  private static htmlHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Accept'] = 'text/html';
    headers['User-Agent'] = AppMeta.holidayUserAgent;
    return headers;
  }

  private static apiHeaders(accessToken: string | null): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Accept'] = 'application/json, text/plain, */*';
    headers['Authorization'] = UCloudAssignmentClient.portalAuthorization;
    headers['Tenant-Id'] = '000000';
    headers['Referer'] = UCloudAssignmentClient.serviceOrigin + '/';
    headers['User-Agent'] = AppMeta.holidayUserAgent;
    if (accessToken !== null) {
      headers['Blade-Auth'] = accessToken;
    }
    return headers;
  }

  static parseExecution(html: string): string | null {
    const inputPattern: RegExp = new RegExp('<input\\b[^>]*>', 'gi');
    let inputMatch: RegExpExecArray | null = inputPattern.exec(html);
    while (inputMatch !== null) {
      const input: string = inputMatch[0];
      const attributePattern: RegExp = new RegExp(
        '\\b(name|value)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', 'gi');
      let name: string | null = null;
      let value: string | null = null;
      let attribute: RegExpExecArray | null = attributePattern.exec(input);
      while (attribute !== null) {
        let rawValue: string = '';
        for (let group = 2; group <= 4; group++) {
          if (attribute[group] !== undefined && attribute[group].length > 0) {
            rawValue = attribute[group];
            break;
          }
        }
        const key: string = attribute[1].toLowerCase();
        if (key === 'name') {
          name = UCloudAssignmentClient.decodeHTMLEntities(rawValue);
        } else if (key === 'value') {
          value = UCloudAssignmentClient.decodeHTMLEntities(rawValue);
        }
        attribute = attributePattern.exec(input);
      }
      if (name === 'execution' && value !== null && value.length > 0) {
        return value;
      }
      inputMatch = inputPattern.exec(html);
    }
    return null;
  }

  static ticketFrom(location: string): string | null {
    let resolved: string = location;
    if (!location.startsWith('https://') && !location.startsWith('http://')) {
      resolved = UCloudAssignmentClient.serviceOrigin +
        (location.startsWith('/') ? location : '/' + location);
    }
    if (!UCloudAssignmentClient.allowsFixedHTTPS(resolved, 'ucloud.bupt.edu.cn')) {
      return null;
    }
    const question: number = resolved.indexOf('?');
    if (question < 0) {
      return null;
    }
    const hash: number = resolved.indexOf('#', question + 1);
    const query: string = resolved.substring(question + 1, hash < 0 ? resolved.length : hash);
    for (const field of query.split('&')) {
      const equal: number = field.indexOf('=');
      if (equal < 0) {
        continue;
      }
      try {
        const name: string = decodeURIComponent(field.substring(0, equal));
        const value: string = decodeURIComponent(field.substring(equal + 1));
        if (name === 'ticket' && value.length > 0) {
          return value;
        }
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // NetworkKit may expose repeated Set-Cookie headers either as an array or as
  // one comma-joined string. Keep each cookie pair while discarding attributes
  // such as Path and Expires (whose date itself contains a comma).
  static cookieHeaderFrom(headers: Record<string, Object>): string {
    const attributes: string[] = [
      'domain', 'expires', 'httponly', 'max-age', 'partitioned', 'path',
      'priority', 'samesite', 'secure'
    ];
    const pairs: Map<string, string> = new Map<string, string>();
    const values: string[] = UCloudAssignmentClient.headerValues(headers, 'Set-Cookie');
    for (const raw of values) {
      const segments: string[] = raw.split(/[,;]/);
      for (const segment of segments) {
        const candidate: string = segment.trim();
        const equal: number = candidate.indexOf('=');
        if (equal <= 0) {
          continue;
        }
        const name: string = candidate.substring(0, equal).trim();
        const lowerName: string = name.toLowerCase();
        const value: string = candidate.substring(equal + 1).trim();
        if (name.length === 0 || value.length === 0 || name.startsWith('$') ||
          attributes.includes(lowerName)) {
          continue;
        }
        pairs.set(name, name + '=' + value);
      }
    }
    const result: string[] = [];
    for (const pair of pairs.values()) {
      result.push(pair);
    }
    return result.join('; ');
  }

  private static headerValues(headers: Record<string, Object>, name: string): string[] {
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() !== name.toLowerCase()) {
        continue;
      }
      const raw: Object | undefined = headers[key];
      if (typeof raw === 'string') {
        return [raw as string];
      }
      const values: Object[] = JsonUtil.array(raw);
      const strings: string[] = [];
      for (const value of values) {
        if (typeof value === 'string') {
          strings.push(value as string);
        }
      }
      return strings;
    }
    return [];
  }

  private static allowsFixedHTTPS(url: string, expectedHost: string): boolean {
    const prefix: string = 'https://';
    if (!url.toLowerCase().startsWith(prefix)) {
      return false;
    }
    const rest: string = url.substring(prefix.length);
    let authorityEnd: number = rest.length;
    for (const delimiter of ['/', '?', '#']) {
      const index: number = rest.indexOf(delimiter);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }
    const authority: string = rest.substring(0, authorityEnd);
    if (authority.indexOf('@') >= 0) {
      return false;
    }
    const colon: number = authority.indexOf(':');
    const host: string = (colon < 0 ? authority : authority.substring(0, colon)).toLowerCase();
    const port: number = colon < 0 ? 443 : Number(authority.substring(colon + 1));
    return host === expectedHost.toLowerCase() && port === 443;
  }

  private static decodeHTMLEntities(value: string): string {
    return value.replace(/&quot;/g, '"').replace(/&#39;/g, '\'')
      .replace(/&apos;/g, '\'').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  private static courseRecords(root: Record<string, Object>): UCloudCourse[] {
    const firstValue: Record<string, Object> = JsonUtil.record(root['data']);
    const first: Record<string, Object> = Object.keys(firstValue).length > 0 ? firstValue : root;
    const secondValue: Record<string, Object> = JsonUtil.record(first['data']);
    const second: Record<string, Object> = Object.keys(secondValue).length > 0 ? secondValue : first;
    const records: Object[] = JsonUtil.array(second['records']);
    const courses: UCloudCourse[] = [];
    for (const raw of records) {
      const item: Record<string, Object> = JsonUtil.record(raw);
      const id: string = UCloudAssignmentClient.firstString(
        item, ['id', 'siteId', 'courseId']);
      if (id.length === 0) {
        continue;
      }
      const name: string = UCloudAssignmentClient.firstString(
        item, ['siteName', 'courseName', 'siteTitle', 'name']);
      courses.push(new UCloudCourse(id, name.length > 0 ? name : null));
    }
    return courses;
  }

  private static firstString(source: Record<string, Object>, keys: string[]): string {
    for (const key of keys) {
      const value: string = JsonUtil.string(source[key]).trim();
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private static merge(items: AssignmentDeadlineItem[]): AssignmentDeadlineItem[] {
    const merged: Map<string, AssignmentDeadlineItem> = new Map<string, AssignmentDeadlineItem>();
    const count: number = Math.min(items.length, UCloudAssignmentClient.maximumAssignments);
    for (let index = 0; index < count; index++) {
      const item: AssignmentDeadlineItem = items[index];
      const key: string = item.id + '\u001F' + item.deadline;
      const existing: AssignmentDeadlineItem | undefined = merged.get(key);
      if (existing === undefined || (existing.courseName === null && item.courseName !== null)) {
        merged.set(key, item);
      }
    }
    const result: AssignmentDeadlineItem[] = [];
    for (const item of merged.values()) {
      result.push(item);
    }
    result.sort((left: AssignmentDeadlineItem, right: AssignmentDeadlineItem): number => {
      const leftKey: string = left.deadline + '\u001F' + (left.courseName ?? '') +
        '\u001F' + left.title + '\u001F' + left.id;
      const rightKey: string = right.deadline + '\u001F' + (right.courseName ?? '') +
        '\u001F' + right.title + '\u001F' + right.id;
      return leftKey < rightKey ? -1 : (leftKey > rightKey ? 1 : 0);
    });
    return result;
  }
}
