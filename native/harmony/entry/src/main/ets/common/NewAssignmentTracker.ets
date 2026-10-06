// IDs remain remembered when an assignment disappears. At the bound, stop
// detecting for this scope rather than evicting IDs and re-alerting old work.
export class NewAssignmentTracker {
  static readonly limit: number = 4096;
  private seen: Set<string> = new Set<string>();
  private baseline: boolean = false;
  private saturated: boolean = false;

  restore(raw: string | null): void {
    if (raw === null || raw.length > 1024 * 1024) { return; }
    try {
      const values: Object[] = JSON.parse(raw) as Object[];
      if (!Array.isArray(values) || values.length > NewAssignmentTracker.limit + 1 || values[0] !== 'v1') { return; }
      const ids: string[] = [];
      for (let i: number = 1; i < values.length; i++) {
        if (typeof values[i] !== 'string' || (values[i] as string).length > 128) { return; }
        ids.push(values[i] as string);
      }
      this.seen = new Set<string>(ids);
      this.baseline = true;
      this.saturated = this.seen.size >= NewAssignmentTracker.limit;
    } catch (e) {}
  }

  accept(ids: string[], complete: boolean, cached: boolean = false): string[] {
    if (!complete) { return []; }
    const added: string[] = [];
    const notify: boolean = this.baseline && !cached && !this.saturated;
    for (const id of ids) {
      if (id.length === 0 || id.length > 128 || this.seen.has(id)) { continue; }
      if (this.seen.size >= NewAssignmentTracker.limit) { this.saturated = true; break; }
      this.seen.add(id);
      if (notify) { added.push(id); }
    }
    if (complete) { this.baseline = true; }
    return added;
  }

  serialize(): string { return this.baseline ? JSON.stringify(['v1', ...Array.from(this.seen)]) : ''; }
}
