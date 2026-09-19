// 会话仅驻留内存。失效代次阻止旧登录/请求回写；只有明确认证过期才重试一次。
export class AuthenticationExpiredError extends Error {
  constructor() { super('登录状态已过期，请刷新后重试。'); }
}

export class SessionLease<T> {
  readonly value: T;
  readonly expiresAt: number;
  constructor(value: T, expiresAt: number) { this.value = value; this.expiresAt = expiresAt; }
}

export class AuthenticatedSession<T> {
  private account: string = '';
  private password: string = '';
  private generation: number = 0;
  private lease: SessionLease<T> | null = null;
  private pending: Promise<SessionLease<T>> | null = null;

  reset(): void {
    this.generation++;
    this.account = '';
    this.password = '';
    this.lease = null;
    this.pending = null;
  }

  async run<R>(account: string, password: string, login: () => Promise<SessionLease<T>>,
    request: (value: T) => Promise<R>): Promise<R> {
    if (this.account !== account || this.password !== password) {
      this.reset();
      this.account = account;
      this.password = password;
    }
    const generation: number = this.generation;
    for (let attempt: number = 0; attempt < 2; attempt++) {
      this.requireCurrent(generation);
      const lease: SessionLease<T> = await this.obtain(generation, login);
      this.requireCurrent(generation);
      try {
        const result: R = await request(lease.value);
        this.requireCurrent(generation);
        return result;
      } catch (error) {
        this.requireCurrent(generation);
        if (!(error instanceof AuthenticationExpiredError)) {
          throw error instanceof Error ? error : new Error('服务暂时不可用，请稍后刷新。');
        }
        // 其他并发请求可能已完成刷新，不能清除它的新 token。
        if (this.lease === lease) { this.lease = null; }
        if (attempt === 1) { throw error; }
      }
    }
    throw new AuthenticationExpiredError();
  }

  private requireCurrent(generation: number): void {
    if (generation !== this.generation) { throw new Error('账户状态已更改，请重新刷新。'); }
  }

  private async obtain(generation: number, login: () => Promise<SessionLease<T>>): Promise<SessionLease<T>> {
    this.requireCurrent(generation);
    if (this.lease !== null && this.lease.expiresAt > Date.now()) { return this.lease; }
    if (this.pending !== null) { return await this.pending; }
    const work: Promise<SessionLease<T>> = login();
    this.pending = work;
    try {
      const lease: SessionLease<T> = await work;
      this.requireCurrent(generation);
      this.lease = lease;
      return lease;
    } finally {
      if (this.pending === work) { this.pending = null; }
    }
  }
}

export class AuthenticationFailure {
  static isExpired(status: number, code: string, message: string): boolean {
    if (status === 403 || status === 423 || code === '403' || code === '423' || status >= 500) { return false; }
    if (status === 401 || code === '401') { return true; }
    return /(?:token|令牌).*(?:expired|invalid|过期|失效)|(?:登录|登陆).*(?:过期|失效)|未登录|请(?:重新|先)登录|not\s+logged\s+in|login\s+(?:expired|required)/i.test(message);
  }
}
