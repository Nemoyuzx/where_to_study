// 常规用例仅 review-demo 本地 UI：不聚焦输入框、不保存自定义 URL 或请求网络。
// 真实键盘输入用例只在测试运行参数 runSettingsKeyboardInput=true 时注册，
// 不能自动同意第三方输入法协议。
// 第二项必须在旋转后确实跨 phone_navigation ↔ root_sidebar_layout，不能只按屏幕总宽推断。
import { describe, it, expect } from '@ohos/hypium';
import { Component, DisplayRotation, Driver, ON, Point, Rect } from '@ohos.UiTest';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { display } from '@kit.ArkUI';

const BUNDLE_NAME: string = 'com.nemoyu.wheretostudy';

async function launchReviewDemo(seedDrafts: boolean = false): Promise<Driver> {
  const delegator = AbilityDelegatorRegistry.getAbilityDelegator();
  await delegator.startAbility({
    bundleName: BUNDLE_NAME,
    abilityName: 'EntryAbility',
    parameters: seedDrafts ?
      { 'reviewDemo': true, 'privacyConsentAcceptedForTesting': true,
        'settingsPresentationSeedForTesting': true } :
      { 'reviewDemo': true, 'privacyConsentAcceptedForTesting': true }
  });
  const driver: Driver = Driver.create();
  await driver.delayMs(4000);
  return driver;
}

async function hasID(driver: Driver, id: string): Promise<boolean> {
  try {
    return await driver.findComponent(ON.id(id)) !== null;
  } catch (e) {
    return false;
  }
}

async function hasText(driver: Driver, value: string): Promise<boolean> {
  try {
    return await driver.findComponent(ON.text(value)) !== null;
  } catch (e) {
    return false;
  }
}

async function policyVisible(driver: Driver): Promise<boolean> {
  // privacy_policy_page 是纯 Column，UiTest 不一定将其作为可访问节点导出；
  // 交互式关闭入口加真实标题一起确认页面，避免靠底层设置树误判。
  return await hasID(driver, 'privacy_policy_close') &&
    (await hasText(driver, '隐私声明') || await hasText(driver, 'Privacy Policy'));
}

async function openSettings(driver: Driver): Promise<void> {
  const settings: Component = await driver.findComponent(ON.id('navigation.settings'));
  await settings.click();
  await driver.delayMs(450);
  expect(await hasID(driver, 'settings_scroll')).assertTrue();
}

async function visibleSetting(driver: Driver, id: string): Promise<Component | null> {
  try {
    const scroll: Component = await driver.findComponent(ON.id('settings_scroll'));
    const viewport = await scroll.getBounds();
    const target: Component = await driver.findComponent(ON.id(id));
    if (target === null) { return null; }
    const bounds = await target.getBounds();
    let safeBottom: number = viewport.bottom;
    try {
      const navigation: Component = await driver.findComponent(ON.id('phone_navigation'));
      if (navigation !== null) {
        safeBottom = Math.min(safeBottom, (await navigation.getBounds()).top - 6);
      }
    } catch (e) {}
    const centerY: number = (bounds.top + bounds.bottom) / 2;
    return centerY > viewport.top + 12 && centerY < safeBottom - 12 &&
      bounds.right > viewport.left && bounds.left < viewport.right ? target : null;
  } catch (e) {
    return null;
  }
}

function boundsText(bounds: Rect): string {
  return '[' + bounds.left.toString() + ',' + bounds.top.toString() + ',' +
    bounds.right.toString() + ',' + bounds.bottom.toString() + ']';
}

