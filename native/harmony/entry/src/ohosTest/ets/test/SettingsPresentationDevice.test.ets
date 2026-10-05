// 常规用例仅 review-demo 本地 UI：不聚焦输入框、不保存自定义 URL 或请求网络。
// 真实键盘输入用例只在测试运行参数 runSettingsKeyboardInput=true 时注册，
// 不能自动同意第三方输入法协议。
// 第二项必须在旋转后确实跨 phone_navigation ↔ root_sidebar_layout，不能只按屏幕总宽推断。
import { describe, it, expect } from '@ohos/hypium';
import { Component, DisplayRotation, Driver, ON, Point, Rect } from '@ohos.UiTest';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { display, FrameNode, UIContext, window } from '@kit.ArkUI';

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

async function targetWindow(): Promise<window.Window> {
  // getAppContext() 是测试进程的 ApplicationContext，不能用于取得目标 UIAbility
  // 的顶层窗口（真机报 Get top window failed）。AbilityDelegator 官方接口返回
  // 本进程正在显示的 UIAbility，再用其 UIAbilityContext 查询真实 app window。
  const delegator = AbilityDelegatorRegistry.getAbilityDelegator();
  const targetAbility = await delegator.getCurrentTopAbility();
  return window.getLastWindow(targetAbility.context);
}

async function targetUIContext(): Promise<UIContext> {
  return (await targetWindow()).getUIContext();
}

function attachedNode(ui: UIContext, id: string): FrameNode | null {
  try {
    return ui.getAttachedFrameNodeById(id);
  } catch (e) {
    return null;
  }
}

async function waitForSameWindowToReturn(mainWindow: window.Window, driver: Driver): Promise<UIContext> {
  const deadline: number = Date.now() + 3000;
  let lastReason: string = 'window has not regained focus';
  while (Date.now() < deadline) {
    try {
      let candidate: window.Window = mainWindow;
      try {
        // 常规路径重新取前台 owner；Home 刚结束时该 API 会暂时失败，
        // 此时保留已验证的旧 Window，不能把失败解释成“遮罩不存在”。
        candidate = await targetWindow();
      } catch (e) {
        candidate = mainWindow;
      }
      if (candidate.isFocused() && await hasID(driver, 'settings_scroll')) {
        // Home 后 getCurrentTopAbility() 在测试进程可能仍报错；复用 Home 前
        // 官方 API 返回的真实 Window owner，只在它重新聚焦且Scroll真挂载后
        // 读取它的新 UIContext。FrameNode 获取异常不能当作“遮罩不存在”。
        const ui: UIContext = candidate.getUIContext();
        const scroll: FrameNode | null = ui.getAttachedFrameNodeById('settings_scroll');
        if (scroll !== null && scroll.getMeasuredSize().width > 0) { return ui; }
        lastReason = 'focused window has no measured settings_scroll';
      }
    } catch (e) {
      lastReason = e instanceof Error ? e.message : String(e);
    }
    await nextRenderSample();
  }
  throw new Error('返回前台后真实原窗口未就绪：' + lastReason);
}

async function nextRenderSample(): Promise<void> {
  await new Promise<void>((resolve): void => {
    setTimeout((): void => resolve(), 16);
  });
}

class LanguageBlurObservation {
  sawCover: boolean = false;
  coveredWholeApp: boolean = false;
  sawTargetUnderCover: boolean = false;
  stableTargetSamples: number = 0;
  finishedAfterMs: number = -1;
}

class LanguageBlurCapture {
  private pending: Promise<boolean> | null = null;
  start(driver: Driver, path: string): void {
    this.pending = driver.screenCap(path).catch((): boolean => false);
  }
  async finish(): Promise<boolean> {
    const pending: Promise<boolean> | null = this.pending;
    return pending !== null ? await pending : false;
  }
}

async function observeLanguageBlur(ui: UIContext, targetIndex: number, startedAt: number,
  deadlineMs: number, captureOnce: (() => void) | null = null): Promise<LanguageBlurObservation> {
  const observed: LanguageBlurObservation = new LanguageBlurObservation();
  let lastCardY: number = Number.NaN;
  let lastOptionY: number = Number.NaN;
  let captureStarted: boolean = false;
  while (Date.now() - startedAt < deadlineMs) {
    const overlay: FrameNode | null = attachedNode(ui, 'language_transition_overlay');
    const scroll: FrameNode | null = attachedNode(ui, 'settings_scroll');
    if (overlay !== null) {
      observed.sawCover = true;
      if (scroll !== null) {
        const coverSize = overlay.getMeasuredSize();
        const scrollSize = scroll.getMeasuredSize();
        // 设置Scroll本身覆盖根内容，不把系统状态栏猜成app内容尺寸。
        observed.coveredWholeApp = observed.coveredWholeApp ||
          coverSize.width >= scrollSize.width - 1 && coverSize.height >= scrollSize.height - 1;
      }
      const thumb: FrameNode | null = attachedNode(ui,
        'settings.language.thumb.' + targetIndex.toString() + '.active');
      const card: FrameNode | null = attachedNode(ui, 'settings_language_surface');
      const option: FrameNode | null = attachedNode(ui, 'settings.language.' + targetIndex.toString());
      if (thumb !== null && card !== null && option !== null && option.getMeasuredSize().width > 0) {
        observed.sawTargetUnderCover = true;
        if (captureOnce !== null && !captureStarted) {
          captureStarted = true;
          captureOnce(); // concurrent SDK evidence must not replace frame sampling
        }
        const cardY: number = card.getPositionToWindow().y;
        const optionY: number = option.getPositionToWindow().y;
        observed.stableTargetSamples = Number.isFinite(lastCardY) &&
          Math.abs(cardY - lastCardY) <= 1 && Math.abs(optionY - lastOptionY) <= 1 ?
          observed.stableTargetSamples + 1 : 0;
        lastCardY = cardY;
        lastOptionY = optionY;
      }
    } else if (observed.sawCover) {
      observed.finishedAfterMs = Date.now() - startedAt;
      return observed;
    }
    await nextRenderSample();
  }
  return observed;
}

