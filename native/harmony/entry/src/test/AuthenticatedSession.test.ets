import { describe, it, expect } from '@ohos/hypium';
import { AuthenticatedSession, AuthenticationExpiredError, AuthenticationFailure, SessionLease } from '../main/ets/net/AuthenticatedSession';
import { SJDAPIClient } from '../main/ets/net/SjdApi';

class SessionGate {
  private release: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.release = resolve; });
  finish(): void { this.release(); }
}

export default function authenticatedSessionTest() {
  describe('AuthenticatedSessionTest', () => {
    it('sjd_http_500_expiry_requires_explicit_401_code_not_message', 0, () => {
      // 脱敏契约：仅故意无效 token 的公开错误响应，不含真实账号数据。
      for (const body of ['{"code":"401","message":"非法访问：/currentTerm"}',
        '{"code":401,"message":"非法访问：/currentTerm"}']) {
        expect(SJDAPIClient.authenticationExpired(500, body)).assertTrue();
        expect(SJDAPIClient.authenticationExpired(200, body)).assertTrue();
        for (const status of [403, 423, 503]) {
          expect(SJDAPIClient.authenticationExpired(status, body)).assertFalse();
        }
      }
      for (const body of ['{"code":500,"message":"token expired"}',
        '{"code":403,"message":"请先登录"}', '{"code":423,"message":"token expired"}',
        '{"message":"token expired"}', '<html>login required</html>']) {
        expect(SJDAPIClient.authenticationExpired(500, body)).assertFalse();
        expect(SJDAPIClient.authenticationExpired(200, body)).assertFalse();
      }
      expect(SJDAPIClient.authenticationExpired(401, '')).assertTrue();
      // UCloud 的通用规则不获得 SJD 专用的 500 例外。
      expect(AuthenticationFailure.isExpired(500, '401', '')).assertFalse();
    });

    it('sjd_http_500_401_retries_once_and_keeps_retry_bounded', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      let logins: number = 0;
      let requests: number = 0;
      const login = async (): Promise<SessionLease<string>> => new SessionLease<string>(
        (++logins).toString(), Date.now() + 60000);
      const value = await cache.run('synthetic', 'fixture-only', login, async (token: string): Promise<string> => {
        requests++;
        if (requests === 1 && SJDAPIClient.authenticationExpired(500, '{"code":"401"}')) {
          throw new AuthenticationExpiredError();
        }
        return token;
      });
      expect(value).assertEqual('2');
      expect(logins).assertEqual(2);
      expect(requests).assertEqual(2);
      let retryAttempts: number = 0;
      let rejected: boolean = false;
      try {
        await cache.run('synthetic', 'fixture-only', login, async (token: string): Promise<string> => {
          retryAttempts++;
          if (SJDAPIClient.authenticationExpired(500, '{"code":401}')) { throw new AuthenticationExpiredError(); }
          return token;
        });
      } catch (e) { rejected = true; }
      expect(rejected).assertTrue();
      expect(retryAttempts).assertEqual(2);
      expect(logins).assertEqual(3);
    });

    it('concurrent_queries_and_later_refresh_reuse_one_login', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      const gate: SessionGate = new SessionGate();
      let count: number = 0;
      const login = async (): Promise<SessionLease<string>> => {
        count++;
        await gate.promise;
        return new SessionLease<string>('synthetic-token', Date.now() + 60000);
      };
      const query = async (token: string): Promise<string> => token;
      const first = cache.run('synthetic', 'password', login, query);
      const second = cache.run('synthetic', 'password', login, query);
      gate.finish();
      const result = await Promise.all([first, second]);
      expect(result[0]).assertEqual(result[1]);
      await cache.run('synthetic', 'password', login, query);
      expect(count).assertEqual(1);
    });

    it('explicit_expiry_retries_once_and_replaces_only_failed_lease', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      let logins: number = 0;
      let queries: number = 0;
      const login = async (): Promise<SessionLease<string>> => new SessionLease<string>(
        (++logins).toString(), Date.now() + 60000);
      const query = async (token: string): Promise<string> => {
        queries++;
        if (token === '1') { throw new AuthenticationExpiredError(); }
        return token;
      };
      const results = await Promise.all([cache.run('a', 'p', login, query), cache.run('a', 'p', login, query)]);
      expect(logins).assertEqual(2);
      expect(queries).assertEqual(4);
      expect(results.join(',')).assertEqual('2,2');
      let failures: number = 0;
      try {
        await cache.run('a', 'p', login, async (token: string): Promise<string> => {
          failures++;
          throw new AuthenticationExpiredError();
        });
      } catch (e) {}
      expect(failures).assertEqual(2);
      expect(logins).assertEqual(3);
    });

    it('network_parse_permission_and_lock_failures_do_not_login_again', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      let logins: number = 0;
      const login = async (): Promise<SessionLease<string>> => {
        logins++;
        return new SessionLease<string>('token', Date.now() + 60000);
      };
      for (const failure of ['network', 'parse', '403', '423']) {
        try {
          await cache.run('a', 'p', login, async (token: string): Promise<string> => { throw new Error(failure); });
        } catch (e) {}
      }
      expect(logins).assertEqual(1);
      expect(AuthenticationFailure.isExpired(401, '', '')).assertTrue();
      expect(AuthenticationFailure.isExpired(200, '401', '')).assertTrue();
      expect(AuthenticationFailure.isExpired(200, '0', 'token expired')).assertTrue();
      expect(AuthenticationFailure.isExpired(403, '', 'token expired')).assertFalse();
      expect(AuthenticationFailure.isExpired(423, '', 'token expired')).assertFalse();
      expect(AuthenticationFailure.isExpired(200, '423', 'token expired')).assertFalse();
      expect(AuthenticationFailure.isExpired(503, '', 'please login')).assertFalse();
      expect(AuthenticationFailure.isExpired(200, '0', '业务处理失败')).assertFalse();
    });

    it('expired_local_lease_password_account_and_reset_invalidate', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      let count: number = 0;
      const login = async (): Promise<SessionLease<string>> => new SessionLease<string>(
        (++count).toString(), count === 1 ? Date.now() - 1 : Date.now() + 60000);
      const query = async (token: string): Promise<string> => token;
      await cache.run('a', 'p', login, query);
      await cache.run('a', 'p', login, query);
      await cache.run('a', 'changed', login, query);
      await cache.run('b', 'changed', login, query);
      cache.reset();
      await cache.run('b', 'changed', login, query);
      expect(count).assertEqual(5);
    });

    it('late_login_after_reset_is_rejected_and_cannot_repopulate', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      const gate: SessionGate = new SessionGate();
      let logins: number = 0;
      let queries: number = 0;
      const login = async (): Promise<SessionLease<string>> => {
        logins++;
        if (logins === 1) { await gate.promise; }
        return new SessionLease<string>('token', Date.now() + 60000);
      };
      const query = async (token: string): Promise<string> => { queries++; return token; };
      const old: Promise<boolean> = cache.run('a', 'p', login, query).then(() => false).catch(() => true);
      cache.reset();
      await cache.run('a', 'p', login, query);
      gate.finish();
      expect(await old).assertTrue();
      await cache.run('a', 'p', login, query);
      expect(logins).assertEqual(2);
      expect(queries).assertEqual(2);
    });

    it('late_expired_query_cannot_reauthenticate_an_old_account', 0, async () => {
      const cache: AuthenticatedSession<string> = new AuthenticatedSession<string>();
      const started: SessionGate = new SessionGate();
      const gate: SessionGate = new SessionGate();
      let logins: number = 0;
      const login = async (): Promise<SessionLease<string>> => new SessionLease<string>(
        (++logins).toString(), Date.now() + 60000);
      const old: Promise<boolean> = cache.run('old', 'p', login, async (token: string): Promise<string> => {
        started.finish();
        await gate.promise;
        throw new AuthenticationExpiredError();
      }).then(() => false).catch(() => true);
      await started.promise;
      await cache.run('new', 'p', login, async (token: string): Promise<string> => token);
      gate.finish();
      expect(await old).assertTrue();
      expect(logins).assertEqual(2);
    });
  });
}
