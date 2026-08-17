// 与 iOS 端 HolidayClient.swift 对应的节假日数据源客户端：
// 严格校验响应年份、区域、日期、名称与类型，映射 public_holiday/transfer_workday
// 到本地契约，未知类型不写入；另含 2026 年离线兜底数据。
import { http } from '@kit.NetworkKit';
import { HolidayDefaults, HolidaysSnapshot } from '../common/Models';
import { StrictDates } from '../common/StrictDates';
import { AppMeta } from '../common/AppMeta';
import { HolidayClientError, HolidaySourceLimits } from './SjdErrors';
import { HttpRequestSpec, HttpResult, HttpUtil } from './HttpUtil';
import { HolidaySourceParser } from './parsers/HolidaySourceParser';
export interface HolidayFetching {
  fetch(year: number): Promise<HolidaysSnapshot>;
}

export class HolidayClient implements HolidayFetching {
  private readonly source: string;

  constructor(source: string = HolidayDefaults.source) {
    this.source = source;
  }

  async fetch(year: number): Promise<HolidaysSnapshot> {
    if (year < HolidayDefaults.supportedYearsStart || year > HolidayDefaults.supportedYearsEnd) {
      throw HolidayClientError.service('节假日年份不在支持范围内。');
    }
    const url: string = this.source + '/' + year.toString() + '.json';
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = http.RequestMethod.GET;
    spec.connectTimeoutMs = 20000;
    spec.readTimeoutMs = 20000;
    spec.maxBytes = HolidaySourceLimits.maximumPayloadBytes;
    spec.headers['Accept'] = 'application/json';
    spec.headers['User-Agent'] = AppMeta.holidayUserAgent;
    const result: HttpResult = await HttpUtil.perform(url, spec, HolidayClient.sourceHost);
    if (result.statusCode < 200 || result.statusCode > 299) {
      throw HolidayClientError.service('节假日数据源返回错误，HTTP ' + result.statusCode.toString() + '。');
    }
    return HolidaySourceParser.parse(
      result.body, year, this.source, StrictDates.formatFetchedAt(Date.now()));
  }

  // 与移动教务客户端不同，主分支 iOS 的节假日请求不限制重定向；这里按 unpkg.com
  // 主机放行并沿用同一套 HTTPS 安全策略，行为更严格且不影响正常获取。
  private static readonly sourceHost: string = 'unpkg.com';
}
