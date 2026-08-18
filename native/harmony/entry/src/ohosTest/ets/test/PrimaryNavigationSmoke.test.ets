// 主导航 UI 冒烟测试，对应 iOS 端 PrimaryNavigationSmokeTests 的关键断言：
// 三个一级页面可导航、示例模式（review-demo）展示本地数据、
// 日历四视图切换与月视图展开收起。
import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { Driver, ON, MatchPattern, Component, Point } from '@ohos.UiTest';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';

const BUNDLE_NAME: string = 'com.nemoyu.wheretostudy.native.harmony';

async function launchApp(reviewDemo: boolean): Promise<void> {
  const delegator = AbilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({
    bundleName: BUNDLE_NAME,
    abilityName: 'EntryAbility',
    parameters: reviewDemo ? { 'reviewDemo': true } : { 'uiTesting': true }
  });
  const driver: Driver = Driver.create();
  await driver.delayMs(4000);
}

async function findText(driver: Driver, text: string, timeoutMs: number = 5000): Promise<Component | null> {
  const deadline: number = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const component: Component = await driver.findComponent(ON.text(text));
      return component;
    } catch (e) {
      await driver.delayMs(400);
    }
  }
  return null;
}

async function findTextPattern(
  driver: Driver, text: string, pattern: MatchPattern, timeoutMs: number = 5000
): Promise<Component | null> {
  const deadline: number = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const component: Component = await driver.findComponent(ON.text(text, pattern));
      return component;
    } catch (e) {
      await driver.delayMs(400);
    }
  }
  return null;
}

async function expectText(driver: Driver, text: string, message: string): Promise<void> {
  const component: Component | null = await findText(driver, text);
  expect(component !== null).assertTrue();
}

export default function primaryNavigationSmokeTest() {
  describe('PrimaryNavigationSmoke', () => {
    it('primary_pages_are_navigable', 0, async () => {
      await launchApp(false);
      const driver: Driver = Driver.create();
      // 空教室页
      const plannerTitle: Component | null = await findText(driver, '联动查询');
      expect(plannerTitle !== null).assertTrue();
      // 教学日历
      const calendarTab: Component | null = await findText(driver, '教学日历');
      expect(calendarTab !== null).assertTrue();
      await calendarTab?.click();
      await driver.delayMs(1200);
      const todayButton: Component | null = await findText(driver, '今天');
      expect(todayButton !== null).assertTrue();
      const weekMode: Component | null = await findText(driver, '周');
      expect(weekMode !== null).assertTrue();
      // 设置
      const settingsTab: Component | null = await findText(driver, '设置');
      expect(settingsTab !== null).assertTrue();
      await settingsTab?.click();
      await driver.delayMs(1200);
      const accountHeader: Component | null = await findText(driver, '个人账户');
      expect(accountHeader !== null).assertTrue();
      // 回到空教室
      const plannerTab: Component | null = await findText(driver, '空教室');
      expect(plannerTab !== null).assertTrue();
      await plannerTab?.click();
      await driver.delayMs(1200);
      const plannerTitleAgain: Component | null = await findText(driver, '联动查询');
      expect(plannerTitleAgain !== null).assertTrue();
    });

    it('review_demo_shows_local_data_without_account', 0, async () => {
      await launchApp(true);
      const driver: Driver = Driver.create();
      const banner: Component | null = await findText(driver, '示例数据 · 不连接北邮教务服务');
      expect(banner !== null).assertTrue();
      const sampleCourse: Component | null = await findText(driver, '数据挖掘');
      expect(sampleCourse !== null).assertTrue();
      // 设置页示例模式说明与提醒开关
      const settingsTab: Component | null = await findText(driver, '设置');
      expect(settingsTab !== null).assertTrue();
      await settingsTab?.click();
      await driver.delayMs(1200);
      const demoNote: Component | null = await findText(
        driver, '内置示例模式已开启，不会连接教务服务或读写真实用户数据。');
      expect(demoNote !== null).assertTrue();
      const toggleLabel: Component | null = await findText(driver, '每天 07:30 发送当日课程摘要');
      expect(toggleLabel !== null).assertTrue();
      await toggleLabel?.click();
      await driver.delayMs(800);
      const simulatedMessage: Component | null = await findText(
        driver, '示例模式已模拟开启每日课程摘要，未申请通知权限');
      expect(simulatedMessage !== null).assertTrue();
    });

    it('calendar_modes_switch_and_month_expands', 0, async () => {
      await launchApp(true);
      const driver: Driver = Driver.create();
      const calendarTab: Component | null = await findText(driver, '教学日历');
      expect(calendarTab !== null).assertTrue();
      await calendarTab?.click();
      await driver.delayMs(1500);
      // 周视图标题：YYYY年M月 第 N 周
      const weekTitle: Component | null = await findTextPattern(
        driver, ' 周', MatchPattern.ENDS_WITH);
      expect(weekTitle !== null).assertTrue();
      const weekText: string = weekTitle !== null ? await weekTitle.getText() : '';
      expect(weekText.includes('第 ')).assertTrue();
      // 日视图
      const dayMode: Component | null = await findText(driver, '日');
      expect(dayMode !== null).assertTrue();
      await dayMode?.click();
      await driver.delayMs(1200);
      const dayTitle: Component | null = await findTextPattern(
        driver, '日', MatchPattern.ENDS_WITH);
      expect(dayTitle !== null).assertTrue();
      // 月视图与展开/收起
      const monthMode: Component | null = await findText(driver, '月');
      expect(monthMode !== null).assertTrue();
      await monthMode?.click();
      await driver.delayMs(1200);
      const monthTitle: Component | null = await findTextPattern(
        driver, '月', MatchPattern.ENDS_WITH);
      expect(monthTitle !== null).assertTrue();
      const mondayHeader: Component | null = await findText(driver, '一');
      expect(mondayHeader !== null).assertTrue();
      // 收起月历：点击展开/收起把手（位于月网格下方，用下滑手势触发）
      const size: Point = await driver.getDisplaySize();
      await driver.swipe(size.x / 2, size.y * 0.68, size.x / 2, size.y * 0.30);
      await driver.delayMs(1000);
      const collapsedSummary: Component | null = await findText(
        driver, '暂无课程');
      expect(collapsedSummary !== null).assertTrue();
      // 再展开
      await driver.swipe(size.x / 2, size.y * 0.30, size.x / 2, size.y * 0.68);
      await driver.delayMs(1000);
      // 年视图
      const yearMode: Component | null = await findText(driver, '年');
      expect(yearMode !== null).assertTrue();
      await yearMode?.click();
      await driver.delayMs(1200);
      const yearHint: Component | null = await findText(driver, '颜色越深表示当天课程越多');
      expect(yearHint !== null).assertTrue();
      const januaryLabel: Component | null = await findText(driver, '1月');
      expect(januaryLabel !== null).assertTrue();
    });
  });
}
