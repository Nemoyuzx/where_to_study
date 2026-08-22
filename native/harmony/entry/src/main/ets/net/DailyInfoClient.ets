// UAPI 校区天气客户端：西土城按海淀区、沙河按昌平区查询。
// 与 Rust/Swift/Kotlin 端保持相同的 HTTPS 主机、响应上限和字段校验。
import { http } from '@kit.NetworkKit';
import { AppMeta } from '../common/AppMeta';
import { JsonUtil } from '../common/JsonUtil';
import { StrictDates } from '../common/StrictDates';
import { Utf8 } from '../common/Utf8';
import { HttpRequestSpec, HttpResult, HttpUtil } from './HttpUtil';

export class CampusWeatherDay {
  readonly date: string;
  readonly weekday: string;
  readonly weatherDay: string;
  readonly weatherNight: string;
  readonly temperatureMaximum: number;
  readonly temperatureMinimum: number;
  readonly precipitationProbability: number | null;

  constructor(date: string, weekday: string, weatherDay: string, weatherNight: string,
    temperatureMaximum: number, temperatureMinimum: number, precipitationProbability: number | null) {
    this.date = date;
    this.weekday = weekday;
    this.weatherDay = weatherDay;
    this.weatherNight = weatherNight;
    this.temperatureMaximum = temperatureMaximum;
    this.temperatureMinimum = temperatureMinimum;
    this.precipitationProbability = precipitationProbability;
  }
}

export class CampusWeather {
  readonly campusID: string;
  readonly campusName: string;
  readonly district: string;
  readonly currentWeather: string;
  readonly currentTemperature: number;
  readonly reportTime: string;
  readonly days: CampusWeatherDay[];

  constructor(campusID: string, campusName: string, district: string, currentWeather: string,
    currentTemperature: number, reportTime: string, days: CampusWeatherDay[]) {
    this.campusID = campusID;
    this.campusName = campusName;
    this.district = district;
    this.currentWeather = currentWeather;
    this.currentTemperature = currentTemperature;
    this.reportTime = reportTime;
    this.days = days;
  }
}

export class CampusWeatherTarget {
  readonly campusID: string;
  readonly campusName: string;
  readonly adcode: string;

  constructor(campusID: string, campusName: string, adcode: string) {
    this.campusID = campusID;
    this.campusName = campusName;
    this.adcode = adcode;
  }
}

export class DailyInfoClientError extends Error {
  constructor(message: string) {
    super(message);
  }
}

export interface WeatherFetching {
  fetchWeather(campusID: string): Promise<CampusWeather>;
}

export class WeatherSourceParser {
  static readonly maximumPayloadBytes: number = 128 * 1024;

  static target(campusID: string): CampusWeatherTarget {
    const normalized: string = campusID.trim();
    if (normalized === '01' || normalized === '1') {
      return new CampusWeatherTarget('01', '西土城', '110108');
    }
    if (normalized === '04' || normalized === '4') {
      return new CampusWeatherTarget('04', '沙河', '110114');
    }
    throw new DailyInfoClientError('暂不支持该校区的天气查询。');
  }

