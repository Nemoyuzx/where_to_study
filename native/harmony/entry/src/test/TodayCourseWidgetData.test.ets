// 今日课程卡片数据层测试：课程过滤（周/星期）+ 绑定数据（行/空态/提示）。
// 与 Android TodayCourseWidgetLogicTest 的语义对齐。
import { describe, it, expect } from '@ohos/hypium';
import { DateParts } from '../main/ets/common/StrictDates';
import {
  TodayCourseWidgetData, WidgetArchive, WidgetArchiveCourse
} from '../main/ets/widget/TodayCourseWidgetData';

function course(id: string, name: string, room: string, timeRange: string,
  weekday: number, weeks: number[], startSlot: number): WidgetArchiveCourse {
  return new WidgetArchiveCourse(id, name, room, timeRange, weekday, weeks, [], startSlot);
}

function archive(): WidgetArchive {
  const courses: WidgetArchiveCourse[] = [
    course('c1', '高等数学', '教一-101', '08:00-09:35', 1, [1, 2, 3], 0),
    course('c2', '大学英语', '教二-202', '10:10-11:45', 1, [1, 2, 3], 2),
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
      expect(result.length).assertEqual(2); // c1 与 c2 在周一、包含第 1 周
      expect(result[0].name).assertEqual('高等数学');
      expect(result[1].name).assertEqual('大学英语');
      // 第 2 周周一：c1/c2/c4（c4 只在第 2 周）。
      const mondayWeek2: DateParts = new DateParts(2026, 3, 9);
      const week2: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(mondayWeek2, archive());
      expect(week2.length).assertEqual(3);
      expect(week2[2].name).assertEqual('数据结构');
    });

    it('courses_on_sorts_by_start_slot_then_name', 0, () => {
      const result: WidgetArchiveCourse[] = TodayCourseWidgetData.coursesOn(
        new DateParts(2026, 3, 2), archive());
      expect(result[0].startSlot).assertEqual(0);
      expect(result[1].startSlot).assertEqual(2);
    });

    it('binding_produces_structured_course_rows', 0, () => {
      const today: DateParts = new DateParts(2026, 3, 2);
      const data: Record<string, Object> = TodayCourseWidgetData.binding(archive(), 3, today);
      expect(data['todayTitle']).assertEqual('今日课程');
      expect(data['todayCountText']).assertEqual('2 门');
      expect(data['course1Name']).assertEqual('高等数学');
      expect(data['course1Details']).assertEqual('08:00-09:35 · 教一-101');
      expect(data['course2Name']).assertEqual('大学英语');
      expect(data['course3Name']).assertEqual('');
      expect(data['moreHint']).assertEqual('');
      expect(data['emptyText']).assertEqual('');
      expect(data['tomorrowHint']).assertEqual('明天 1 门课');
    });

    it('binding_respects_course_limit_for_small_dimension', 0, () => {
      const today: DateParts = new DateParts(2026, 3, 9); // 第 2 周周一：3 门课
      const data: Record<string, Object> = TodayCourseWidgetData.binding(archive(), 2, today);
      expect(data['course2Name']).assertEqual('大学英语');
      expect(data['course3Name']).assertEqual('');
      expect(data['moreHint']).assertEqual('另有 1 门课程');
    });

    it('binding_empty_state_without_archive', 0, () => {
      const data: Record<string, Object> = TodayCourseWidgetData.binding(null, 3,
        new DateParts(2026, 3, 2));
      expect(data['emptyGlyph']).assertEqual('↻');
      expect(data['emptyText']).assertEqual('打开应用获取个人课表');
      expect(data['course1Name']).assertEqual('');
      expect(data['todayCountText']).assertEqual('');
    });

    it('binding_empty_state_on_course_free_day', 0, () => {
      const data: Record<string, Object> = TodayCourseWidgetData.binding(archive(), 3,
        new DateParts(2026, 3, 4)); // 周三无课
      expect(data['emptyGlyph']).assertEqual('✓');
      expect(data['emptyText']).assertEqual('今天没有课程');
    });
  });
}