async function safeSwipeStartFraction(driver: Driver, bounds: Rect, x: number): Promise<number> {
  // Swipe 的首触点会让 TextInput 获得焦点；即使只想滚动也可能弹出第三方 IME。
  // 依据真实控件边界选择卡片文字/间隙，避免所有当前可见的设置输入框。
  const inputIDs: string[] = [
    'settings_custom_deadline_url', 'settings_pre_class_minutes_0',
    'color_theme_primary', 'color_theme_accent', 'color_theme_selected_date'
  ];
  const inputBounds: Rect[] = [];
  for (const id of inputIDs) {
    try {
      const input: Component = await driver.findComponent(ON.id(id));
      if (input !== null) { inputBounds.push(await input.getBounds()); }
    } catch (e) {}
  }
  for (const fraction of [0.78, 0.72, 0.66, 0.60, 0.54, 0.48]) {
    const y: number = Math.round(bounds.top + (bounds.bottom - bounds.top) * fraction);
    if (!inputBounds.some((input: Rect): boolean =>
      x >= input.left - 6 && x <= input.right + 6 &&
      y >= input.top - 8 && y <= input.bottom + 8)) {
      return fraction;
    }
  }
  throw new Error('设置页当前视口没有可安全开始滚动的非输入框位置');
}

async function scrollToSetting(driver: Driver, id: string): Promise<Component> {
  const scroll: Component = await driver.findComponent(ON.id('settings_scroll'));
  await scroll.scrollToTop();
  for (let attempt: number = 0; attempt < 18; attempt++) {
    const target: Component | null = await visibleSetting(driver, id);
    if (target !== null) { return target; }
    const bounds = await scroll.getBounds();
    // UiTest.getDisplayDensity returns physical x/y DPI, not the vp scale.
    // Reuse the SDK's logical pixel ratio from PrimaryNavigationSmoke.
    const pixelsPerVp: number = display.getDefaultDisplaySync().densityPixels;
    if (!Number.isFinite(pixelsPerVp) || pixelsPerVp <= 0) {
      throw new Error('UiTest 未返回有效显示密度，不能猜测 20vp 内边距的触摸位置');
    }
    // settingsContent 的左右内边距为20vp。18vp 是 Scroll 内、卡片外的纵向拖动通道；
    // 不从屏幕最外侧像素启动，也不会按 TextInput 的全宽中线触发输入法。
    const x: number = Math.round(bounds.left + pixelsPerVp * 18);
    if (x <= bounds.left + 6 || x >= bounds.right - 6 || x >= bounds.left + pixelsPerVp * 20) {
      throw new Error('设置页 Scroll 过窄，18vp 拖动通道不在有效内边距中');
    }
    const startFraction: number = await safeSwipeStartFraction(driver, bounds, x);
    const yStart: number = Math.round(bounds.top + (bounds.bottom - bounds.top) * startFraction);
    const yEnd: number = Math.round(bounds.top + (bounds.bottom - bounds.top) *
      Math.max(0.12, startFraction - 0.38));
    await driver.swipe(x, yStart, x, yEnd, 700);
  }
  throw new Error('连续 18 次在 settings_scroll 内向下滑动仍未显示 ' + id);
}

async function withFailureEvidence(driver: Driver, label: string, cause: Object): Promise<Error> {
  let screenshot: string = 'unavailable';
  let captured: boolean = false;
  try {
    const context = AbilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    screenshot = context.filesDir + '/settings-presentation-' + label + '-failure.png';
    captured = await driver.screenCap(screenshot);
  } catch (e) {}
  let displaySize: string = 'unavailable';
  try {
    const size: Point = await driver.getDisplaySize();
    displaySize = size.x.toString() + 'x' + size.y.toString();
  } catch (e) {}
  const ids: string[] = [
    'settings_scroll', 'settings_privacy_policy', 'settings_custom_deadline_url',
    'settings_pre_class_notification_edit', 'settings_pre_class_minutes_0',
    'privacy_policy_page', 'phone_navigation', 'root_sidebar_layout'
  ];
  const visible: string[] = [];
  for (const id of ids) {
    if (await hasID(driver, id)) { visible.push(id); }
  }
  let scrollBounds: string = 'unavailable';
  try {
    const bounds = await (await driver.findComponent(ON.id('settings_scroll'))).getBounds();
    scrollBounds = bounds.left.toString() + ',' + bounds.top.toString() + ',' +
      bounds.right.toString() + ',' + bounds.bottom.toString();
  } catch (e) {}
  const reason: string = cause instanceof Error ? cause.message : String(cause);
  return new Error(reason + '；截图=' + screenshot + ' captured=' + captured.toString() +
    '；display=' + displaySize +
    '；settingsScrollBounds=' + scrollBounds + '；现存ID=' + visible.join(','));
}

