// 与 iOS 端 ScheduleClient.swift 的 SJDScheduleClient + SJDScheduleParser 对应：
// 移动教务个人课表获取与解析（当前周 + 全量周两次请求合并）。
import { ScheduleSnapshot } from '../common/Models';
import { StrictDates } from '../common/StrictDates';
import { Credentials } from '../store/CredentialStore';
import { ScheduleClientError } from './SjdErrors';
import { SJDAPIClient } from './SjdApi';
import { SJDScheduleParser } from './parsers/SjdScheduleParser';

export interface ScheduleFetching {
  fetch(credentials: Credentials, fallbackTermID: string, fallbackTermStartDate: string): Promise<ScheduleSnapshot>;
}

export class SJDScheduleClient implements ScheduleFetching {
  private readonly api: SJDAPIClient;

  constructor() {
    this.api = new SJDAPIClient();
  }

  async fetch(
    credentials: Credentials, fallbackTermID: string, fallbackTermStartDate: string
  ): Promise<ScheduleSnapshot> {
    const token: string = await this.api.login(credentials);
    const results: string[] = await Promise.all([
      this.api.curriculum(token, ''),
      this.api.curriculum(token, 'all')
    ]);
    return SJDScheduleParser.parse(results[0], results[1], fallbackTermID, fallbackTermStartDate);
  }
}

