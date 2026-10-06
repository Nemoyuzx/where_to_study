import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
import {transformSync} from 'esbuild'

const normalizeSource = source => source.replace(/\r\n?/g, '\n')
const read = path => normalizeSource(readFileSync(new URL('../native/harmony/entry/src/main/ets/' + path, import.meta.url), 'utf8'))
const settings = read('view/SettingsView.ets')
const root = read('view/RootView.ets')
const localization = read('common/AppLocalization.ets')
const picker = read('view/LanguagePickerView.ets')
const sessionSource = read('view/SettingsSession.ets')

function transitionFixture({reducedMotion = false, rootSource = root, session = sessionSource} = {}) {
  const root = normalizeSource(rootSource)
  const start = root.indexOf('  private reduceLanguageMotion(')
  const end = root.indexOf('  @Builder\n  languageCompletionMark(')
  assert.ok(start >= 0 && end > start, 'load the production transition coordinator')
  const callbackStart = root.indexOf('class LanguageLayoutFrameCallback extends FrameCallback')
  const callbackEnd = root.indexOf('@ComponentV2', callbackStart)
  const settingsSession = normalizeSource(session).replace(/^import[^\n]+\n/gm, '')
    .replace(/@ObservedV2\s*/g, '').replace(/@Trace\s+/g, '').replace('export class SettingsSession', 'class SettingsSession')
  const source = root.slice(callbackStart, callbackEnd) + settingsSession +
    '\nclass TransitionHarness {\n' + root.slice(start, end) +
    '\n}\nglobalThis.TransitionHarness = TransitionHarness; globalThis.SettingsSession = SettingsSession;'
  const timers = new Map()
  const frames = []
  const animations = []
  const writes = []
  let sequence = 0
  let language = 'zh'
  const card = {x: 20, y: 100, width: 360, height: 100}
  const target = {x: 36, y: 142, width: 280, height: 18}
  const otherCard = {x: 20, y: 250, width: 360, height: 200}
  let targetPresent = true
  let acknowledged = true
  const node = geometry => ({
    getPositionToWindow: () => ({x: geometry.x, y: geometry.y}),
    getMeasuredSize: () => ({width: geometry.width, height: geometry.height}),
    getChildrenCount: () => 0,
    getChild: () => null,
  })
  const context = {
    PreferencesStore:class{},
    FrameCallback: class {},
    AppSection: {settings: 'settings'},
    AppLanguageInfo: {normalize: value => value, systemLanguage: () => 'synthetic-system', all: ['zh', 'en', 'ar']},
    Curve: {EaseOut: 'ease-out'},
    settings: {display: {ANIMATOR_DURATION_SCALE: 'animator', TRANSITION_ANIMATION_SCALE: 'transition'},
      getValueSync: () => reducedMotion ? '0' : '1'},
    setTimeout: (work, delay) => {const id = ++sequence; timers.set(id, {work, delay}); return id},
    clearTimeout: id => timers.delete(id),
  }
  vm.runInNewContext(transformSync(source, {loader: 'ts', target: 'es2022'}).code, context)
  const owner = new context.TransitionHarness()
  Object.assign(owner, {
    currentSection: 'settings', languageTransitionEpoch: 0, languageAppliedRequestEpoch: 0,
    languageTransitionTarget: null, languageTransitionTimer: -1,
    languageOverlayVisible: false, languageOverlayOpacity: 0, languageOverlayFading: false,
    navigationAvoidanceActive: true, qmPlusSession: {loginForeground: true},
    settingsSession: new context.SettingsSession(),
    model: {systemLanguageID: 'synthetic-system', languageSetting: () => language,
      languageChangeReady: target => acknowledged && language === target,
      setLanguageSetting: value => {writes.push(value); language = value; return Promise.resolve()}},
    getUIContext: () => ({
      getHostContext: () => ({}),
      postFrameCallback: callback => frames.push(callback),
      animateTo: (options, work) => {animations.push(options); work()},
      getAttachedFrameNodeById: id => id === 'settings_language_surface' ? node(card) :
        targetPresent && id === 'settings.language.current.target.' + language ? node(target) :
        id === 'language.main.ui.' + language ? {...node(card), getChildrenCount:()=>2, getChild:index=>node(index===0?target:otherCard)} : null,
    }),
  })
  owner.resetLanguageLayoutSamples()
  return {
    owner, card, target, otherCard, timers, frames, animations, writes,
    get language() {return language},
    setTargetPresent: value => {targetPresent = value},
    setAcknowledged: value => {acknowledged = value},
    nextFrame: () => {assert.ok(frames.length > 0); frames.shift().onFrame(0)},
    finish: duration => {
      const animation = animations.find(item => item.duration === duration && !item.finished)
      assert.ok(animation, 'production animation exists: ' + duration)
      animation.finished = true
      animation.onFinish()
    },
    applyRequest: () => {
      const selected = owner.settingsSession.takeLanguageRequest()
      if (selected !== null) owner.model.setLanguageSetting(selected)
    },
    deadline: delay => {
      const entry = [...timers].find(([, timer]) => timer.delay === delay)
      assert.ok(entry, 'production deadline exists: ' + delay)
      timers.delete(entry[0])
      entry[1].work()
    },
    completeMark() {
      this.nextFrame()
      this.finish(reducedMotion ? 0 : 210)
      this.finish(reducedMotion ? 0 : 150)
      this.deadline(100)
      this.finish(reducedMotion ? 0 : 190)
    },
  }
}

