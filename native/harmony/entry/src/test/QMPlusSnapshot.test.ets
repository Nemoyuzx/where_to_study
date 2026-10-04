// 纯合成快照，不含个人账户、Cookie 或 QMplus 页面正文。
import { describe, it, expect } from '@ohos/hypium';
import { QMPlusSnapshotParser, QMPlusURLPolicy } from '../main/ets/net/QMPlusSnapshot';
import { QMPlusSession } from '../main/ets/view/QMPlusSession';

function syntheticSnapshot(): string {
  return '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-03T10:00:00.000Z",' +
    '"ok":true,"partial":false,"courses":[{"id":"7","name":"Synthetic Course",' +
    '"short_name":"SC","url":"https://qmplus.qmul.ac.uk/course/view.php?id=7",' +
    '"start_at":null,"end_at":null,"current_term_status":"current"}],' +
    '"activities":[{"id":"8","course_id":"7","title":"Synthetic assignment",' +
    '"kind":"assignment","url":"https://qmplus.qmul.ac.uk/mod/assign/view.php?id=8",' +
    '"due_at":"2026-10-10T12:00:00.000Z","opens_at":null,"closes_at":null,' +
    '"cutoff_at":null,"time_limit_seconds":null,"status":"unknown",' +
    '"detail_status":"available","raw_time_text":""}],"warnings":[]}';
}

export default function qmPlusSnapshotTest() {
  describe('QMPlusSnapshotTest', () => {
    it('official_origin_and_course_paths_are_required_before_any_script_runs', 0, () => {
      expect(QMPlusURLPolicy.isBusinessPage('https://qmplus.qmul.ac.uk/my/')).assertTrue();
      expect(QMPlusURLPolicy.isBusinessPage('https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=8')).assertTrue();
      expect(QMPlusURLPolicy.isBusinessPage('https://login.microsoftonline.com/common/')).assertFalse();
      expect(QMPlusURLPolicy.isBusinessPage('http://qmplus.qmul.ac.uk/my/')).assertFalse();
      expect(QMPlusURLPolicy.isBusinessPage('https://qmplus.qmul.ac.uk.evil.test/my/')).assertFalse();
      expect(QMPlusURLPolicy.isHTTPSPage('msauth://callback')).assertFalse();
      expect(QMPlusURLPolicy.isHTTPSPage('https://login.microsoftonline.com/common/')).assertTrue();
    });

    it('accepts_only_bounded_schema_one_snapshot_and_verified_official_links', 0, () => {
      const snapshot = QMPlusSnapshotParser.parse(syntheticSnapshot());
      expect(snapshot.courses.length).assertEqual(1);
      expect(snapshot.activities.length).assertEqual(1);
      expect(snapshot.activities[0].dueAt).assertEqual('2026-10-10T12:00:00.000Z');
      expect(snapshot.activities[0].timeLimitSeconds).assertNull();
      expect(QMPlusURLPolicy.isActivityURL(snapshot.activities[0].url, 'assignment')).assertTrue();
      expect(QMPlusURLPolicy.isActivityURL(snapshot.activities[0].url, 'quiz')).assertFalse();
    });

    it('rejects_cross_origin_wrong_schema_and_oversized_results', 0, () => {
      let rejected: number = 0;
      for (const raw of [
        syntheticSnapshot().replace('"source":"qmplus"', '"source":"other"'),
        syntheticSnapshot().replace('qmplus.qmul.ac.uk/mod/assign', 'evil.test/mod/assign'),
        syntheticSnapshot().replace('2026-10-10T12:00:00.000Z', '2026-10-10T12:00:00+02:00'),
        syntheticSnapshot().replace('"warnings":[]', '"warnings":[],"sesskey":"never-cross-bridge"'),
        ' '.repeat(QMPlusSnapshotParser.maximumBytes + 1)
      ]) {
        try { QMPlusSnapshotParser.parse(raw); } catch (e) { rejected++; }
      }
      expect(rejected).assertEqual(5);
    });

    it('close_and_logout_generation_reject_late_web_callbacks_without_erasing_last_good_on_error', 0, () => {
      const session: QMPlusSession = new QMPlusSession();
      session.openLogin();
      const first: number = session.beginSync();
      session.closeLogin();
      session.completeSync(first, syntheticSnapshot());
      expect(session.snapshot).assertNull();
      session.openLogin();
      const second: number = session.beginSync();
      session.completeSync(second, syntheticSnapshot());
      expect(session.snapshot?.activities.length).assertEqual(1);
      const failed: number = session.beginSync();
      session.completeSync(failed, '{broken');
      expect(session.snapshot?.activities.length).assertEqual(1);
      expect(session.error.length > 0).assertTrue();
      // No Web was opened in this pure unit case; logout clears the in-memory snapshot.
      expect(session.logout()).assertTrue();
      expect(session.snapshot).assertNull();
      session.completeSync(second, syntheticSnapshot());
      expect(session.snapshot).assertNull();
    });

    it('partial_sync_preserves_prior_complete_snapshot_and_its_timestamp', 0, () => {
      const session: QMPlusSession = new QMPlusSession();
      session.openLogin();
      const first: number = session.beginSync();
      session.completeSync(first, syntheticSnapshot());
      expect(session.snapshot?.activities.length).assertEqual(1);
      const partial: Record<string, Object> = JSON.parse(syntheticSnapshot()) as Record<string, Object>;
      partial['partial'] = true;
      const noActivities: Object[] = [];
      const warnings: string[] = ['QM_DETAIL_PARTIAL'];
      partial['activities'] = noActivities;
      partial['warnings'] = warnings;
      const second: number = session.beginSync();
      session.completeSync(second, JSON.stringify(partial));
      expect(session.snapshot?.partial).assertFalse();
      expect(session.snapshot?.activities.length).assertEqual(1);
      expect(session.snapshot?.fetchedAt).assertEqual('2026-10-03T10:00:00.000Z');
      expect(session.showingStalePartial).assertTrue();
      session.logout();
      expect(session.showingStalePartial).assertFalse();
      const firstConnect: QMPlusSession = new QMPlusSession();
      firstConnect.openLogin();
      firstConnect.completeSync(firstConnect.beginSync(), JSON.stringify(partial));
      expect(firstConnect.snapshot?.partial).assertTrue();
      expect(firstConnect.snapshot?.activities.length).assertEqual(0);
      expect(firstConnect.showingStalePartial).assertFalse();
    });
  });
}
