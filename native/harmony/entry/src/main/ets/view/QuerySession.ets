// RootView 持有的查询页轻量会话：只保留筛选、位置及一份有界的公开班车快照。
// 不存账号、密码、令牌，也不复制/改写 ShuttleBusClient 的接口或响应。
import { ImportantEventFilter, ImportantEventQueryLogic, QueryPageTab } from '../common/QueryLogic';
import { ShuttleBusFetching, ShuttleBusSnapshot } from '../net/ShuttleBusClient';

class QueryShuttleFlight {
  readonly deadlineMillis: number = Date.now() + 55 * 1000;
  private timer: number = -1;
  private rejectWatchdog: ((error: Error) => void) | null = null;
  private ended: boolean = false;

  setRejection(reject: (error: Error) => void): void { this.rejectWatchdog = reject; }

  arm(): void {
    if (this.ended || this.timer >= 0 || this.rejectWatchdog === null) { return; }
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.rejectWatchdog?.(new Error('班车请求超时，请稍后重试。'));
    }, Math.max(0, this.deadlineMillis - Date.now()));
  }

  suspend(): void {
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
  }

  finish(): void {
    this.ended = true;
    this.suspend();
    this.rejectWatchdog = null;
  }

  cancel(): void {
    if (this.ended) { return; }
    this.suspend();
    this.rejectWatchdog?.(new Error('班车请求已取消。'));
    this.finish();
  }
}

@ObservedV2
export class QuerySession {
  static readonly shuttleCacheLifetimeMs: number = 5 * 60 * 1000;

  @Trace selectedTabRawValue: string = QueryPageTab.shuttle;
  @Trace eventFilterRawValue: string = ImportantEventFilter.all;
  @Trace eventCategory: string = '';
  @Trace showEndedEvents: boolean = false;
  @Trace searchText: string = '';
  @Trace requestedVisibleEventCount: number = ImportantEventQueryLogic.initialRequestedCount();
  @Trace shuttleSnapshot: ShuttleBusSnapshot | null = null;
  @Trace shuttleLoading: boolean = false;
  @Trace shuttleError: string = '';
  @Trace shuttleFetchedAtMillis: number = 0;

  eventFirstVisibleIndex: number = 0;
  readonly regularScrollOffsets: Map<string, number> = new Map<string, number>();
  private shuttleScope: string = '';
  private shuttleRequestGeneration: number = 0;
  private shuttleRequest: Promise<void> | null = null;
  private shuttleFlight: QueryShuttleFlight | null = null;
  private viewOwners: number = 0;

  attachView(): void {
    this.viewOwners++;
    this.shuttleFlight?.arm();
  }

  detachView(): void {
    this.viewOwners = Math.max(0, this.viewOwners - 1);
    if (this.viewOwners === 0) { this.shuttleFlight?.suspend(); }
  }

  dispose(): void {
    this.viewOwners = 0;
    this.shuttleRequestGeneration++;
    this.shuttleFlight?.cancel();
    this.shuttleFlight = null;
    this.shuttleRequest = null;
    this.shuttleLoading = false;
  }

  activateScope(sampleMode: boolean): void {
    const nextScope: string = sampleMode ? 'sample' : 'live';
    if (nextScope === this.shuttleScope) { return; }
    this.shuttleFlight?.cancel();
    this.shuttleFlight = null;
    this.shuttleScope = nextScope;
    this.shuttleRequestGeneration++;
    this.shuttleRequest = null;
    this.shuttleSnapshot = null;
    this.shuttleFetchedAtMillis = 0;
    this.shuttleLoading = false;
    this.shuttleError = '';
  }

  hasFreshShuttle(nowMillis: number = Date.now()): boolean {
    const age: number = nowMillis - this.shuttleFetchedAtMillis;
    return this.shuttleSnapshot !== null && this.shuttleFetchedAtMillis > 0 &&
      age >= 0 && age < QuerySession.shuttleCacheLifetimeMs;
  }

  loadShuttle(client: ShuttleBusFetching, sampleMode: boolean, force: boolean = false): Promise<void> {
    this.activateScope(sampleMode);
    if (this.shuttleRequest !== null) { return this.shuttleRequest; }
    if (!force && this.hasFreshShuttle()) { return Promise.resolve(); }
    const generation: number = ++this.shuttleRequestGeneration;
    const scope: string = this.shuttleScope;
    this.shuttleLoading = true;
    this.shuttleError = '';
    const flight: QueryShuttleFlight = new QueryShuttleFlight();
    const watchdog: Promise<ShuttleBusSnapshot> = new Promise<ShuttleBusSnapshot>((resolve, reject) => {
      flight.setRejection(reject);
    });
    flight.arm();
    const fetch: Promise<ShuttleBusSnapshot> = Promise.resolve().then(() => client.fetch());
    const work: Promise<void> = Promise.race([fetch, watchdog])
      .then((snapshot: ShuttleBusSnapshot): void => {
        if (generation !== this.shuttleRequestGeneration || scope !== this.shuttleScope) { return; }
        this.shuttleSnapshot = snapshot;
        this.shuttleFetchedAtMillis = Date.now();
      }, (error: Error): void => {
        if (generation !== this.shuttleRequestGeneration || scope !== this.shuttleScope) { return; }
        const message: string = error instanceof Error ? error.message : String(error);
        this.shuttleError = message.length > 0 ? message : '班车信息暂时无法读取。';
      })
      .finally((): void => {
        flight.finish();
        if (generation === this.shuttleRequestGeneration && scope === this.shuttleScope) {
          this.shuttleLoading = false;
          this.shuttleRequest = null;
          if (this.shuttleFlight === flight) { this.shuttleFlight = null; }
        }
      });
    this.shuttleFlight = flight;
    this.shuttleRequest = work;
    return work;
  }
}
