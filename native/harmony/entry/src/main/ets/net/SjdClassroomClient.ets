// 与 iOS 端 ClassroomClient.swift 的 SJDClassroomClient + SJDClassroomParser 对应：
// 当天两校区实时空教室获取与解析。
import { ClassroomsCache } from '../common/Models';
import { StrictDates } from '../common/StrictDates';
import { Credentials } from '../store/CredentialStore';
import { ClassroomClientError } from './SjdErrors';
import { SJDAPIClient } from './SjdApi';
import { SJDClassroomParser } from './parsers/SjdClassroomParser';

export interface ClassroomFetching {
  fetch(credentials: Credentials, targetDate: string): Promise<ClassroomsCache>;
}
export class SJDClassroomClient implements ClassroomFetching {
  private readonly api: SJDAPIClient;

  constructor() {
    this.api = new SJDAPIClient();
  }

  async fetch(credentials: Credentials, targetDate: string): Promise<ClassroomsCache> {
    const today: string = StrictDates.formatDateParts(StrictDates.todayParts());
    if (targetDate !== today) {
      throw ClassroomClientError.service('空教室实时接口仅支持当天查询。');
    }
    const token: string = await this.api.login(credentials);
    const results: string[] = await Promise.all([
      this.api.classrooms(token, '01'),
      this.api.classrooms(token, '04')
    ]);
    const payloads: Map<string, string> = new Map<string, string>();
    payloads.set('01', results[0]);
    payloads.set('04', results[1]);
    return SJDClassroomParser.parse(payloads, targetDate, StrictDates.formatFetchedAt(Date.now()));
  }
}