async function enterDraft(driver: Driver, id: string, value: string): Promise<void> {
  const field: Component = await scrollToSetting(driver, id);
  expect(await field.isEnabled()).assertTrue();
  await field.click();
  await field.clearText();
  await field.inputText(value);
  expect(await field.getOriginalText()).assertEqual(value);
}

async function actualSettingsBranch(driver: Driver): Promise<string> {
  const sidebar: boolean = await hasID(driver, 'root_sidebar_layout');
  const phone: boolean = await hasID(driver, 'phone_navigation');
  if (sidebar === phone) {
    const size: Point = await driver.getDisplaySize();
    throw new Error('设置页无法确认单一布局分支：sidebar=' + sidebar.toString() +
      ', phone=' + phone.toString() + ', display=' + size.x.toString() + 'x' + size.y.toString());
  }
  return sidebar ? 'sidebar' : 'phone';
}

async function requireBranch(driver: Driver, expected: string): Promise<void> {
  const actual: string = await actualSettingsBranch(driver);
  if (actual !== expected) {
    const size: Point = await driver.getDisplaySize();
    throw new Error('该设备旋转未跨越真实布局边界：期望 ' + expected + '，实际 ' + actual +
      '，display=' + size.x.toString() + 'x' + size.y.toString() +
      '。此用例需在旋转可切换窄/宽布局的设备上运行，不能按总像素宽度假定侧栏。');
  }
}

