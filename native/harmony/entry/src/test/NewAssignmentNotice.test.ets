import { describe, it, expect } from '@ohos/hypium';
import { NewAssignmentNotice, NewAssignmentNoticeQueue } from '../main/ets/common/NewAssignmentNotice';

function batch(source: string, count: number, identity: string = 'synthetic', term: string = '2026-2027-1'): NewAssignmentNotice {
  return new NewAssignmentNotice(source, identity, term, count, ['Synthetic title\nSynthetic course\n2026-10-06']);
}

export default function newAssignmentNoticeTest() {
  describe('NewAssignmentNotice', () => {
    it('large_result_keeps_eight_previews_and_exact_total_and_remaining', 0, () => {
      const titles: string[] = [];
      for (let i: number = 0; i < 5000; i++) { titles.push('Synthetic ' + i.toString()); }
      const notice: NewAssignmentNotice = new NewAssignmentNotice('ucloud', 'owner', 'term', 5000, titles);
      expect(notice.preview.length).assertEqual(8);
      expect(notice.count).assertEqual(5000);
      expect(notice.message('New assignments').includes('+4992')).assertTrue();
      expect(notice.message('New assignments').includes('Synthetic 8')).assertFalse();
    });

    it('one_active_and_two_source_pending_batches_keep_all_unconfirmed_counts', 0, () => {
      const queue: NewAssignmentNoticeQueue = new NewAssignmentNoticeQueue();
      queue.enqueue(batch('ucloud', 7));
      const active = queue.begin();
      expect(active !== null).assertTrue();
      for (let i: number = 0; i < 1000; i++) {
        queue.enqueue(batch('ucloud', 2));
        queue.enqueue(batch('qmplus', 3));
        expect(queue.size() <= 3).assertTrue();
      }
      expect(queue.unconfirmedCount()).assertEqual(5007);
      expect(active!.notice.count).assertEqual(7);
      expect(queue.begin() === null).assertTrue();
      expect(queue.finish(active!.id)).assertTrue();
      const cloud = queue.begin();
      expect(cloud!.notice.count).assertEqual(2000);
      expect(cloud!.notice.preview.length).assertEqual(8);
      queue.finish(cloud!.id);
      const qm = queue.begin();
      expect(qm!.notice.count).assertEqual(3000);
      queue.finish(qm!.id);
      expect(queue.unconfirmedCount()).assertEqual(0);
    });

    it('retirement_preserves_other_source_and_never_merges_old_identity_or_term', 0, () => {
      const queue: NewAssignmentNoticeQueue = new NewAssignmentNoticeQueue();
      queue.enqueue(batch('ucloud', 1, 'old'));
      const old = queue.begin();
      queue.enqueue(batch('ucloud', 10, 'old'));
      queue.enqueue(batch('qmplus', 20, 'independent'));
      queue.retire('ucloud');
      queue.enqueue(batch('ucloud', 30, 'new'));
      expect(old!.notice.count).assertEqual(1);
      expect(queue.unconfirmedCount()).assertEqual(51);
      queue.finish(old!.id);
      const qm = queue.begin();
      expect(qm!.notice.source).assertEqual('qmplus');
      expect(qm!.notice.count).assertEqual(20);
      queue.finish(qm!.id);
      const fresh = queue.begin();
      expect(fresh!.notice.identity).assertEqual('new');
      expect(fresh!.notice.count).assertEqual(30);
      expect(NewAssignmentNotice.merge(batch('ucloud', 8, 'old'), batch('ucloud', 2, 'new')).count).assertEqual(2);
      expect(NewAssignmentNotice.merge(batch('ucloud', 8), batch('ucloud', 2, 'synthetic', 'next-term')).count).assertEqual(2);
    });

    it('late_finish_after_clear_cannot_acknowledge_a_new_dialog', 0, () => {
      const queue: NewAssignmentNoticeQueue = new NewAssignmentNoticeQueue();
      queue.enqueue(batch('ucloud', 4));
      const old = queue.begin();
      queue.clear();
      queue.enqueue(batch('qmplus', 9));
      const fresh = queue.begin();
      expect(queue.finish(old!.id)).assertFalse();
      expect(queue.unconfirmedCount()).assertEqual(9);
      expect(queue.begin() === null).assertTrue();
      expect(queue.finish(fresh!.id)).assertTrue();
      expect(queue.unconfirmedCount()).assertEqual(0);
    });
  });
}