function applyCoveredSelection(fixture, language = 'en') {
  fixture.owner.beginLanguageTransition(language)
  fixture.nextFrame()
  fixture.finish(110)
  fixture.applyRequest()
}

test('CRLF production sources execute the same transition coordinator and preference handoff', () => {
  const fixture = transitionFixture({rootSource: root.replaceAll('\n', '\r\n'), session: sessionSource.replaceAll('\n', '\r\n')})
  applyCoveredSelection(fixture)
  assert.equal(fixture.language, 'en')
  assert.deepEqual(fixture.writes, ['en'])
  assert.equal(fixture.owner.languageOverlayVisible, true)
  fixture.owner.cancelLanguageTransition(false)
})

test('Harmony language picker keeps its owner above settings without animating the translated page', () => {
  const surface = settings.slice(settings.indexOf('  languageSurface() {'), settings.indexOf('  removedCoursesSurface() {'))
  const select = settings.slice(settings.indexOf('  private selectLanguageAtCurrentPosition('),
    settings.indexOf('  private preserveLanguageAnchorAfterLayout('))
  assert.match(root, /if \(this\.settingsSession\.showingLanguagePicker\) \{\s*LanguagePickerView\(/)
  assert.match(root, /\.zIndex\(115\)/)
  assert.match(surface, /\.id\('settings\.language\.open'\)/)
  assert.match(surface, /this\.session\.showingLanguagePicker = true/)
  assert.match(settings, /onLanguagePickerSelection\(monitor: IMonitor\): void/)
  assert.match(select, /new SettingsLanguageAnchor\(revision, this\.languageCardGlobalY, offset\)/)
  assert.doesNotMatch(select, /animateTo\(/)
  assert.doesNotMatch(surface, /languageSegments\(\)/)
  assert.doesNotMatch(surface, /segmentedOptions\(/)
})

test('Harmony phone navigation keeps its animation on background/icon, not its text geometry', () => {
  const navigation = root.slice(root.indexOf('  phoneNavigationItem(section: AppSection) {'),
    root.indexOf('  sectionView(section: AppSection) {'))
  assert.ok(navigation.length > 0)
  assert.match(navigation, /Stack\(\) \{[\s\S]*?Column\(\) \{\}[\s\S]*?\.backgroundColor\([\s\S]*?\.animation\(\{ duration: 160/)
  assert.match(navigation, /SymbolGlyph\([\s\S]*?\.fontColor\([\s\S]*?\.animation\(\{ duration: 160/)
  const label = navigation.slice(navigation.indexOf('Text(this.model.text(AppSectionInfo.title(section)))'))
  assert.ok(label.indexOf('.animation(') < 0 || label.indexOf('.animation(') > label.indexOf('.onClick('),
    'the translated label must not own a geometry animation')
})

test('Harmony native-language picker keeps one root owner and Arabic layout without reversing the calendar', () => {
  assert.match(localization, /AppLanguage\.system, AppLanguage\.simplifiedChinese, AppLanguage\.traditionalChinese/)
  assert.match(localization, /AppLanguage\.vietnamese, AppLanguage\.indonesian/)
  assert.match(localization, /isRightToLeft\(language: AppLanguage\): boolean \{\s*return language === AppLanguage\.arabic/)
  assert.match(root, /onSelect: \(language: AppLanguage\): void => \{ this\.beginLanguageTransition\(language\); \}/)
  assert.match(root, /\.direction\(this\.isRightToLeftUI\(\) \? Direction\.Rtl : Direction\.Ltr\)/)
  assert.match(root, /CalendarSectionView\([\s\S]*?\.direction\(Direction\.Ltr\)/)
  assert.match(picker, /\.id\('settings\.language\.option\.' \+ language\)/)
  assert.match(picker, /\.textDirection\(TextDirection\.AUTO\)/)
  assert.doesNotMatch(picker, /segmentedOptions/)
})

test('Harmony picker selection reaches the settings language request after the independent cover is laid out', () => {
  assert.match(settings, /onLanguagePickerSelection\(monitor: IMonitor\): void \{\s*if \(!this\.favoriteManagerOnly\) \{ this\.applyPendingLanguageRequest\(\); \}/)
  assert.match(settings, /const requested: AppLanguage \| null = this\.session\.takeLanguageRequest\(\);\s*if \(requested !== null\) \{ this\.selectLanguageAtCurrentPosition\(requested\); \}/)
  const select = settings.slice(settings.indexOf('  private selectLanguageAtCurrentPosition('),
    settings.indexOf('  private preserveLanguageAnchorAfterLayout('))
  assert.match(select, /void this\.model\.setLanguageSetting\(target\)/)
  const fixture = transitionFixture()
  fixture.owner.settingsSession.showingLanguagePicker = true
  fixture.owner.beginLanguageTransition('en')
  assert.equal(fixture.owner.languageOverlayVisible, true)
  assert.equal(fixture.owner.languageOverlayOpacity, 0)
  assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, '')
  fixture.nextFrame()
  assert.equal(fixture.owner.languageOverlayOpacity, 1)
  assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, '')
  fixture.finish(110)
  assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, 'en')
  assert.equal(fixture.owner.settingsSession.showingLanguagePicker, false)
  fixture.applyRequest()
  assert.equal(fixture.language, 'en')
  fixture.owner.cancelLanguageTransition(false)
})

test('Harmony production sampler waits through label and card height changes before fading', () => {
  const fixture = transitionFixture()
  applyCoveredSelection(fixture)
  for (const [cardHeight, targetHeight] of [[100, 18], [140, 36], [180, 54]]) {
    fixture.card.height = cardHeight
    fixture.target.height = targetHeight
    fixture.nextFrame()
    assert.equal(fixture.owner.languageStableFrames, 1)
    assert.equal(fixture.animations.some(item => item.duration === 190), false)
  }
  fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames, 2)
  fixture.nextFrame()
  assert.equal(fixture.owner.languageOverlayFading, true)
  assert.equal(fixture.animations.filter(item => item.duration === 190).length, 0, 'mark completes before the ready cover fades')
  fixture.completeMark()
  assert.equal(fixture.owner.languageOverlayVisible, false)
  assert.equal(fixture.timers.size, 0)
})

test('Harmony production sampler checks every card and target coordinate and size', () => {
  for (const part of ['card', 'target', 'otherCard']) {
    for (const field of ['x', 'y', 'width', 'height']) {
      const fixture = transitionFixture()
      applyCoveredSelection(fixture)
      fixture.nextFrame()
      fixture[part][field] += 10
      fixture.nextFrame()
      assert.equal(fixture.owner.languageStableFrames, 1, `${part}.${field} starts a fresh geometry baseline`)
      assert.equal(fixture.owner.languageOverlayFading, false)
      fixture.owner.cancelLanguageTransition(false)
    }
  }
})

test('Harmony stable geometry cannot claim language completion before native side-effect acknowledgements',()=>{
  const fixture=transitionFixture()
  fixture.setAcknowledged(false)
  applyCoveredSelection(fixture)
  for(let index=0;index<8;index++)fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames,0)
  assert.equal(fixture.owner.languageOverlayCompleted,false)
  fixture.setAcknowledged(true)
  fixture.nextFrame();fixture.nextFrame()
  assert.equal(fixture.owner.languageOverlayCompleted,false)
  fixture.nextFrame()
  assert.equal(fixture.owner.languageOverlayCompleted,true)
  fixture.completeMark()
  assert.equal(fixture.owner.languageOverlayVisible,false)
})

test('Harmony missing or invalid target measurements interrupt consecutive stability samples', () => {
  const fixture = transitionFixture()
  applyCoveredSelection(fixture)
  fixture.nextFrame()
  fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames, 2)
  fixture.setTargetPresent(false)
  fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames, 0)
  fixture.setTargetPresent(true)
  fixture.target.height = 0
  fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames, 0)
  fixture.target.height = 18
  fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames, 1, 'a restored target needs a new baseline')
  fixture.nextFrame()
  assert.equal(fixture.owner.languageStableFrames, 2)
  assert.equal(fixture.owner.languageOverlayFading, false)
  fixture.owner.cancelLanguageTransition(false)
})

test('Harmony no-target and unapplied-language deadlines clean the cover without claiming ready fade', () => {
  for (const mode of ['missing-target', 'unapplied-language', 'missing-frame']) {
    const fixture = transitionFixture()
    fixture.owner.beginLanguageTransition('en')
    if (mode !== 'missing-frame') {
      fixture.nextFrame()
      fixture.finish(110)
      if (mode === 'missing-target') {fixture.applyRequest(); fixture.setTargetPresent(false)}
      fixture.nextFrame()
    }
    assert.equal(fixture.owner.languageOverlayFading, false)
    fixture.deadline(5000)
    assert.equal(fixture.animations.some(item => item.duration === 190), false)
    assert.equal(fixture.owner.languageOverlayVisible, false)
    assert.equal(fixture.owner.languageTransitionTarget, null)
    assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, '')
    assert.equal(fixture.language, 'en', 'timeout preserves the accepted choice')
    assert.equal(fixture.timers.size, 0)
    while (fixture.frames.length > 0) fixture.nextFrame()
    assert.equal(fixture.owner.languageOverlayVisible, false, 'retired frames cannot restore a mask')
  }
})

test('Harmony rapid replacement and returning to current language retire every previous callback', () => {
  const fixture = transitionFixture()
  fixture.owner.beginLanguageTransition('en')
  fixture.nextFrame()
  fixture.owner.beginLanguageTransition('ar')
  fixture.finish(110)
  assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, '')
  fixture.nextFrame()
  fixture.finish(110)
  assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, 'ar')
  fixture.owner.beginLanguageTransition('zh')
  assert.equal(fixture.owner.languageOverlayVisible, false)
  assert.equal(fixture.owner.settingsSession.requestedLanguageRawValue, '')
  assert.equal(fixture.timers.size, 0)
  while (fixture.frames.length > 0) fixture.nextFrame()
  assert.equal(fixture.language, 'zh')
  assert.equal(fixture.writes.length, 0)
})

test('Harmony cancellation preserves the last accepted choice and retires frame, timer, and window owners', () => {
  const disappear = root.slice(root.indexOf('  aboutToDisappear(): void'), root.indexOf('  onPageShow(): void'))
  const windowOwner = root.slice(root.indexOf('  private attachPhoneNavigationAvoidance('), root.indexOf('  private reduceLanguageMotion('))
  const navigation = root.slice(root.indexOf('  selectSection('), root.indexOf('  private setSettingsPrivacyPolicyVisible('))
  assert.match(disappear, /this\.cancelLanguageTransition\(true\)/)
  assert.match(disappear, /this\.detachPhoneNavigationAvoidance\(\)/)
  assert.match(windowOwner, /WINDOW_INACTIVE[\s\S]*?WINDOW_HIDDEN[\s\S]*?this\.cancelLanguageTransition\(true\)/)
  assert.match(windowOwner, /\.off\('windowEvent', this\.qmWindowListener\)/)
  assert.match(navigation, /section !== AppSection\.settings && this\.languageTransitionTarget !== null[\s\S]*?this\.cancelLanguageTransition\(true\)/)
  const fixture = transitionFixture()
  fixture.owner.beginLanguageTransition('en')
  fixture.owner.beginLanguageTransition('ar')
  fixture.owner.cancelLanguageTransition(true)
  while (fixture.frames.length > 0) fixture.nextFrame()
  assert.equal(fixture.language, 'ar')
  assert.deepEqual(fixture.writes, ['ar'])
  assert.equal(fixture.owner.languageOverlayVisible, false)
  assert.equal(fixture.timers.size, 0)
})

test('Harmony reduced motion retains acknowledgements and completion while every animation has zero duration', () => {
  const fixture = transitionFixture({reducedMotion: true})
  fixture.owner.beginLanguageTransition('en')
  fixture.nextFrame()
  fixture.finish(0)
  fixture.applyRequest()
  fixture.nextFrame(); fixture.nextFrame(); fixture.nextFrame()
  assert.equal(fixture.owner.languageOverlayCompleted,true)
  fixture.completeMark()
  assert.equal(fixture.language, 'en')
  assert.equal(fixture.owner.languageOverlayVisible, false)
  assert.ok(fixture.animations.every(animation=>animation.duration===0))
  assert.equal(fixture.timers.size, 0)
})

test('Harmony duplicate pending choices keep one frame and deadline, and a retired deadline cannot replace a newer choice', () => {
  const fixture = transitionFixture()
  fixture.owner.beginLanguageTransition('en')
  const oldDeadline = [...fixture.timers.values()][0].work
  for (let i = 0; i < 20; i++) fixture.owner.beginLanguageTransition('en')
  assert.equal(fixture.frames.length, 1)
  assert.equal(fixture.timers.size, 1)
  fixture.owner.beginLanguageTransition('ar')
  oldDeadline()
  assert.equal(fixture.owner.languageTransitionTarget, 'ar')
  assert.equal(fixture.owner.languageOverlayVisible, true)
  assert.equal(fixture.writes.length, 0)
  assert.equal(fixture.timers.size, 1)
  fixture.owner.cancelLanguageTransition(true)
  assert.equal(fixture.language, 'ar')
  assert.equal(fixture.timers.size, 0)
})

test('Harmony a lost fade completion is bounded and its late completion cannot revive the overlay', () => {
  const fixture = transitionFixture()
  applyCoveredSelection(fixture)
  fixture.nextFrame()
  fixture.nextFrame()
  fixture.nextFrame()
  assert.equal(fixture.owner.languageOverlayFading, true)
  fixture.deadline(1100)
  assert.equal(fixture.owner.languageOverlayVisible, false)
  assert.equal(fixture.timers.size, 0)
  assert.deepEqual(fixture.writes, ['en'])
  fixture.nextFrame() // the retired completion callback cannot revive the cover
  assert.equal(fixture.owner.languageOverlayVisible, false)
  assert.equal(fixture.timers.size, 0)
  assert.deepEqual(fixture.writes, ['en'])
})
