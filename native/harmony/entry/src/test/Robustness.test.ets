// 健壮性回归测试（BUG-018/019/049/062 修复验证）。
import { describe, it, expect } from '@ohos/hypium';
import { Course } from '../main/ets/common/Models';
import { JsonUtil } from '../main/ets/common/JsonUtil';
import { Utf8 } from '../main/ets/common/Utf8';
import { SJDFormURLEncoder } from '../main/ets/net/SjdEncoding';
import { HolidaySourceParser } from '../main/ets/net/parsers/HolidaySourceParser';

export default function robustnessTest() {
  describe('RobustnessTest', () => {
    it('course_from_json_clamps_out_of_range_slots', 0, () => {
      // BUG-049：越界节次/星期不得导致时间线越界访问。
      const raw: Record<string, Object> = {
        'id': 'c1', 'name': '越界课', 'teacher': '', 'room': '', 'week_text': '1-16',
        'week_numbers': [1], 'exam_week_numbers': [], 'weekday': 9,
        'start_slot': 99, 'end_slot': -3, 'section_text': '100节', 'time_range': '00:00-23:59'
      };
      const course: Course = Course.fromJson(raw);
      expect(course.weekday).assertEqual(7);
      expect(course.startSlot).assertEqual(13);
      expect(course.endSlot >= course.startSlot).assertTrue();
      const raw2: Record<string, Object> = {
        'id': 'c2', 'name': '下界课', 'teacher': '', 'room': '', 'week_text': '1-16',
        'week_numbers': [1], 'exam_week_numbers': [], 'weekday': 0,
        'start_slot': -5, 'end_slot': -1, 'section_text': '1节', 'time_range': '08:00-08:45'
      };
      const course2: Course = Course.fromJson(raw2);
      expect(course2.weekday).assertEqual(1);
      expect(course2.startSlot).assertEqual(0);
      expect(course2.endSlot).assertEqual(0);
    });

    it('json_util_string_accepts_numbers', 0, () => {
      // BUG-018：数字字段按字符串兼容（对齐 Swift NSNumber）。
      expect(JsonUtil.string(2026)).assertEqual('2026');
      expect(JsonUtil.string(3.5)).assertEqual('3.5');
      expect(JsonUtil.string(undefined)).assertEqual('');
      expect(JsonUtil.string(null, 'd')).assertEqual('d');
      expect(JsonUtil.string(true, 'd')).assertEqual('d');
    });

    it('utf8_and_form_encoder_replace_lone_surrogates', 0, () => {
      // BUG-062：孤立代理对按 U+FFFD 编码（EF BF BD）。
      const lone: string = '\uD800';
      const encoded: number[] = Utf8.bytes(lone);
      expect(encoded.length).assertEqual(3);
      expect(encoded[0]).assertEqual(0xEF);
      expect(encoded[1]).assertEqual(0xBF);
      expect(encoded[2]).assertEqual(0xBD);
      const form: string = SJDFormURLEncoder.encode(new Map<string, string>([['k', lone]]));
      expect(form).assertEqual('k=%EF%BF%BD');
      // 合法代理对仍为 4 字节（不回归）。
      expect(Utf8.bytes('\uD83C\uDF93').length).assertEqual(4);
    });

    it('holiday_name_length_counts_code_points', 0, () => {
      // BUG-019：emoji（代理对）按 1 个码点计数。
      expect(HolidaySourceParser.codePointLength('春节')).assertEqual(2);
      expect(HolidaySourceParser.codePointLength('春节\uD83C\uDF89')).assertEqual(3);
      expect(HolidaySourceParser.codePointLength('a\uD83C\uDF93b')).assertEqual(3);
    });
  });
}
