import { NewAssignmentTracker } from '../common/NewAssignmentTracker';
import { JsonFile } from './JsonFile';
import { AppContext } from './AppContext';
import { JsonUtil } from '../common/JsonUtil';

class SeenAssignmentScope {
  readonly key: string;
  readonly seen: string;
  constructor(key: string, seen: string) { this.key = key; this.seen = seen; }
}

export class NewAssignmentStore {
  private queue: Promise<void> = Promise.resolve();
  private trackers: Map<string, NewAssignmentTracker> = new Map<string, NewAssignmentTracker>();
  private loaded: boolean = false;
  private epoch: number = 0;
  private path(): string { return AppContext.get().filesDir + '/cache/new-assignments-' + this.source + '.json'; }
  private readonly source: string;
  constructor(source: string) { this.source = source; }

  accept(scope: string, term: string, ids: string[], complete: boolean, cached: boolean,
    current: () => boolean, notify: (ids: string[]) => void): Promise<void> {
    const epoch: number = this.epoch;
    const valid: () => boolean = (): boolean => epoch === this.epoch && current();
    const work: Promise<void> = this.queue.catch(() => {}).then(async (): Promise<void> => {
      if (!/^[0-9a-f]{32}$/.test(scope) || !/^\d{4}-\d{4}-[12]$/.test(term) || !valid()) { return; }
      const key: string = scope + '|' + term;
      if (!this.loaded) {
        try {
          const raw: string | null = await JsonFile.readText(this.path(), 8 * 1024 * 1024);
          if (!valid()) { return; }
          if (raw !== null) {
            const rows: Object[] = JSON.parse(raw) as Object[];
            if (!Array.isArray(rows) || rows.length > 8) { return; }
            for (const value of rows) {
              const row: Record<string, Object> | null = JsonUtil.record(value);
              if (row === null || typeof row['key'] !== 'string' || typeof row['seen'] !== 'string') { return; }
              const restoredKey: string = row['key'] as string;
              if (!/^[0-9a-f]{32}\|\d{4}-\d{4}-[12]$/.test(restoredKey)) { return; }
              const restored: NewAssignmentTracker = new NewAssignmentTracker();
              restored.restore(row['seen'] as string);
              this.trackers.set(restoredKey, restored);
            }
          }
          this.loaded = true;
        } catch (e) { return; }
      }
      let tracker: NewAssignmentTracker | undefined = this.trackers.get(key);
      if (tracker === undefined) {
        // At most eight semester bindings; older removed bindings become a
        // silent first baseline when revisited, never a burst of historical work.
        if (this.trackers.size >= 8) { this.trackers.delete(Array.from(this.trackers.keys())[0]); }
        tracker = new NewAssignmentTracker();
        this.trackers.set(key, tracker);
      }
      const added: string[] = tracker.accept(ids, complete, cached);
      if (!valid()) { return; }
      const serialized: string = tracker.serialize();
      if (serialized.length > 0) {
        const rows: SeenAssignmentScope[] = [];
        this.trackers.forEach((value: NewAssignmentTracker, binding: string): void => {
          if (value.serialize().length > 0) { rows.push(new SeenAssignmentScope(binding, value.serialize())); }
        });
        await JsonFile.writeTextAtomic(this.path(), JSON.stringify(rows));
      }
      if (valid() && added.length > 0) { notify(added); }
    });
    this.queue = work;
    return work;
  }

  clear(): void {
    this.epoch++;
    this.trackers.clear();
    this.loaded = true;
    this.queue = this.queue.catch(() => {}).then(async (): Promise<void> => { await JsonFile.removeFile(this.path()); });
  }
}
