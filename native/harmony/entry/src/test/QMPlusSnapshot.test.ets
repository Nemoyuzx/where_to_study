// 纯合成快照，不含个人账户、Cookie 或 QMplus 页面正文。
import { describe, it, expect } from '@ohos/hypium';
import { QMPlusSnapshotParser, QMPlusURLPolicy, QMPlusCourseworkPolicy, QMPlusActivity,
  QMPlusCourse, QMPlusSnapshot } from '../main/ets/net/QMPlusSnapshot';
import { CourseQMPlusScope } from '../main/ets/common/CourseLogic';
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

function syntheticCourseworkSnapshot(title: string, kind: string = 'assignment'): string {
  const root: Record<string, Object> = JSON.parse(syntheticSnapshot()) as Record<string, Object>;
  const activities: Object[] = root['activities'] as Object[];
  const item: Record<string, Object> = activities[0] as Record<string, Object>;
  item['title'] = title;
  item['kind'] = kind;
  item['url'] = 'https://qmplus.qmul.ac.uk/mod/' + (kind === 'quiz' ? 'quiz' : 'assign') + '/view.php?id=8';
  return JSON.stringify(root).replace('"due_at":"2026-10-10T12:00:00.000Z"', '"due_at":null');
}

function courseworkItem(id: string, title: string, kind: string = 'assignment'): QMPlusActivity {
  return new QMPlusActivity(id, '7', title, kind,
    'https://qmplus.qmul.ac.uk/mod/' + (kind === 'quiz' ? 'quiz' : 'assign') + '/view.php?id=' + id,
    null, null, null, null, null, 'unknown', 'available', '');
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

    it('binds_each_official_link_to_its_record_id_and_rejects_reused_module_ids_across_kinds', 0, () => {
      const wrongCourseURL: string = syntheticSnapshot().replace('/course/view.php?id=7',
        '/course/view.php?id=9');
      const wrongActivityURL: string = syntheticSnapshot().replace('/mod/assign/view.php?id=8',
        '/mod/assign/view.php?id=9');
      const duplicated: Record<string, Object> = JSON.parse(syntheticSnapshot()) as Record<string, Object>;
      const activities: Object[] = duplicated['activities'] as Object[];
      const second: Record<string, Object> = JSON.parse(JSON.stringify(activities[0])) as Record<string, Object>;
      second['kind'] = 'quiz';
      second['url'] = 'https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=8';
      activities.push(second);
      let rejected: number = 0;
      for (const raw of [wrongCourseURL, wrongActivityURL, JSON.stringify(duplicated)]) {
        try { QMPlusSnapshotParser.parse(raw); } catch (e) { rejected++; }
      }
      expect(rejected).assertEqual(3);
    });

    it('close_and_logout_generation_reject_late_web_callbacks_without_erasing_last_good_on_error', 0, () => {
      QMPlusSession.resetOwnedWebLoadedForTesting();
      const session: QMPlusSession = new QMPlusSession((): void => {});
      session.openLogin();
      const first: number = session.beginSync();
      session.closeLogin();
      session.completeSync(first, syntheticSnapshot());
      expect(session.snapshot).assertNull();
      session.openLogin();
      const second: number = session.beginSync();
      session.completeSync(second, syntheticSnapshot());
      expect(session.snapshot?.activities.length).assertEqual(1);
      // A validated sync now closes its owner. A later refresh is a new explicit connection.
      session.openLogin();
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

    it('incognito_logout_skips_uninitialized_web_but_clears_after_root_session_recreation', 0, () => {
      QMPlusSession.resetOwnedWebLoadedForTesting();
      let clearCalls: number = 0;
      try {
        const firstStartup: QMPlusSession = new QMPlusSession((): void => { clearCalls++; });
        expect(firstStartup.logout()).assertTrue();
        expect(clearCalls).assertEqual(0);

        const loaded: QMPlusSession = new QMPlusSession((): void => { clearCalls++; });
        loaded.noteWebLoaded(); // 模拟真实 Web onPageBegin；不启动引擎或读取 Cookie。
        const recreatedRoot: QMPlusSession = new QMPlusSession((): void => { clearCalls++; });
        expect(recreatedRoot.logout()).assertTrue();
        expect(clearCalls).assertEqual(1);

        const failedClear: QMPlusSession = new QMPlusSession((): void => {
          throw new Error('synthetic-url?sesskey=private');
        });
        failedClear.openLogin();
        const pending: number = failedClear.beginSync();
        failedClear.completeSync(pending, syntheticSnapshot());
        expect(failedClear.logout()).assertFalse();
        expect(failedClear.snapshot).assertNull();
        expect(failedClear.error).assertEqual('QMplus 浏览器会话未能清除，请稍后重试。');
        failedClear.completeSync(pending, syntheticSnapshot());
        expect(failedClear.snapshot).assertNull();
        expect(new QMPlusSession((): void => { clearCalls++; }).logout()).assertTrue();
        expect(clearCalls).assertEqual(2);
      } finally {
        QMPlusSession.resetOwnedWebLoadedForTesting();
      }
    });

    it('web_failures_never_publish_raw_urls_or_session_markers_to_the_ui', 0, () => {
      QMPlusSession.resetOwnedWebLoadedForTesting();
      const session: QMPlusSession = new QMPlusSession((): void => {});
      session.openLogin();
      const first: number = session.beginSync();
      session.failSync(first, 'https://qmplus.qmul.ac.uk/lib/ajax/service.php?sesskey=synthetic-secret');
      expect(session.error).assertEqual('QMplus 同步失败。');
      // Pausing now emits this fixed local continuation reason, never the upstream URL.
      expect(session.errorCode).assertEqual('QM_LOGIN_REQUIRED');
      expect((session.error + session.errorCode).includes('sesskey')).assertFalse();
      expect((session.error + session.errorCode).includes('synthetic-secret')).assertFalse();
      const second: number = session.beginSync();
      session.failSync(second, 'QMplus 同步已超时，请稍后重试。');
      expect(session.error).assertEqual('QMplus 同步已超时，请稍后重试。');
      const third: number = session.beginSync();
      session.completeSync(third, '{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-03T10:00:00.000Z",' +
        '"ok":false,"partial":false,"courses":[],"activities":[],"warnings":[],' +
        '"error_code":"SYNTHETIC_SESSION_MARKER"}');
      expect(session.error).assertEqual('QMplus 同步失败。');
      expect(session.errorCode).assertEqual('');
    });

    it('partial_sync_preserves_prior_complete_snapshot_and_its_timestamp', 0, () => {
      QMPlusSession.resetOwnedWebLoadedForTesting();
      const session: QMPlusSession = new QMPlusSession((): void => {});
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
      session.openLogin();
      const second: number = session.beginSync();
      session.completeSync(second, JSON.stringify(partial));
      expect(session.snapshot?.partial).assertFalse();
      expect(session.snapshot?.activities.length).assertEqual(1);
      expect(session.snapshot?.fetchedAt).assertEqual('2026-10-03T10:00:00.000Z');
      expect(session.showingStalePartial).assertTrue();
      session.logout();
      expect(session.showingStalePartial).assertFalse();
      const firstConnect: QMPlusSession = new QMPlusSession((): void => {});
      firstConnect.openLogin();
      firstConnect.completeSync(firstConnect.beginSync(), JSON.stringify(partial));
      expect(firstConnect.snapshot?.partial).assertTrue();
      expect(firstConnect.snapshot?.activities.length).assertEqual(0);
      expect(firstConnect.showingStalePartial).assertFalse();
    });

    it('only_exact_mark_review_assignment_titles_are_administrative_with_conservative_normalization', 0, () => {
      for (const title of ['COURSEWORK MARK REVIEW REQUEST', ' coursework\tmark  review\nrequest ',
        'Coursework-Mark/Review_Request:Form', 'COURSEWORK\u0085MARK\u202FREVIEW\u00A0REQUEST',
        'COURSEWORK\u2010MARK\u2011REVIEW\u2012REQUEST\u2015FORM', 'COURSEWORK\u2212MARK REVIEW REQUEST',
        '\uFEFFＣＯＵＲＳＥＷＯＲＫ　ＭＡＲＫ　ＲＥＶＩＥＷ　ＲＥＱＵＥＳＴ　ＦＯＲＭ\uFEFF']) {
        expect(QMPlusCourseworkPolicy.isMarkReviewRequest('assignment', title)).assertTrue();
        expect(QMPlusCourseworkPolicy.isMarkReviewRequest('quiz', title)).assertFalse();
      }
      for (const title of ['Essay: Coursework Mark Review Request', 'Coursework Mark Review Request Essay',
        'Coursework Mark Review Request Formative Essay', 'Coursework Mark Review Requests',
        'Coursework Mark Review', 'Peer review assignment', 'Feedback report',
        'Coursework Mark Review Request (Form)', 'Coursework.Mark.Review.Request']) {
        expect(QMPlusCourseworkPolicy.isMarkReviewRequest('assignment', title)).assertFalse();
      }
    });

    it('validated_snapshot_filters_only_administrative_assignments_and_keeps_real_undated_work_and_same_named_quiz', 0, () => {
      const title: string = 'COURSEWORK MARK REVIEW REQUEST';
      expect(QMPlusSnapshotParser.parse(syntheticCourseworkSnapshot(title)).activities.length).assertEqual(0);
      const undated: QMPlusSnapshot = QMPlusSnapshotParser.parse(syntheticCourseworkSnapshot('Real undated assignment'));
      expect(undated.activities.length).assertEqual(1);
      expect(undated.activities[0].dueAt).assertNull();
      const quiz: QMPlusSnapshot = QMPlusSnapshotParser.parse(syntheticCourseworkSnapshot(title, 'quiz'));
      expect(quiz.activities.length).assertEqual(1);
      expect(quiz.activities[0].title).assertEqual(title);
    });

    it('legacy_display_counts_and_partial_retention_share_the_same_coursework_filter', 0, () => {
      const courses: QMPlusCourse[] = [new QMPlusCourse('7', 'EBU Synthetic', 'SC', null, null, null, 'current')];
      const real: QMPlusActivity = courseworkItem('11', 'Real undated assignment');
      const quiz: QMPlusActivity = courseworkItem('12', 'COURSEWORK MARK REVIEW REQUEST', 'quiz');
      const review: QMPlusActivity = courseworkItem('13', 'Coursework-Mark/Review_Request:Form');
      const warnings: string[] = [];
      const original: QMPlusSnapshot = new QMPlusSnapshot('2026-10-03T10:00:00.000Z', false,
        courses, [real, quiz, review], warnings);
      expect(original.activities.length).assertEqual(2);
      // Emulate a previously accepted cache made before the title exclusion;
      // the shared presentation scope also protects retained old snapshots.
      original.activities.push(review);
      const visible: QMPlusActivity[] = CourseQMPlusScope.currentActivities(original);
      expect(visible.length).assertEqual(2);
      expect(visible[0].id).assertEqual('11');
      expect(visible[1].id).assertEqual('12');
      expect(visible[0].dueAt).assertNull();
      const session: QMPlusSession = new QMPlusSession((): void => {});
      session.snapshot = original;
      session.openLogin();
      session.completeSync(session.beginSync(), syntheticCourseworkSnapshot('COURSEWORK MARK REVIEW REQUEST')
        .replace('"partial":false', '"partial":true'));
      expect(session.showingStalePartial).assertTrue();
      expect(session.snapshot?.fetchedAt).assertEqual(original.fetchedAt);
      expect(CourseQMPlusScope.currentActivities(session.snapshot).length).assertEqual(2);
      session.dispose();
    });

    it('an_excluded_title_cannot_skip_link_time_identity_duplicate_or_warning_validation', 0, () => {
      const valid: string = syntheticCourseworkSnapshot('COURSEWORK MARK REVIEW REQUEST');
      const duplicate: Record<string, Object> = JSON.parse(valid) as Record<string, Object>;
      const items: Object[] = duplicate['activities'] as Object[];
      items.push(JSON.parse(JSON.stringify(items[0])) as Object);
      let rejected: number = 0;
      for (const raw of [valid.replace('qmplus.qmul.ac.uk/mod/assign', 'evil.test/mod/assign'),
        valid.replace('"due_at":null', '"due_at":"invalid"'),
        valid.replace('"course_id":"7"', '"course_id":"999"'),
        valid.replace('"warnings":[]', '"warnings":["invalid-warning"]'), JSON.stringify(duplicate)]) {
        try { QMPlusSnapshotParser.parse(raw); } catch (e) { rejected++; }
      }
      expect(rejected).assertEqual(5);
    });
  });
}
