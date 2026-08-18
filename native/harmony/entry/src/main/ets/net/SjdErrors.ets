// 客户端错误类型（纯模块，无平台依赖，可被主机侧单元测试直接引用）。
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

export class ClassroomClientError extends Error {
  constructor(message: string) {
    super(message);
  }

  static service(message: string): ClassroomClientError {
    return new ClassroomClientError(message);
  }
}

export class HolidayClientError extends Error {
  constructor(message: string) {
    super(message);
  }

  static service(message: string): HolidayClientError {
    return new HolidayClientError(message);
  }
}

export class HolidaySourceLimits {
  static readonly maximumPayloadBytes: number = 256 * 1024;
  static readonly maximumRecords: number = 128;
  static readonly maximumNameLength: number = 80;
  static readonly maximumExpandedItems: number = 512;
}
