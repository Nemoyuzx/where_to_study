import { describe, it, expect } from '@ohos/hypium';
import { QuerySession } from '../main/ets/view/QuerySession';
import { QueryPageTab } from '../main/ets/common/QueryLogic';
import { ShuttleBusFetching, ShuttleBusSnapshot } from '../main/ets/net/ShuttleBusClient';

class QueryGate {
  private releaseGate: () => void = () => {};
  readonly promise: Promise<void> = new Promise<void>((resolve) => { this.releaseGate = resolve; });
  release(): void { this.releaseGate(); }
}

class QueryShuttleClient implements ShuttleBusFetching {
  calls: number = 0;
  readonly started: QueryGate = new QueryGate();
  gate: QueryGate | null = null;
  readonly snapshot: ShuttleBusSnapshot;

  constructor(generatedAt: string) {
    this.snapshot = new ShuttleBusSnapshot(generatedAt, 'healthy', [], null);
  }

  async fetch(): Promise<ShuttleBusSnapshot> {
    this.calls++;
    this.started.release();
    if (this.gate !== null) { await this.gate.promise; }
    return this.snapshot;
  }
}

export default function querySessionTest() {
  describe('QuerySessionTest', () => {
    it('keeps_lightweight_filter_and_selected_tab_state_in_memory', 0, () => {
      const session: QuerySession = new QuerySession();
      session.selectedTabRawValue = QueryPageTab.events;
      session.searchText = 'synthetic-search';
      session.eventCategory = 'competition';
      session.showEndedEvents = true;
      session.regularScrollOffsets.set(QueryPageTab.shuttle, 120);
      expect(session.selectedTabRawValue).assertEqual(QueryPageTab.events);
      expect(session.searchText).assertEqual('synthetic-search');
      expect(session.eventCategory).assertEqual('competition');
      expect(session.showEndedEvents).assertTrue();
      expect(session.regularScrollOffsets.get(QueryPageTab.shuttle)).assertEqual(120);
    });

    it('shares_one_inflight_fetch_uses_five_minute_cache_and_force_reload', 0, async () => {
      const session: QuerySession = new QuerySession();
      const client: QueryShuttleClient = new QueryShuttleClient('2026-10-03T12:00:00+08:00');
      const gate: QueryGate = new QueryGate();
      client.gate = gate;
      const first: Promise<void> = session.loadShuttle(client, false);
      const second: Promise<void> = session.loadShuttle(client, false);
      await client.started.promise;
      expect(client.calls).assertEqual(1);
      expect(session.shuttleLoading).assertTrue();
      gate.release();
      await first;
      await second;
      expect(session.shuttleSnapshot === client.snapshot).assertTrue();
      expect(session.shuttleLoading).assertFalse();
      expect(session.hasFreshShuttle(session.shuttleFetchedAtMillis + QuerySession.shuttleCacheLifetimeMs - 1))
        .assertTrue();
      expect(session.hasFreshShuttle(session.shuttleFetchedAtMillis + QuerySession.shuttleCacheLifetimeMs))
        .assertFalse();
      await session.loadShuttle(client, false);
      expect(client.calls).assertEqual(1);
      await session.loadShuttle(client, false, true);
      expect(client.calls).assertEqual(2);
    });

    it('sample_and_live_snapshots_never_cross_the_scope_boundary', 0, async () => {
      const session: QuerySession = new QuerySession();
      const sample: QueryShuttleClient = new QueryShuttleClient('sample');
      const live: QueryShuttleClient = new QueryShuttleClient('live');
      const gate: QueryGate = new QueryGate();
      sample.gate = gate;
      const oldRequest: Promise<void> = session.loadShuttle(sample, true);
      await sample.started.promise;
      const liveRequest: Promise<void> = session.loadShuttle(live, false);
      await liveRequest;
      expect(session.shuttleSnapshot === live.snapshot).assertTrue();
      gate.release();
      await oldRequest;
      expect(session.shuttleSnapshot === live.snapshot).assertTrue();
      expect(session.shuttleLoading).assertFalse();
    });

    it('detaching_the_view_suspends_only_watchdog_not_the_shared_fetch', 0, async () => {
      const session: QuerySession = new QuerySession();
      const client: QueryShuttleClient = new QueryShuttleClient('2026-10-03T12:00:00+08:00');
      const gate: QueryGate = new QueryGate();
      client.gate = gate;
      session.attachView();
      const inFlight: Promise<void> = session.loadShuttle(client, false);
      await client.started.promise;
      session.detachView();
      session.attachView();
      const sameFlight: Promise<void> = session.loadShuttle(client, false);
      expect(client.calls).assertEqual(1);
      gate.release();
      await inFlight;
      await sameFlight;
      expect(session.shuttleSnapshot === client.snapshot).assertTrue();
      expect(session.shuttleLoading).assertFalse();
      session.detachView();
      session.dispose();
    });

    it('disposing_root_invalidates_a_late_response', 0, async () => {
      const session: QuerySession = new QuerySession();
      const client: QueryShuttleClient = new QueryShuttleClient('2026-10-03T12:00:00+08:00');
      const gate: QueryGate = new QueryGate();
      client.gate = gate;
      session.attachView();
      const pending: Promise<void> = session.loadShuttle(client, false);
      await client.started.promise;
      session.dispose();
      gate.release();
      await pending;
      expect(session.shuttleSnapshot === null).assertTrue();
      expect(session.shuttleLoading).assertFalse();
    });
  });
}
