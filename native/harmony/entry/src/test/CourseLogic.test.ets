import { describe, it, expect } from '@ohos/hypium';
import { AppSection, AppSectionInfo } from '../main/ets/common/AppSection';
import { CoursePageContract, CoursePageTab, CourseQMPlusScope,
  CourseCloudScope } from '../main/ets/common/CourseLogic';
import { QueryPageContract, QueryPageTab } from '../main/ets/common/QueryLogic';
import { AppLanguage, AppLocalization } from '../main/ets/common/AppLocalization';
import { CourseSession } from '../main/ets/view/CourseSession';
import { QMPlusActivity, QMPlusCourse, QMPlusSnapshot } from '../main/ets/net/QMPlusSnapshot';
import { UCloudCourse } from '../main/ets/net/UCloudAssignmentClient';
import { AssignmentDeadlineItem } from '../main/ets/net/CalendarDailyInfoClient';

export default function courseLogicTest() {
  describe('CourseLogicTest', () => {
    it('courses_are_primary_and_private_queries_stay_in_their_own_page', 0, () => {
      expect(AppSectionInfo.all.length).assertEqual(5);
      expect(AppSectionInfo.all[2]).assertEqual(AppSection.courses);
      expect(AppSectionInfo.title(AppSection.courses)).assertEqual('课程');
      expect(AppSectionInfo.accessibilityId(AppSection.courses)).assertEqual('navigation.courses');
      expect(QueryPageContract.tabs.length).assertEqual(2);
      expect(QueryPageContract.tabs[0]).assertEqual(QueryPageTab.shuttle);
      expect(QueryPageContract.tabs[1]).assertEqual(QueryPageTab.events);
      expect(CoursePageContract.tabs.length).assertEqual(4);
      expect(CoursePageContract.tabs[0]).assertEqual(CoursePageTab.current);
      expect(CoursePageContract.tabs[1]).assertEqual(CoursePageTab.grades);
      expect(CoursePageContract.tabs[2]).assertEqual(CoursePageTab.exams);
      expect(CoursePageContract.tabs[3]).assertEqual(CoursePageTab.assignments);
    });

    it('courses_keep_selected_subpage_across_root_view_recreation_and_translate_labels', 0, () => {
      const session: CourseSession = new CourseSession();
      expect(session.selectedTabRawValue).assertEqual(CoursePageTab.current);
      session.selectedTabRawValue = CoursePageTab.assignments;
      session.scrollOffsets.set(CoursePageTab.assignments, 144);
      expect(session.selectedTabRawValue).assertEqual(CoursePageTab.assignments);
      expect(session.scrollOffsets.get(CoursePageTab.assignments)).assertEqual(144);
      expect(AppLocalization.text(AppSectionInfo.title(AppSection.courses), AppLanguage.english, 'en-US'))
        .assertEqual('Courses');
      expect(AppLocalization.text(CoursePageContract.title(CoursePageTab.current), AppLanguage.english, 'en-US'))
        .assertEqual('Current Courses');
      expect(AppLocalization.text(CoursePageContract.title(CoursePageTab.assignments), AppLanguage.english, 'en-US'))
        .assertEqual('Assignments');
    });

    it('legacy_qmplus_snapshot_shows_only_trimmed_ebu_courses_and_their_current_activities', 0, () => {
      const courses: QMPlusCourse[] = [
        new QMPlusCourse('1', '  EBU Design', 'Design', null, null, null, 'current'),
        new QMPlusCourse('2', '中文课程', 'EBU Alias', null, null, null, 'current'),
        new QMPlusCourse('3', 'ebu History', 'History', null, null, null, 'other'),
        new QMPlusCourse('4', 'EBU Term Unknown', 'Unknown', null, null, null, 'unknown')
      ];
      const activities: QMPlusActivity[] = [
        new QMPlusActivity('11', '1', 'Published assignment', 'assignment',
          'https://qmplus.qmul.ac.uk/mod/assign/view.php?id=11',
          '2026-11-10T12:00:00.000Z', null, null, null, null, 'unknown', 'available', ''),
        new QMPlusActivity('12', '2', 'Chinese course quiz', 'quiz',
          'https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=12',
          null, '2026-11-10T12:00:00.000Z', '2026-11-10T13:00:00.000Z', null,
          1800, 'unknown', 'available', ''),
        new QMPlusActivity('13', '3', 'History quiz', 'quiz',
          'https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=13',
          null, null, null, null, null, 'unknown', 'available', ''),
        new QMPlusActivity('14', '4', 'Unknown term assignment', 'assignment',
          'https://qmplus.qmul.ac.uk/mod/assign/view.php?id=14',
          null, null, null, null, null, 'unknown', 'restricted', ''),
        new QMPlusActivity('15', '1', 'Non-assessment module', 'forum',
          'https://qmplus.qmul.ac.uk/mod/assign/view.php?id=15',
          null, null, null, null, null, 'unknown', 'available', '')
      ];
      const warnings: string[] = [];
      const snapshot: QMPlusSnapshot = new QMPlusSnapshot('2026-10-03T10:00:00.000Z',
        false, courses, activities, warnings);
      expect(CourseQMPlusScope.isEBUName(' eBu Design ')).assertTrue();
      expect(CourseQMPlusScope.isEBUName('Course EBU')).assertFalse();
      expect(CourseQMPlusScope.currentCourses(snapshot).length).assertEqual(1);
      expect(CourseQMPlusScope.currentCourses(snapshot)[0].id).assertEqual('1');
      expect(CourseQMPlusScope.otherCourses(snapshot).length).assertEqual(2);
      expect(CourseQMPlusScope.otherCourses(snapshot)[0].id).assertEqual('3');
      expect(CourseQMPlusScope.otherCourses(snapshot)[1].id).assertEqual('4');
      expect(CourseQMPlusScope.currentActivities(snapshot).length).assertEqual(1);
      expect(CourseQMPlusScope.currentActivities(snapshot)[0].id).assertEqual('11');
    });

    it('qmplus_utc_times_render_as_beijing_without_using_device_timezone_or_guessing_invalid_dates', 0, () => {
      expect(CourseQMPlusScope.shanghaiTime('2026-10-24T20:30:00.000Z'))
        .assertEqual('2026-10-25 04:30');
      expect(CourseQMPlusScope.shanghaiTime('2026-06-01T23:59:00.000Z'))
        .assertEqual('2026-06-02 07:59');
      expect(CourseQMPlusScope.shanghaiTime('unknown')).assertEqual('unknown');
    });

    it('course_detail_owner_survives_navigation_without_losing_overview_scroll', 0, () => {
      const session: CourseSession = new CourseSession();
      session.scrollOffsets.set(CoursePageTab.current, 172);
      session.openCourse('ucloud', 'site-17');
      expect(session.selectedCourseSource).assertEqual('ucloud');
      expect(session.selectedCourseID).assertEqual('site-17');
      session.detailScrollOffset = 84;
      session.closeCourse();
      expect(session.selectedCourseID).assertEqual('');
      expect(session.selectedTabRawValue).assertEqual(CoursePageTab.current);
      expect(session.scrollOffsets.get(CoursePageTab.current)).assertEqual(172);
      session.openCourse('unknown', 'site-18');
      expect(session.selectedCourseID).assertEqual('');
    });

    it('teaching_cloud_details_use_site_id_or_a_unique_exact_legacy_name_only', 0, () => {
      const courseA: UCloudCourse = new UCloudCourse('17', 'Shared Name');
      const courseB: UCloudCourse = new UCloudCourse('18', 'Shared Name');
      const directory: UCloudCourse[] = [courseA, courseB];
      const assignments: AssignmentDeadlineItem[] = [
        new AssignmentDeadlineItem('1', 'Known A', 'Shared Name', '2026-11-01 12:00:00', '未提交', '17'),
        new AssignmentDeadlineItem('2', 'Known B', 'Shared Name', '2026-11-02 12:00:00', '已提交', '18'),
        new AssignmentDeadlineItem('3', 'Old no id', 'Shared Name', '2026-11-03 12:00:00', '已完成')
      ];
      expect(CourseCloudScope.assignmentsFor(courseA, directory, assignments, false).length).assertEqual(0);
      expect(CourseCloudScope.assignmentsFor(courseA, directory, assignments, true).length).assertEqual(1);
      expect(CourseCloudScope.assignmentsFor(courseA, directory, assignments, true)[0].id).assertEqual('1');
      const uniqueDirectory: UCloudCourse[] = [courseA];
      expect(CourseCloudScope.assignmentsFor(courseA, uniqueDirectory, assignments, true).length).assertEqual(2);
    });

    it('submission_badges_count_only_explicit_statuses_and_never_infer_complete_as_submitted', 0, () => {
      const statuses: string[] = [' 未提交 ', 'not submitted', 'nothing submitted',
        'no submissions have been made yet', ' 已提交 ', 'submitted', 'submitted for grading',
        '已批改', '已驳回', 'complete', '已完成', ''];
      const items: AssignmentDeadlineItem[] = statuses.map((status: string, index: number): AssignmentDeadlineItem =>
        new AssignmentDeadlineItem(index.toString(), 'Synthetic', 'Course', '2026-11-01 12:00:00', status));
      const counts = CourseCloudScope.submissionCounts(items);
      expect(counts.pending).assertEqual(4);
      expect(counts.submitted).assertEqual(3);
      expect(CourseCloudScope.submissionCounts([]).submitted).assertEqual(0);
    });
  });
}
