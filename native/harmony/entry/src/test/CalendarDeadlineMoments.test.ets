import { describe, it, expect } from '@ohos/hypium';
import { CalendarCourseworkItem, CalendarCourseworkProjection, CalendarDeadlineMoments } from '../main/ets/view/calendar/CalendarCourseworkProjection';
import { QMPlusActivity, QMPlusCourse, QMPlusSnapshot } from '../main/ets/net/QMPlusSnapshot';
import { AssignmentDeadlineItem } from '../main/ets/net/CalendarDailyInfoClient';
import { UCloudCourse } from '../main/ets/net/UCloudAssignmentClient';

function deadline(id: string, value: string): CalendarCourseworkItem {
  return new CalendarCourseworkItem(id, 'Synthetic task', value, 'ucloud', 'course');
}

export default function calendarDeadlineMomentsTest() {
  describe('CalendarDeadlineMoments', () => {
    it('pending_dot_uses_existing_submission_evidence_and_never_guesses_quiz', 0, () => {
      for (const status of ['未提交', 'not submitted', 'nothing submitted']) {
        const item = CalendarCourseworkProjection.cloud(new AssignmentDeadlineItem('task', 'Synthetic',
          null, '2026-10-06 12:00', status), []);
        expect(CalendarDeadlineMoments.showsPending([item])).assertTrue();
      }
      for (const status of ['已提交', 'submitted for grading', 'unknown', '']) {
        const item = CalendarCourseworkProjection.cloud(new AssignmentDeadlineItem('task', 'Synthetic',
          null, '2026-10-06 12:00', status), []);
        expect(CalendarDeadlineMoments.showsPending([item])).assertFalse();
      }
      const course = new QMPlusCourse('course', 'EBU0001 Synthetic', '', null, null, null, 'current');
      const assignment = new QMPlusActivity('1', 'course', 'Synthetic assignment', 'assignment', '',
        '2026-10-06T04:00:00.000Z', null, null, null, null, 'not submitted', 'ok', '');
      const quiz = new QMPlusActivity('2', 'course', 'Synthetic quiz', 'quiz', '',
        null, null, '2026-10-06T04:00:00.000Z', null, null, 'not submitted', 'ok', '');
      const snapshot = new QMPlusSnapshot('2026-10-06T00:00:00Z', false, [course], [assignment, quiz], []);
      const projected = CalendarCourseworkProjection.qm('2026-10-06', snapshot);
      expect(projected.length).assertEqual(2);
      expect(projected[0].pending).assertTrue();
      expect(projected[1].pending).assertFalse();
      expect(CalendarDeadlineMoments.showsPending([projected[1]])).assertFalse();
    });
    it('theme_strip_spans_each_unchanged_day_column_with_four_point_insets', 0, () => {
      expect(CalendarDeadlineMoments.barWidth(118)).assertEqual(110);
      expect(CalendarDeadlineMoments.barX(118, 0)).assertEqual(4);
      expect(CalendarDeadlineMoments.barX(118, 6) + CalendarDeadlineMoments.barWidth(118)).assertEqual(822);
      expect(CalendarDeadlineMoments.barWidth(44)).assertEqual(36);
      expect(CalendarDeadlineMoments.barWidth(4)).assertEqual(0);
    });
    it('full_raw_catalog_is_rebucketed_by_shanghai_not_original_prefix', 0, () => {
      const catalog: AssignmentDeadlineItem[] = [
        new AssignmentDeadlineItem('utc', 'Synthetic UTC', 'Course', '2026-10-06T16:00:00Z', null, 'course'),
        new AssignmentDeadlineItem('offset', 'Synthetic offset', 'Course', '2026-10-06T17:00:00+01:00', null, 'course')];
      const courses: UCloudCourse[] = [new UCloudCourse('course', 'Course')];
      expect(CalendarDeadlineMoments.cloudOn('2026-10-06', catalog, courses).length).assertEqual(0);
      const nextDay = CalendarDeadlineMoments.cloudOn('2026-10-07', catalog, courses);
      expect(nextDay.length).assertEqual(2);
      expect(nextDay[0].deadline).assertEqual('2026-10-07 00:00');
      expect(nextDay[0].courseID).assertEqual('course');
    });
    it('bottom_adjacent_badges_merge_but_keep_both_actual_moment_anchors', 0, () => {
      const groups = CalendarDeadlineMoments.groups('2026-10-06', [
        deadline('first', '2026-10-06 23:58'), deadline('last', '2026-10-06 23:59')]);
      const badges = CalendarDeadlineMoments.badges(groups, 0, 1536, 64, []);
      expect(groups.length).assertEqual(2);
      expect(badges.length).assertEqual(1);
      expect(badges[0].items.length).assertEqual(2);
      expect(badges[0].minutes.join(',')).assertEqual('1438,1439');
      expect(badges[0].top + 18 <= 1536).assertTrue();
    });
    it('explicit_local_times_include_midnight_and_last_minute_but_not_date_only', 0, () => {
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06 00:00:00')).assertEqual(0);
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06 23:59:59')).assertEqual(1439);
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06')).assertEqual(null);
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06 24:00')).assertEqual(null);
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06 23:59:99')).assertEqual(null);
      expect(CalendarDeadlineMoments.minute('2026-02-30', '2026-02-30 12:00')).assertEqual(null);
    });
    it('explicit_offset_is_converted_to_shanghai_day_and_minute', 0, () => {
      expect(CalendarDeadlineMoments.minute('2026-10-07', '2026-10-06T16:00:00Z')).assertEqual(0);
      expect(CalendarDeadlineMoments.minute('2026-10-07', '2026-10-06T16:00:00.000Z')).assertEqual(0);
      expect(CalendarDeadlineMoments.minute('2026-10-07', '2026-10-06T17:00:00.999+01:00')).assertEqual(0);
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06T16:00:00Z')).assertEqual(null);
      expect(CalendarDeadlineMoments.minute('2026-10-07', '2026-10-06T17:00:00+01:00')).assertEqual(0);
      expect(CalendarDeadlineMoments.minute('2026-10-06', '2026-10-06T15:59:00Z')).assertEqual(1439);
    });
    it('same_timestamp_groups_without_repeated_identity_or_date_only_markers', 0, () => {
      const groups = CalendarDeadlineMoments.groups('2026-10-06', [
        deadline('one', '2026-10-06 06:30'), deadline('two', '2026-10-06 06:30'),
        deadline('one', '2026-10-06 06:30'), deadline('date-only', '2026-10-06')]);
      expect(groups.length).assertEqual(1);
      expect(groups[0].items.length).assertEqual(2);
      expect(groups[0].clock()).assertEqual('06:30');
      expect(CalendarDeadlineMoments.bounds([480, 1320], groups).join(',')).assertEqual('360,1320');
      const midnight = CalendarDeadlineMoments.groups('2026-10-06', [
        deadline('first', '2026-10-06 00:00'), deadline('last', '2026-10-06 23:59')]);
      expect(CalendarDeadlineMoments.bounds([480, 1320], midnight).join(',')).assertEqual('0,1440');
    });
    it('badge_clip_and_title_avoidance_do_not_change_the_exact_anchor', 0, () => {
      expect(CalendarDeadlineMoments.labelY(0, 1728, [])).assertEqual(0);
      expect(CalendarDeadlineMoments.labelY(1726.8, 1728, [])).assertEqual(1710);
      expect(CalendarDeadlineMoments.labelY(100, 1728, [96])).assertEqual(120);
      expect(CalendarDeadlineMoments.labelY(0, 8, [])).assertEqual(0);
    });
  });
}