export default function settingsPresentationDeviceTest() {
  describe('SettingsPresentationDevice', () => {
    it('privacy_open_close_preserves_the_underlying_settings_scroll_position', 0, async () => {
      const driver: Driver = await launchReviewDemo();
      try {
        await openSettings(driver);
        // 按真实可点击的“隐私说明”锚点测量 About 区域；非交互 Column
        // 在 UiTest 可访问树中可能不暴露，不能用它的 ID 假设 getBounds 可取。
        const policyLink: Component = await scrollToSetting(driver, 'settings_privacy_policy');
        const aboutAnchorBefore = await policyLink.getBounds();
        await policyLink.click();
        await driver.delayMs(350);
        expect(await policyVisible(driver)).assertTrue();
        await (await driver.findComponent(ON.id('privacy_policy_close'))).click();
        await driver.delayMs(350);
        expect(await policyVisible(driver)).assertFalse();
        expect(await hasID(driver, 'settings_scroll')).assertTrue();
        // 不再次滚动查找：原锚点必须仍在原视口位置，才能证明底层 Scroll 未重建。
        const policyAfter: Component | null = await visibleSetting(driver, 'settings_privacy_policy');
        if (policyAfter === null) {
          throw new Error('返回后 About 内隐私入口不在原视口');
        }
        const aboutAnchorAfter = await policyAfter.getBounds();
        expect(Math.abs(aboutAnchorAfter.top - aboutAnchorBefore.top) <= 12).assertTrue();
      } catch (e) {
        throw await withFailureEvidence(driver, 'privacy-scroll', e);
      }
    });

    it('seeded_unsaved_drafts_survive_real_phone_sidebar_rotation_both_ways', 0, async () => {
      const driver: Driver = await launchReviewDemo(true);
      const originalRotation: DisplayRotation = await driver.getDisplayRotation();
      const customURL: string = 'https://example.org/review-only-feed.json';
      try {
        await driver.setDisplayRotation(DisplayRotation.ROTATION_0);
        await driver.delayMs(1000);
        await requireBranch(driver, 'phone');
        await openSettings(driver);

        // 明确只验证 DEBUG review-demo 的纯内存固定草稿；没有输入法或实体输入验证。
        expect(await (await scrollToSetting(driver, 'settings_pre_class_minutes_0')).getOriginalText())
          .assertEqual('17');
        expect(await (await scrollToSetting(driver, 'settings_custom_deadline_url')).getOriginalText())
          .assertEqual(customURL);
        const policyLink: Component = await scrollToSetting(driver, 'settings_privacy_policy');
        await policyLink.click();
        await driver.delayMs(350);
        expect(await policyVisible(driver)).assertTrue();

        await driver.setDisplayRotation(DisplayRotation.ROTATION_90);
        await driver.delayMs(1100);
        expect(await policyVisible(driver)).assertTrue();
        await (await driver.findComponent(ON.id('privacy_policy_close'))).click();
        await driver.delayMs(400);
        await requireBranch(driver, 'sidebar');
        expect(await (await scrollToSetting(driver, 'settings_custom_deadline_url')).getOriginalText())
          .assertEqual(customURL);
        expect(await (await scrollToSetting(driver, 'settings_pre_class_minutes_0')).getOriginalText())
          .assertEqual('17');

        await driver.setDisplayRotation(DisplayRotation.ROTATION_0);
        await driver.delayMs(1100);
        await requireBranch(driver, 'phone');
        expect(await (await scrollToSetting(driver, 'settings_custom_deadline_url')).getOriginalText())
          .assertEqual(customURL);
        expect(await (await scrollToSetting(driver, 'settings_pre_class_minutes_0')).getOriginalText())
          .assertEqual('17');
      } catch (e) {
        throw await withFailureEvidence(driver, 'draft-rotation', e);
      } finally {
        try {
          // 显式无 seed 的 review Want 让 EntryAbility 恢复原 preferredOrientation；
          // 不更改系统自动旋转开关，也不影响真实输入可选 suite。
          await AbilityDelegatorRegistry.getAbilityDelegator().startAbility({
            bundleName: BUNDLE_NAME,
            abilityName: 'EntryAbility',
            parameters: { 'reviewDemo': true, 'privacyConsentAcceptedForTesting': true }
          });
        } finally {
          await driver.setDisplayRotation(originalRotation);
        }
      }
    });

    it('language_switch_keeps_the_visible_settings_anchor_in_place', 0, async () => {
      const driver: Driver = await launchReviewDemo(true);
      try {
        await openSettings(driver);
        const english: Component = await scrollToSetting(driver, 'settings.language.2');
        const before = await english.getBounds();
        await english.click();
        await driver.delayMs(220); // 分段控件的160ms选中动画完成。
        const chineseEnglish: Component = await driver.findComponent(ON.id('settings.language.1'));
        expect(await chineseEnglish.getText()).assertEqual('Simplified Chinese');
        const afterEnglish: Component | null = await visibleSetting(driver, 'settings.language.2');
        if (afterEnglish === null) { throw new Error('切为英文后语言卡不再位于原视口'); }
        const englishBounds: Rect = await afterEnglish.getBounds();
        const englishDelta: number = englishBounds.top - before.top;
        const englishRowHeight: number = Math.max(before.bottom - before.top,
          englishBounds.bottom - englishBounds.top);
        if (Math.abs(englishDelta) > englishRowHeight) {
          const viewport: Rect = await (await driver.findComponent(ON.id('settings_scroll'))).getBounds();
          throw new Error('中→英语言锚点位移超过一个实测分段行高：delta=' + englishDelta.toString() +
            ' rowHeight=' + englishRowHeight.toString() +
            ' before=' + boundsText(before) + ' after=' + boundsText(englishBounds) +
            ' scrollViewport=' + boundsText(viewport));
        }
        expect(await hasID(driver, 'settings_scroll')).assertTrue();

        await chineseEnglish.click();
        await driver.delayMs(220);
        const chineseChinese: Component = await driver.findComponent(ON.id('settings.language.1'));
        expect(await chineseChinese.getText()).assertEqual('简体中文');
        const afterChinese: Component | null = await visibleSetting(driver, 'settings.language.2');
        if (afterChinese === null) { throw new Error('切回中文后语言卡不再位于原视口'); }
        const chineseBounds: Rect = await afterChinese.getBounds();
        const chineseDelta: number = chineseBounds.top - before.top;
        const chineseRowHeight: number = Math.max(before.bottom - before.top,
          chineseBounds.bottom - chineseBounds.top);
        if (Math.abs(chineseDelta) > chineseRowHeight) {
          const viewport: Rect = await (await driver.findComponent(ON.id('settings_scroll'))).getBounds();
          throw new Error('英→中语言锚点位移超过一个实测分段行高：delta=' + chineseDelta.toString() +
            ' rowHeight=' + chineseRowHeight.toString() +
            ' before=' + boundsText(before) + ' after=' + boundsText(chineseBounds) +
            ' scrollViewport=' + boundsText(viewport));
        }
        console.info('SettingsLanguageAnchor before=' + boundsText(before) +
          ' english=' + boundsText(englishBounds) + ' delta=' + englishDelta.toString() +
          ' rowHeight=' + englishRowHeight.toString() + ' chinese=' + boundsText(chineseBounds) +
          ' delta=' + chineseDelta.toString() + ' rowHeight=' + chineseRowHeight.toString());
      } catch (e) {
        throw await withFailureEvidence(driver, 'language-scroll', e);
      } finally {
        await AbilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: BUNDLE_NAME,
          abilityName: 'EntryAbility',
          parameters: { 'reviewDemo': true, 'privacyConsentAcceptedForTesting': true }
        });
      }
    });
  });

  // 单独显式授权后才注册真实输入用例；默认设备套件只有上述三个无 IME 用例。
  if (AbilityDelegatorRegistry.getArguments().parameters['runSettingsKeyboardInput'] === 'true') {
    describe('SettingsKeyboardInputDevice', () => {
      it('physical_keyboard_input_drafts_survive_real_phone_sidebar_rotation', 0, async () => {
        const driver: Driver = await launchReviewDemo();
        const originalRotation: DisplayRotation = await driver.getDisplayRotation();
        const customURL: string = 'https://example.org/review-only-feed.json';
        try {
          await driver.setDisplayRotation(DisplayRotation.ROTATION_0);
          await driver.delayMs(1000);
          await requireBranch(driver, 'phone');
          await openSettings(driver);

          const editReminder: Component = await scrollToSetting(driver, 'settings_pre_class_notification_edit');
          await editReminder.click();
          await enterDraft(driver, 'settings_pre_class_minutes_0', '17');
          await driver.pressBack();
          await enterDraft(driver, 'settings_custom_deadline_url', customURL);
          await driver.pressBack(); // 仅草稿，不触发保存或网络请求。
          const policyLink: Component = await scrollToSetting(driver, 'settings_privacy_policy');
          await policyLink.click();
          await driver.delayMs(350);
          expect(await policyVisible(driver)).assertTrue();

          await driver.setDisplayRotation(DisplayRotation.ROTATION_90);
          await driver.delayMs(1100);
          expect(await policyVisible(driver)).assertTrue();
          await (await driver.findComponent(ON.id('privacy_policy_close'))).click();
          await driver.delayMs(400);
          await requireBranch(driver, 'sidebar');
          expect(await (await scrollToSetting(driver, 'settings_custom_deadline_url')).getOriginalText())
            .assertEqual(customURL);
          expect(await (await scrollToSetting(driver, 'settings_pre_class_minutes_0')).getOriginalText())
            .assertEqual('17');
        } catch (e) {
          throw await withFailureEvidence(driver, 'keyboard-draft-rotation', e);
        } finally {
          await driver.setDisplayRotation(originalRotation);
        }
      });
    });
  }
}
