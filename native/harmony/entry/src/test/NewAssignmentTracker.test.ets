import { describe, it, expect } from '@ohos/hypium';
import { NewAssignmentTracker } from '../main/ets/common/NewAssignmentTracker';

export default function newAssignmentTrackerTest() {
  describe('NewAssignmentTracker', () => {
    it('baseline_refresh_restart_and_reappearance', 0, () => {
      const tracker: NewAssignmentTracker = new NewAssignmentTracker();
      expect(tracker.accept(['course|old'], true).length).assertEqual(0);
      expect(tracker.accept(['course|old', 'course|new'], true).join(',')).assertEqual('course|new');
      expect(tracker.accept([], true).length).assertEqual(0);
      const restarted: NewAssignmentTracker = new NewAssignmentTracker();
      restarted.restore(tracker.serialize());
      expect(restarted.accept(['course|new', 'course|old'], true).length).assertEqual(0);
      expect(restarted.accept(['course|later'], true).join(',')).assertEqual('course|later');
    });
    it('partial_never_establishes_baseline_and_cache_is_silent', 0, () => {
      const tracker: NewAssignmentTracker = new NewAssignmentTracker();
      expect(tracker.accept(['partial'], false).length).assertEqual(0);
      expect(tracker.serialize()).assertEqual('');
      expect(tracker.accept(['cached'], true, true).length).assertEqual(0);
      const before: string = tracker.serialize();
      expect(tracker.accept(['cached', 'fresh'], false).length).assertEqual(0);
      expect(tracker.serialize()).assertEqual(before);
      expect(tracker.accept(['fresh'], true).join(',')).assertEqual('fresh');
    });
    it('bounded_history_saturates_without_eviction', 0, () => {
      const tracker: NewAssignmentTracker = new NewAssignmentTracker();
      const ids: string[] = [];
      for (let i: number = 0; i < NewAssignmentTracker.limit; i++) { ids.push('id-' + i); }
      tracker.accept(ids, true);
      expect(tracker.accept(['overflow'], true).length).assertEqual(0);
      expect(tracker.accept(['id-0'], true).length).assertEqual(0);
      const restarted: NewAssignmentTracker = new NewAssignmentTracker();
      restarted.restore(tracker.serialize());
      expect(restarted.accept(['another'], true).length).assertEqual(0);
    });
  });
}