  static parse(data: string, campusID: string, campusName: string): CampusWeather {
    if (Utf8.bytes(data).length > WeatherSourceParser.maximumPayloadBytes) {
      throw new DailyInfoClientError('生活信息响应过大。');
    }
    const payload: Record<string, Object> | null = JsonUtil.parseObject(data);
    if (payload === null) {
      throw new DailyInfoClientError('天气数据格式不正确。');
    }
    const district: string = WeatherSourceParser.requiredString(payload, 'district');
    const currentWeather: string = WeatherSourceParser.requiredString(payload, 'weather');
    const reportTime: string = WeatherSourceParser.requiredString(payload, 'report_time');
    const currentTemperature: number = WeatherSourceParser.roundedTemperature(
      WeatherSourceParser.requiredNumber(payload, 'temperature'));
    if (!Array.isArray(payload['forecast'])) {
      throw new DailyInfoClientError('天气数据格式不正确。');
    }
    const forecast: Object[] = JsonUtil.array(payload['forecast']);
    if (forecast.length < 2) {
      throw new DailyInfoClientError('天气数据缺少今日或明日信息。');
    }
    const days: CampusWeatherDay[] = [];
    for (let index = 0; index < 2; index++) {
      const item: Record<string, Object> = JsonUtil.record(forecast[index]);
      const date: string = WeatherSourceParser.requiredString(item, 'date');
      if (StrictDates.parseDateString(date) === null) {
        throw new DailyInfoClientError('天气数据日期格式不正确。');
      }
      let probability: number | null = null;
      if (item['pop'] !== undefined && item['pop'] !== null) {
        probability = WeatherSourceParser.roundedProbability(
          WeatherSourceParser.requiredNumber(item, 'pop'));
      }
      days.push(new CampusWeatherDay(
        date,
        WeatherSourceParser.requiredString(item, 'week'),
        WeatherSourceParser.requiredString(item, 'weather_day'),
        WeatherSourceParser.requiredString(item, 'weather_night'),
        WeatherSourceParser.roundedTemperature(WeatherSourceParser.requiredNumber(item, 'temp_max')),
        WeatherSourceParser.roundedTemperature(WeatherSourceParser.requiredNumber(item, 'temp_min')),
        probability
      ));
    }
    return new CampusWeather(
      campusID, campusName, district, currentWeather, currentTemperature, reportTime, days);
  }

  private static requiredString(payload: Record<string, Object>, key: string): string {
    const raw: Object | undefined = payload[key];
    if (typeof raw !== 'string') {
      throw new DailyInfoClientError('天气数据格式不正确。');
    }
    const value: string = (raw as string).trim();
    if (value.length === 0) {
      throw new DailyInfoClientError('天气数据缺少今日或明日信息。');
    }
    return value;
  }

  private static requiredNumber(payload: Record<string, Object>, key: string): number {
    const raw: Object | undefined = payload[key];
    if (typeof raw !== 'number') {
      throw new DailyInfoClientError('天气数据格式不正确。');
    }
    return raw as number;
  }

  private static roundedTemperature(value: number): number {
    if (!Number.isFinite(value) || value < -150 || value > 100) {
      throw new DailyInfoClientError('天气温度超出合理范围。');
    }
    return Math.round(value);
  }

  private static roundedProbability(value: number): number {
    if (!Number.isFinite(value) || value < 0 || value > 100) {
      throw new DailyInfoClientError('天气降水概率超出合理范围。');
    }
    return Math.round(value);
  }
}

export class UAPIWeatherClient implements WeatherFetching {
  private static readonly source: string = 'https://uapis.cn';
  private static readonly sourceHost: string = 'uapis.cn';

  async fetchWeather(campusID: string): Promise<CampusWeather> {
    const target: CampusWeatherTarget = WeatherSourceParser.target(campusID);
    const url: string = UAPIWeatherClient.source + '/api/v1/misc/weather?adcode=' + target.adcode +
      '&lang=zh&forecast=true';
    const spec: HttpRequestSpec = new HttpRequestSpec();
    spec.method = http.RequestMethod.GET;
    spec.connectTimeoutMs = 10000;
    spec.readTimeoutMs = 15000;
    spec.maxBytes = WeatherSourceParser.maximumPayloadBytes;
    spec.headers['Accept'] = 'application/json';
    spec.headers['User-Agent'] = AppMeta.holidayUserAgent;
    const result: HttpResult = await HttpUtil.perform(url, spec, UAPIWeatherClient.sourceHost);
    if (result.statusCode < 200 || result.statusCode > 299) {
      throw new DailyInfoClientError(
        '生活信息接口返回错误，HTTP ' + result.statusCode.toString() + '。');
    }
    return WeatherSourceParser.parse(result.body, target.campusID, target.campusName);
  }
}
