import { describe, it, expect } from '@ohos/hypium';
import { WidgetFileOperations, WidgetFileQueue } from '../main/ets/widget/WidgetFileQueue';

class DelayedWidgetFiles implements WidgetFileOperations {
  files: Map<string, string> = new Map<string, string>();
  started: Promise<void>;
  private didStart: () => void = () => {};
  private releaseWrite: () => void = () => {};
  private gate: Promise<void>;
  private first: boolean = true;
  constructor() {
    this.started = new Promise<void>((resolve) => { this.didStart = resolve; });
    this.gate = new Promise<void>((resolve) => { this.releaseWrite = resolve; });
  }
  resume(): void { this.releaseWrite(); }
  async write(path: string, text: string): Promise<void> {
    if (this.first) {
      this.first = false;
      this.didStart();
      await this.gate;
    }
    this.files.set(path, text);
  }
  async remove(path: string): Promise<void> { this.files.delete(path); }
}

export default function widgetFileQueueTest() {
  describe('WidgetFileQueueTest', () => {
    it('clear_waits_for_slow_write_and_removes_canonical_and_legacy_private_data', 0, async () => {
      const files = new DelayedWidgetFiles();
      files.files.set('obsolete', 'previous-account');
      const queue = new WidgetFileQueue(files);
      const old = queue.replace('current', 'obsolete', 'old-account');
      await files.started;
      const clear = queue.replace('current', 'obsolete', null);
      files.resume();
      expect(await old).assertFalse();
      expect(await clear).assertTrue();
      expect(files.files.has('current')).assertFalse();
      expect(files.files.has('obsolete')).assertFalse();
    });

    it('latest_account_wins_over_waiting_clear_and_stale_write', 0, async () => {
      const files = new DelayedWidgetFiles();
      const queue = new WidgetFileQueue(files);
      const old = queue.replace('current', 'obsolete', 'old-account');
      await files.started;
      const clear = queue.replace('current', 'obsolete', null);
      const latest = queue.replace('current', 'obsolete', 'current-account');
      files.resume();
      expect(await old).assertFalse();
      expect(await clear).assertFalse();
      expect(await latest).assertTrue();
      expect(files.files.get('current')).assertEqual('current-account');
    });
  });
}
