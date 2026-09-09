// PC 日历字号下限与手机既有排版分开验证，避免修复宽屏后抬高手机字号。
import { describe, it, expect } from '@ohos/hypium';
import { CalendarTypography } from '../main/ets/common/CalendarTypography';

export default function calendarTypographyTest() {
  describe('CalendarTypographyTest', () => {
    it('pc_calendar_labels_use_at_least_10fp', 0, () => {
      expect(CalendarTypography.minimumPcFontSize).assertEqual(10);
      // 年历星期、课程时间、全天标题和紧凑月历事件的实际请求值。
      expect(CalendarTypography.fontSize(8, true)).assertEqual(10);
      expect(CalendarTypography.fontSize(9, true)).assertEqual(10);
      expect(CalendarTypography.fontSize(9.5, true)).assertEqual(10);
    });

    it('pc_calendar_keeps_sizes_at_and_above_the_minimum', 0, () => {
      expect(CalendarTypography.fontSize(10, true)).assertEqual(10);
      expect(CalendarTypography.fontSize(10.5, true)).assertEqual(10.5);
      expect(CalendarTypography.fontSize(11, true)).assertEqual(11);
      expect(CalendarTypography.fontSize(14, true)).assertEqual(14);
      expect(CalendarTypography.fontSize(24, true)).assertEqual(24);
    });

    it('phone_and_non_pc_layouts_keep_the_requested_font_size', 0, () => {
      expect(CalendarTypography.fontSize(8, false)).assertEqual(8);
      expect(CalendarTypography.fontSize(9, false)).assertEqual(9);
      expect(CalendarTypography.fontSize(9.5, false)).assertEqual(9.5);
      expect(CalendarTypography.fontSize(10, false)).assertEqual(10);
      expect(CalendarTypography.fontSize(10.5, false)).assertEqual(10.5);
      expect(CalendarTypography.fontSize(11, false)).assertEqual(11);
      expect(CalendarTypography.fontSize(14, false)).assertEqual(14);
      expect(CalendarTypography.fontSize(24, false)).assertEqual(24);
    });
  });
}