async function observeLanguageAnchorUntilStable(driver: Driver, id: string,
  translatedID: string, translatedText: string, before: Rect): Promise<Rect> {
  const deadline: number = Date.now() + 1800;
  let previousTop: number | null = null;
  let stableSamples: number = 0;
  let sampleCount: number = 0;
  let maximumDelta: number = 0;
  while (Date.now() < deadline) {
    const target: Component | null = await visibleSetting(driver, id);
    if (target === null) { throw new Error('语言切换期间选项离开设置视口'); }
    const bounds: Rect = await target.getBounds();
    const rowHeight: number = Math.max(before.bottom - before.top, bounds.bottom - bounds.top);
    const delta: number = Math.abs(bounds.top - before.top);
    maximumDelta = Math.max(maximumDelta, delta);
    sampleCount++;
    if (delta > rowHeight) {
      throw new Error('语言切换中间样本位置越过一个实测行高：sample=' + sampleCount.toString() +
        ' delta=' + delta.toString() + ' rowHeight=' + rowHeight.toString() +
        ' before=' + boundsText(before) + ' observed=' + boundsText(bounds));
    }
    const translated: Component = await driver.findComponent(ON.id(translatedID));
    if (await translated.getText() === translatedText) {
      stableSamples = previousTop !== null && Math.abs(bounds.top - previousTop) <= 1 ?
        stableSamples + 1 : 0;
      if (stableSamples >= 1) {
        console.info('SettingsLanguageMotion observedSamples=' + sampleCount.toString() +
          ' maximumDelta=' + maximumDelta.toString() + ' settled=' + boundsText(bounds));
        return bounds;
      }
    } else {
      stableSamples = 0;
    }
    previousTop = bounds.top;
    await driver.delayMs(16); // 按实际文字与位置收敛轮询，不用固定动画等待时间。
  }
  throw new Error('语言文字与位置未在有界时间内稳定：samples=' + sampleCount.toString() +
    ' maximumDelta=' + maximumDelta.toString());
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
        const englishBounds: Rect = await observeLanguageAnchorUntilStable(
          driver, 'settings.language.2', 'settings.language.1', 'Simplified Chinese', before);
        const chineseEnglish: Component = await driver.findComponent(ON.id('settings.language.1'));
        expect(await chineseEnglish.getText()).assertEqual('Simplified Chinese');
        const afterEnglish: Component | null = await visibleSetting(driver, 'settings.language.2');
        if (afterEnglish === null) { throw new Error('切为英文后语言卡不再位于原视口'); }
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
        const chineseBounds: Rect = await observeLanguageAnchorUntilStable(
          driver, 'settings.language.2', 'settings.language.1', '简体中文', before);
        const chineseChinese: Component = await driver.findComponent(ON.id('settings.language.1'));
        expect(await chineseChinese.getText()).assertEqual('简体中文');
        const afterChinese: Component | null = await visibleSetting(driver, 'settings.language.2');
        if (afterChinese === null) { throw new Error('切回中文后语言卡不再位于原视口'); }
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

    it('language_blur_covers_app_until_target_layout_then_finishes_before_deadline', 0, async () => {
      const driver: Driver = await launchReviewDemo(true);
      try {
        await openSettings(driver);
        const english: Component = await scrollToSetting(driver, 'settings.language.2');
        const rect: Rect = await english.getBounds();
        const ui: UIContext = await targetUIContext();
        const startedAt: number = Date.now();
        const tap: Promise<void> = driver.click(Math.round((rect.left + rect.right) / 2),
          Math.round((rect.top + rect.bottom) / 2));
        // 直接读取目标window的真实FrameNode；UiTest.click的完成时机不是中间帧，
        // 因而观察与注入手势并行，不用固定sleep冒充动画验证。
        const capture: LanguageBlurCapture = new LanguageBlurCapture();
        const captureRequested: boolean = AbilityDelegatorRegistry.getArguments()
          .parameters['captureLanguageBlurForTesting'] === 'true';
        const capturePath: string = AbilityDelegatorRegistry.getAbilityDelegator().getAppContext()
          .filesDir + '/settings-language-blur-material.png';
        const observed: LanguageBlurObservation = await observeLanguageBlur(ui, 2, startedAt, 1450,
          captureRequested ? (): void => { capture.start(driver, capturePath); } : null);
        await tap;
        if (captureRequested) {
          const captured: boolean = await capture.finish();
          console.info('HarmonyLanguageBlurMaterial captured=' + captured.toString() + ' path=' + capturePath);
          expect(captured).assertTrue();
        }
        if (!observed.sawCover || !observed.coveredWholeApp || !observed.sawTargetUnderCover ||
          observed.stableTargetSamples < 1 || observed.finishedAfterMs < 0 ||
          observed.finishedAfterMs >= 1450) {
          throw new Error('语言遮罩/目标布局未按中间帧结束：cover=' + observed.sawCover.toString() +
            ' whole=' + observed.coveredWholeApp.toString() +
            ' target=' + observed.sawTargetUnderCover.toString() +
            ' stable=' + observed.stableTargetSamples.toString() +
            ' elapsed=' + observed.finishedAfterMs.toString());
        }
        expect(await (await driver.findComponent(ON.id('settings.language.1'))).getText())
          .assertEqual('Simplified Chinese');
        expect(attachedNode(ui, 'settings.language.thumb.2.active') !== null).assertTrue();
        console.info('HarmonyLanguageBlur covered=true target=true stable=' +
          observed.stableTargetSamples.toString() + ' elapsedMs=' + observed.finishedAfterMs.toString());
      } catch (e) {
        throw await withFailureEvidence(driver, 'language-blur-layout', e);
      } finally {
        await AbilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: BUNDLE_NAME,
          abilityName: 'EntryAbility',
          parameters: { 'reviewDemo': true, 'privacyConsentAcceptedForTesting': true }
        });
      }
    });

    it('language_blur_background_cancels_old_owner_without_losing_last_choice', 0, async () => {
      const driver: Driver = await launchReviewDemo(true);
      try {
        await openSettings(driver);
        const english: Component = await scrollToSetting(driver, 'settings.language.2');
        const rect: Rect = await english.getBounds();
        const mainWindow: window.Window = await targetWindow();
        const ui: UIContext = mainWindow.getUIContext();
        const tap: Promise<void> = driver.click(Math.round((rect.left + rect.right) / 2),
          Math.round((rect.top + rect.bottom) / 2));
        const startedAt: number = Date.now();
        let coverSeen: boolean = false;
        while (Date.now() - startedAt < 700) {
          if (attachedNode(ui, 'language_transition_overlay') !== null) {
            coverSeen = true;
            break;
          }
          await nextRenderSample();
        }
        if (!coverSeen) { throw new Error('背景测试未观察到切换遮罩，不能冒称旧owner清理'); }
        // 旧owner仍持遮罩时立即退到后台；等待 click Promise 会把测试变成
        // “动画已经结束再退后台”，无法验证窗口事件取消路径。
        if (attachedNode(ui, 'language_transition_overlay') === null) {
          throw new Error('按 Home 前遮罩已消失，未测到中途后台取消');
        }
        await driver.pressHome();
        await tap;
        let didBackground: boolean = false;
        const backgroundDeadline: number = Date.now() + 1000;
        while (Date.now() < backgroundDeadline) {
          try {
            if (!mainWindow.isFocused()) { didBackground = true; break; }
          } catch (e) {
            // 窗口正隐藏，下一帧再读；异常不等于已经进入后台。
          }
          await nextRenderSample();
        }
        if (!didBackground) { throw new Error('Home 后原窗口始终聚焦，不能冒称后台清理'); }
        await AbilityDelegatorRegistry.getAbilityDelegator().startAbility({
          bundleName: BUNDLE_NAME, abilityName: 'EntryAbility'
        });
        const resumedUI: UIContext = await waitForSameWindowToReturn(mainWindow, driver);
        const recoveryDeadline: number = Date.now() + 1300;
        while (Date.now() < recoveryDeadline) {
          // 已验证原窗口重新聚焦且settings_scroll实测挂载；这里使用严格
          // FrameNode 读取，不能将API异常伪装成 overlay=null。
          if (resumedUI.getAttachedFrameNodeById('language_transition_overlay') === null &&
            resumedUI.getAttachedFrameNodeById('settings.language.thumb.2.active') !== null) {
            expect(await (await driver.findComponent(ON.id('settings.language.1'))).getText())
              .assertEqual('Simplified Chinese');
            return;
          }
          await nextRenderSample();
        }
        throw new Error('返回前台后旧语言遮罩未清理，或最后一次语言选择被吞掉');
      } catch (e) {
        throw await withFailureEvidence(driver, 'language-blur-background', e);
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
