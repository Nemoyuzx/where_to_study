// A dialog owns only a small immutable projection; full tasks stay in the
// course owners. Tracker publications contain disjoint newly seen identities.
export class NewAssignmentNotice {
  static readonly previewLimit: number = 8;
  readonly source: string;
  readonly identity: string;
  readonly term: string;
  readonly count: number;
  readonly preview: string[];

  constructor(source: string, identity: string, term: string, count: number, preview: string[]) {
    this.source = source;
    this.identity = identity;
    this.term = term;
    this.count = Math.max(0, Math.floor(count));
    this.preview = preview.slice(0, NewAssignmentNotice.previewLimit);
  }

  static merge(previous: NewAssignmentNotice | null, incoming: NewAssignmentNotice): NewAssignmentNotice {
    if (previous === null || previous.source !== incoming.source || previous.identity !== incoming.identity ||
      previous.term !== incoming.term) { return incoming; }
    return new NewAssignmentNotice(incoming.source, incoming.identity, incoming.term,
      previous.count + incoming.count, previous.preview.concat(incoming.preview));
  }

  message(title: string): string {
    const remaining: number = Math.max(0, this.count - this.preview.length);
    return title + ': ' + this.count.toString() + '\n\n' + this.preview.join('\n\n') +
      (remaining > 0 ? '\n\n+' + remaining.toString() : '');
  }
}

export class NewAssignmentNoticeTicket {
  readonly id: number;
  readonly notice: NewAssignmentNotice;
  constructor(id: number, notice: NewAssignmentNotice) { this.id = id; this.notice = notice; }
}

export class NewAssignmentNoticeQueue {
  private active: NewAssignmentNoticeTicket | null = null;
  private readonly pending: Map<string, NewAssignmentNotice> = new Map<string, NewAssignmentNotice>();
  private nextID: number = 0;

  enqueue(notice: NewAssignmentNotice): void {
    if (!['ucloud', 'qmplus'].includes(notice.source) || notice.count <= 0) { return; }
    this.pending.set(notice.source, NewAssignmentNotice.merge(this.pending.get(notice.source) ?? null, notice));
  }

  begin(): NewAssignmentNoticeTicket | null {
    if (this.active !== null || this.pending.size === 0) { return null; }
    const source: string = Array.from(this.pending.keys())[0];
    const notice: NewAssignmentNotice | undefined = this.pending.get(source);
    this.pending.delete(source);
    if (notice === undefined) { return null; }
    this.active = new NewAssignmentNoticeTicket(++this.nextID, notice);
    return this.active;
  }

  finish(id: number): boolean {
    if (this.active?.id !== id) { return false; }
    this.active = null;
    return true;
  }

  retire(source: string): void {
    this.pending.delete(source);
    // An already visible alert remains immutable until dismissed; this keeps
    // a new identity's alert from opening on top of the old one.
  }

  clear(): void { this.pending.clear(); this.active = null; }
  size(): number { return this.pending.size + (this.active === null ? 0 : 1); }
  unconfirmedCount(): number {
    let count: number = this.active?.notice.count ?? 0;
    this.pending.forEach((notice: NewAssignmentNotice): void => { count += notice.count; });
    return count;
  }
}
