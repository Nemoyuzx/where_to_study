// 折叠屏与宽屏布局策略（对应 iOS AdaptiveLayoutPolicy 语义）。
// DeviceState 依赖设备 API，这里用纯函数 useSidebarFor/useTwoColumnFor/
// useExpandedCalendarFor 验证阈值与半折叠降级规则。
import { describe, it, expect } from '@ohos/hypium';
import {
  AdaptiveLayoutPolicy, DeviceFoldState, PhoneNavigationLayout
} from '../main/ets/common/DeviceState';

export default function adaptivePolicyTest() {
  describe('AdaptivePolicyTest', () => {
    it('compact_widths_use_tabs_single_column_compact_calendar', 0, () => {
      expect(AdaptiveLayoutPolicy.useSidebarFor(430, DeviceFoldState.expanded)).assertFalse();
      expect(AdaptiveLayoutPolicy.useSidebarFor(699, DeviceFoldState.expanded)).assertFalse();
      expect(AdaptiveLayoutPolicy.useTwoColumnFor(759, DeviceFoldState.expanded)).assertFalse();
      expect(AdaptiveLayoutPolicy.useExpandedCalendarFor(867, DeviceFoldState.expanded)).assertFalse();
    });

    it('wide_widths_use_sidebar_two_columns_expanded_calendar', 0, () => {
      expect(AdaptiveLayoutPolicy.useSidebarFor(700, DeviceFoldState.expanded)).assertTrue();
      expect(AdaptiveLayoutPolicy.useSidebarFor(1024, DeviceFoldState.expanded)).assertTrue();
      expect(AdaptiveLayoutPolicy.useTwoColumnFor(760, DeviceFoldState.expanded)).assertTrue();
      expect(AdaptiveLayoutPolicy.useExpandedCalendarFor(760, DeviceFoldState.expanded)).assertFalse();
      expect(AdaptiveLayoutPolicy.useExpandedCalendarFor(868, DeviceFoldState.expanded)).assertTrue();
    });

    it('half_folded_forces_compact_even_when_wide', 0, () => {
      // 半折叠时铰链横贯屏幕中部，任何宽度都退化为紧凑布局。
      expect(AdaptiveLayoutPolicy.useSidebarFor(1024, DeviceFoldState.halfFolded)).assertFalse();
      expect(AdaptiveLayoutPolicy.useTwoColumnFor(1024, DeviceFoldState.halfFolded)).assertFalse();
      expect(AdaptiveLayoutPolicy.useExpandedCalendarFor(1024, DeviceFoldState.halfFolded)).assertFalse();
    });

    it('folded_and_unknown_states_follow_width', 0, () => {
      expect(AdaptiveLayoutPolicy.useSidebarFor(1024, DeviceFoldState.folded)).assertTrue();
      expect(AdaptiveLayoutPolicy.useSidebarFor(1024, DeviceFoldState.unknown)).assertTrue();
      expect(AdaptiveLayoutPolicy.useSidebarFor(430, DeviceFoldState.folded)).assertFalse();
    });

    it('phone_navigation_uses_device_inset_with_28vp_minimum', 0, () => {
      expect(PhoneNavigationLayout.bottomMarginFor(0)).assertEqual(28);
      expect(PhoneNavigationLayout.bottomMarginFor(10, 24)).assertEqual(28);
      expect(PhoneNavigationLayout.bottomMarginFor(28, 0)).assertEqual(28);
      expect(PhoneNavigationLayout.bottomMarginFor(34, 20)).assertEqual(34);
      expect(PhoneNavigationLayout.bottomMarginFor(20, 36)).assertEqual(36);
      expect(PhoneNavigationLayout.bottomMarginFor(-10, 12)).assertEqual(28);
      expect(PhoneNavigationLayout.bottomMarginFor(Number.NaN, 18)).assertEqual(28);
      expect(PhoneNavigationLayout.bottomMarginFor(Number.POSITIVE_INFINITY, 18)).assertEqual(28);
    });
  });
}
