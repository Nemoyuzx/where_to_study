// 今日课程卡片数据层测试：课程过滤 + 阶段/高亮/上下文 + 绑定数据（行/空态）。
// 与 Android TodayCourseWidgetLogicTest / Apple TodayCourseWidgetDataTests 对齐。
import { describe, it, expect } from '@ohos/hypium';
import { DateParts } from '../main/ets/common/StrictDates';
import {
  TodayCourseWidgetData, WidgetArchive, WidgetArchiveCourse,
  WidgetCoursePreferences, CoursePhase
} from '../main/ets/widget/TodayCourseWidgetData';
import { AppLanguage } from '../main/ets/common/AppLocalization';

function course(id: string, name: string, room: string, timeRange: string,
  weekday: number, weeks: number[], startSlot: number,
  sectionText: string = '1-2节'): WidgetArchiveCourse {
  return new WidgetArchiveCourse(id, name, '测试教师', room, sectionText, timeRange,
    weekday, weeks, [], startSlot);
}

function archive(): WidgetArchive {
  const courses: WidgetArchiveCourse[] = [
    course('c1', '高等数学', '教一-101', '08:00-09:35', 1, [1, 2, 3], 0),
    course('c2', '大学英语', '教二-202', '10:10-11:45', 1, [1, 2, 3], 2, '3-4节'),
    course('c3', '物理实验', '实验楼-301', '14:00-15:40', 2, [1, 2, 3], 5),
    course('c4', '数据结构', '教三-303', '16:00-17:35', 1, [2], 7),
  ];
  return new WidgetArchive('2026-03-02', '2026-03-02T00:00:00Z', courses);
}

export default function todayCourseWidgetDataTest() {
  describe('TodayCourseWidgetDataTest', () => {
    it('courses_on_filters_by_weekday_and_week', 0, () => {
      // 2026-03-02 是周一（第一周）。
      const mondayWeek1: DateParts = new DateParts(2026, 3, 2);
      const result: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(mondayWeek1, archive());
      expect(result.length).assertEqual(2);
      expect(result[0].name).assertEqual('高等数学');
      expect(result[1].name).assertEqual('大学英语');
      const mondayWeek2: DateParts = new DateParts(2026, 3, 9);
      const week2: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(mondayWeek2, archive());
      expect(week2.length).assertEqual(3);
      expect(week2[2].name).assertEqual('数据结构');
    });

    it('course_phase_detects_upcoming_in_progress_finished', 0, () => {
      const c: WidgetArchiveCourse = course('c', '高数', '教一-101', '08:00-09:35', 1, [1], 0);
      expect(TodayCourseWidgetData.coursePhase(c, new DateParts(2026, 3, 2), 7 * 60))
        .assertEqual(CoursePhase.upcoming);
      expect(TodayCourseWidgetData.coursePhase(c, new DateParts(2026, 3, 2), 8 * 60 + 30))
        .assertEqual(CoursePhase.inProgress);
      expect(TodayCourseWidgetData.coursePhase(c, new DateParts(2026, 3, 2), 10 * 60))
        .assertEqual(CoursePhase.finished);
    });

    it('binding_produces_context_status_and_highlighted_rows', 0, () => {
      const today: DateParts = new DateParts(2026, 3, 2);
      const data: Record<string, Object> = TodayCourseWidgetData.binding(
        archive(), new WidgetCoursePreferences(), today, 8 * 60 + 30);
      expect(data['todayTitle']).assertEqual('今日课程');
      expect(data['todayCountText']).assertEqual('2 门');
      expect(String(data['dateContext'])).assertEqual('3月2日 · 周一 · 第1周');
      expect(String(data['statusText'])).assertEqual('进行中 · 09:35 下课');
      // 高等数学（08:00-09:35）正在进行中 -> 高亮 + 前缀
      expect(String(data['course1Name'])).assertEqual('进行中 · 高等数学');
      expect(data['course1Highlighted']).assertEqual(true);
      // 大学英语（10:10）下一节 -> 前缀
      expect(String(data['course2Name'])).assertEqual('下一节 · 大学英语');
      expect(String(data['course2Details'])).assertEqual('10:10-11:45 · 3-4节 · 教二-202 · 测试教师');
      expect(String(data['course3Name'])).assertEqual('');
    });

    it('binding_respects_course_limit_and_shows_more_hint', 0, () => {
      const today: DateParts = new DateParts(2026, 3, 9); // 第 2 周周一：3 门课
      const data: Record<string, Object> = TodayCourseWidgetData.binding(
        archive(), new WidgetCoursePreferences(true, true, 2), today, 9 * 60);
      // 9:00 时大学英语（10:10）为下一节 -> 前缀
      expect(String(data['course2Name'])).assertEqual('下一节 · 大学英语');
      expect(String(data['course3Name'])).assertEqual('');
      expect(String(data['moreHint'])).assertEqual('另有 1 门课程');
    });

    it('binding_empty_state_without_archive', 0, () => {
      const data: Record<string, Object> = TodayCourseWidgetData.binding(
        null, new WidgetCoursePreferences(), new DateParts(2026, 3, 2), 9 * 60);
      expect(String(data['emptyGlyph'])).assertEqual('↻');
      expect(String(data['emptyText'])).assertEqual('打开应用获取个人课表');
      expect(String(data['course1Name'])).assertEqual('');
      expect(String(data['todayCountText'])).assertEqual('');
    });

    it('binding_empty_state_on_course_free_day', 0, () => {
      const data: Record<string, Object> = TodayCourseWidgetData.binding(
        archive(), new WidgetCoursePreferences(), new DateParts(2026, 3, 4), 9 * 60);
      expect(String(data['emptyGlyph'])).assertEqual('✓');
      expect(String(data['emptyText'])).assertEqual('今日无课');
      expect(String(data['statusText'])).assertEqual('今天可以自由安排');
    });

    it('binding_localizes_static_widget_copy_without_touching_course_names', 0, () => {
      const data: Record<string, Object> = TodayCourseWidgetData.binding(
        archive(), new WidgetCoursePreferences(true, true, 4, AppLanguage.english),
        new DateParts(2026, 3, 2), 8 * 60 + 30);
      expect(String(data['todayTitle'])).assertEqual('Today\'s Courses');
      expect(String(data['dateContext'])).assertEqual('3/2 · Mon · Week 1');
      expect(String(data['course1Name'])).assertEqual('In progress · 高等数学');
    });

    it('preview_archive_contains_sample_courses', 0, () => {
      const preview: WidgetArchive = TodayCourseWidgetData.previewArchive();
      expect(preview.courses.length).assertEqual(6);
      expect(preview.courses[0].name).assertEqual('高等数学');
    });
  });
}
