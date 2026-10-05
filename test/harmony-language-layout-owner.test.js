import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
import { transformSync } from 'esbuild'

const viewRoot = '../native/harmony/entry/src/main/ets/view/'
const read = file => readFileSync(new URL(`${viewRoot}${file}`, import.meta.url), 'utf8')
const root = read('RootView.ets')
const session = read('SettingsSession.ets')
const settingsView = read('SettingsView.ets')

function between(source, start, end) {
  const first = source.indexOf(start)
  const last = source.indexOf(end, first)
  assert.ok(first >= 0 && last > first, `production method boundary: ${start}`)
  return source.slice(first, last)
}

// Framework decorators are removed, but all coordinator and request-consumer
// method bodies and field initializers below execute directly from production.
const production = [
  between(root, 'class LanguageLayoutFrameCallback extends FrameCallback', '@ComponentV2'),
  session.replace(/^import[^\n]*\n/gm, '').replace(/@ObservedV2\s*/g, '')
    .replace(/@Trace\s+/g, '').replace('export class SettingsSession', 'class SettingsSession'),
  'class LayoutOwner {',
  between(root, '  @Local languageOverlayVisible:', '  private sidebarWidth(').replace(/@Local\s+/g, ''),
  between(root, '  aboutToDisappear(): void', '  onPageShow(): void'),
  between(root, '  private attachPhoneNavigationAvoidance(', '  private reduceLanguageMotion('),
  between(root, '  private reduceLanguageMotion(', '  private visibleBottomInsetVp('),
  '}',
  'class RequestConsumer {',
  between(settingsView, '  private applyRequestedLanguageChange(', '  aboutToDisappear(): void'),
  '}',
  'globalThis.LayoutOwner = LayoutOwner; globalThis.SettingsSession = SettingsSession; globalThis.RequestConsumer = RequestConsumer;',
].join('\n')
const executable = new vm.Script(transformSync(production, { loader: 'ts', target: 'es2022' }).code,
  { filename: 'harmony-production-language-coordinator.js' })

function fixture({ animatorScale = '1', transitionScale = '1' } = {}) {
  const languages = ['zh', 'en', 'ar']
  const timers = new Map()
  const frames = []
  const animations = []
  const writes = []
  const nodeLookups = []
  const listeners = new Map()
  const offEvents = []
  const present = { card: true, option: true, thumb: true }
  const card = { x: 20, y: 100, width: 360, height: 100 }
  const option = { x: 36, y: 142, width: 280, height: 18 }
  let sequence = 0
  let language = 'zh'
  let selectedThumb = null
  let framesAvailable = true
  let disposed = 0
  const mainWindow = {
    on: (name, callback) => listeners.set(name, callback),
    off: (name, callback) => {
      assert.equal(listeners.get(name), callback)
      listeners.delete(name)
      offEvents.push(name)
    },
  }
  const context = vm.createContext({
    FrameCallback: class {},
    AppSection: { settings: 'settings' },
    AppLanguageInfo: { all: languages, normalize: value => value, systemLanguage: () => 'fixture-system' },
    PhoneNavigationLayout: { minimumBottomClearanceVp: 28 },
    Curve: { EaseOut: 'ease-out' },
    window: {
      WindowEventType: { WINDOW_INACTIVE: 'inactive', WINDOW_HIDDEN: 'hidden' },
      AvoidAreaType: { TYPE_NAVIGATION_INDICATOR: 'navigation', TYPE_SYSTEM: 'system' },
      getLastWindow: () => Promise.resolve(mainWindow),
    },
    settings: {
      display: { ANIMATOR_DURATION_SCALE: 'animator', TRANSITION_ANIMATION_SCALE: 'transition' },
      getValueSync: (_context, name) => name === 'animator' ? animatorScale : transitionScale,
    },
    setTimeout: (work, delay) => { const id = ++sequence; timers.set(id, { work, delay }); return id },
    clearTimeout: id => timers.delete(id),
    clearInterval: () => { throw new Error('The fixture must not start the application refresh interval') },
  })
  executable.runInContext(context)
  const owner = new context.LayoutOwner()
  const model = {
    systemLanguageID: 'fixture-system',
    languageSetting: () => language,
    setLanguageSetting: value => { writes.push(value); language = value; return Promise.resolve() },
  }
  const node = geometry => ({
    getPositionToWindow: () => ({ x: geometry.x, y: geometry.y }),
    getMeasuredSize: () => ({ width: geometry.width, height: geometry.height }),
  })
  Object.assign(owner, {
    currentSection: 'settings', settingsSession: new context.SettingsSession(), model,
    querySession: { dispose: () => { disposed++ } },
    refreshPhoneNavigationBottomMargin: () => {},
    getUIContext: () => ({
      getHostContext: () => ({}),
      postFrameCallback: callback => {
        if (!framesAvailable) throw new Error('Synthetic detached UIContext')
        frames.push(callback)
      },
      animateTo: (options, work) => { animations.push(options); work() },
      getAttachedFrameNodeById: id => {
        nodeLookups.push(id)
        const index = languages.indexOf(owner.languageTransitionTarget)
        if (id === 'settings_language_surface') return present.card ? node(card) : null
        if (id === `settings.language.${index}`) return present.option ? node(option) : null
        const thumbIndex = languages.indexOf(selectedThumb ?? language)
        if (id === `settings.language.thumb.${thumbIndex}.active`) return present.thumb ? node(option) : null
        return null
      },
    }),
  })
  const consumer = new context.RequestConsumer()
  Object.assign(consumer, {
    session: owner.settingsSession, favoriteManagerOnly: false,
    selectLanguageAtCurrentPosition: target => { void model.setLanguageSetting(target) },
  })
  return {
    owner, card, option, present, timers, frames, animations, writes, nodeLookups, listeners, offEvents,
    get language() { return language },
    get disposed() { return disposed },
    setLanguage: value => { language = value },
    setSelectedThumb: value => { selectedThumb = value },
    detachFrames: () => { framesAvailable = false },
    applyRequest: () => consumer.applyRequestedLanguageChange(),
    nextFrame: () => { assert.ok(frames.length > 0, 'production queued a frame'); frames.shift().onFrame(0) },
    finish: animation => { assert.ok(animation?.onFinish, 'production queued this animation'); animation.onFinish() },
    deadline: delay => {
      const entry = [...timers].find(([, value]) => value.delay === delay)
      assert.ok(entry, `production deadline: ${delay}`)
      timers.delete(entry[0])
      entry[1].work()
    },
    drainRetiredFrames: () => {
      let remaining = 32
      while (frames.length > 0 && remaining-- > 0) frames.shift().onFrame(0)
      assert.equal(frames.length, 0, 'retired callbacks must not keep polling')
    },
    attachWindow: async () => {
      owner.navigationAvoidanceActive = true
      owner.attachPhoneNavigationAvoidance()
      await Promise.resolve()
      assert.ok(listeners.has('windowEvent'), 'production owns the window lifecycle listener')
    },
    windowEvent: event => { assert.ok(listeners.has('windowEvent')); listeners.get('windowEvent')(event) },
  }
}

function coverAndApply(value, target = 'en') {
  value.owner.beginLanguageTransition(target)
  assert.equal(value.owner.settingsSession.languageChangeTarget, null)
  value.nextFrame()
  const cover = value.animations.at(-1)
  assert.equal(cover.duration, 110)
  value.finish(cover)
  assert.equal(value.owner.settingsSession.languageChangeTarget, target)
  value.applyRequest()
  return cover
}

function assertNoFade(value) {
  assert.equal(value.owner.languageOverlayFading, false)
  assert.equal(value.animations.some(animation => animation.duration === 190), false)
}

function assertRetired(value, target) {
  assert.equal(value.owner.languageOverlayVisible, false)
  assert.equal(value.owner.languageOverlayOpacity, 0)
  assert.equal(value.owner.languageTransitionTarget, null)
  assert.equal(value.owner.settingsSession.languageChangeTarget, null)
  assert.equal(value.language, target)
  assert.equal(value.timers.size, 0)
  value.drainRetiredFrames()
  assert.equal(value.owner.languageOverlayVisible, false)
}

test('Production card and option geometry each reset stability and require three valid frames', () => {
  for (const part of ['card', 'option']) {
    for (const field of ['x', 'y', 'width', 'height']) {
      const value = fixture()
      coverAndApply(value)
      value.nextFrame()
      value.nextFrame()
      assert.equal(value.owner.languageStableFrames, 1)
      value[part][field] += 10
      value.nextFrame()
      assert.equal(value.owner.languageStableFrames, 0, `${part}.${field} changed`)
      assertNoFade(value)
      value.nextFrame()
      assert.equal(value.owner.languageStableFrames, 1)
      assertNoFade(value)
      value.nextFrame()
      assert.equal(value.owner.languageOverlayFading, true)
      assert.equal(value.animations.filter(animation => animation.duration === 190).length, 1)
      value.finish(value.animations.at(-1))
      assertRetired(value, 'en')
    }
  }
})

test('Missing nodes and zero-size frames invalidate the baseline before layout can become ready', () => {
  const invalidations = [
    ...['card', 'option', 'thumb'].map(part => ({ break: value => { value.present[part] = false }, restore: value => { value.present[part] = true }, name: `${part} missing` })),
    ...['card', 'option'].flatMap(part => ['width', 'height'].map(field => ({
      break: value => { value[part][field] = 0 },
      restore: value => { value[part][field] = part === 'card' ? (field === 'width' ? 360 : 100) : (field === 'width' ? 280 : 18) },
      name: `${part}.${field} zero`,
    }))),
  ]
  for (const invalidation of invalidations) {
    const value = fixture()
    coverAndApply(value)
    value.nextFrame()
    value.nextFrame()
    assert.equal(value.owner.languageStableFrames, 1)
    invalidation.break(value)
    value.nextFrame()
    assert.equal(value.owner.languageStableFrames, 0, invalidation.name)
    assertNoFade(value)
    invalidation.restore(value)
    value.nextFrame()
    assert.equal(value.owner.languageStableFrames, 0, `${invalidation.name}: restored geometry is a new baseline`)
    value.nextFrame()
    assertNoFade(value)
    value.nextFrame()
    assert.equal(value.owner.languageOverlayFading, true)
    value.owner.cancelLanguageTransition(false)
  }
})

test('Non-finite geometry, stale applied revisions, wrong language and stale active thumbs cannot report ready', () => {
  for (const part of ['card', 'option']) {
    for (const field of ['x', 'y', 'width', 'height']) {
      const value = fixture()
      value[part][field] = Number.NaN
      coverAndApply(value)
      for (let frame = 0; frame < 4; frame++) value.nextFrame()
      assertNoFade(value)
      value.owner.cancelLanguageTransition(false)
    }
  }
  const value = fixture()
  value.owner.beginLanguageTransition('en')
  value.nextFrame()
  value.finish(value.animations.at(-1))
  const revision = value.owner.languageTransitionEpoch
  value.setLanguage('en')
  for (const applied of [0, revision - 1, revision + 1]) {
    value.owner.settingsSession.languageChangeAppliedRevision = applied
    for (let frame = 0; frame < 3; frame++) value.nextFrame()
    assertNoFade(value)
  }
  assert.equal(value.nodeLookups.length, 0, 'geometry is not ready before the exact target revision is applied')
  value.owner.settingsSession.languageChangeAppliedRevision = revision
  value.setLanguage('ar')
  value.nextFrame()
  assertNoFade(value)
  value.setLanguage('en')
  value.setSelectedThumb('zh')
  for (let frame = 0; frame < 3; frame++) value.nextFrame()
  assertNoFade(value)
  value.setSelectedThumb('en')
  value.nextFrame()
  value.nextFrame()
  assertNoFade(value)
  value.nextFrame()
  assert.equal(value.owner.languageOverlayFading, true)
  assert.ok(value.nodeLookups.includes('settings.language.1'))
  assert.ok(value.nodeLookups.includes('settings.language.thumb.1.active'))
  value.owner.cancelLanguageTransition(false)
})

test('The 1600 ms deadline retires missing frames, unapplied revisions and missing geometry without a ready fade', () => {
  for (const mode of ['no-frame', 'unapplied', 'missing-option']) {
    const value = fixture()
    if (mode === 'no-frame') value.detachFrames()
    value.owner.beginLanguageTransition('en')
    let lateCover = null
    if (mode !== 'no-frame') {
      value.nextFrame()
      lateCover = value.animations.at(-1)
      value.finish(lateCover)
      if (mode === 'missing-option') { value.applyRequest(); value.present.option = false }
      value.nextFrame()
    }
    assertNoFade(value)
    value.deadline(1600)
    assertNoFade(value)
    assertRetired(value, 'en')
    assert.deepEqual(value.writes, ['en'], 'accepted intent is committed exactly once')
    value.applyRequest()
    if (lateCover) value.finish(lateCover)
    assert.deepEqual(value.writes, ['en'], 'late view/animation callbacks cannot duplicate the commit')
    assertRetired(value, 'en')
  }
})

test('Rapid replacement and reverse choice reject obsolete cover, timer and layout callbacks', () => {
  const value = fixture()
  value.owner.beginLanguageTransition('en')
  const staleDeadline = [...value.timers.values()][0].work
  value.nextFrame()
  const oldCover = value.animations.at(-1)
  value.owner.beginLanguageTransition('ar')
  value.finish(oldCover)
  assert.equal(value.owner.settingsSession.languageChangeTarget, null)
  value.nextFrame()
  value.finish(value.animations.at(-1))
  assert.equal(value.owner.settingsSession.languageChangeTarget, 'ar')
  value.owner.beginLanguageTransition('zh')
  value.applyRequest()
  staleDeadline()
  value.finish(oldCover)
  assertRetired(value, 'zh')
  assert.deepEqual(value.writes, [])

  const fading = fixture()
  coverAndApply(fading)
  for (let frame = 0; frame < 3; frame++) fading.nextFrame()
  const oldFade = fading.animations.at(-1)
  const oldCleanup = [...fading.timers.values()][0].work
  fading.owner.beginLanguageTransition('ar')
  fading.finish(oldFade)
  oldCleanup()
  assert.equal(fading.owner.languageOverlayVisible, true)
  assert.equal(fading.owner.languageTransitionTarget, 'ar')
  fading.owner.cancelLanguageTransition(true)
  assertRetired(fading, 'ar')
})

test('Production background and detach listeners commit intent and retire stale frames without restoring the cover', async () => {
  for (const event of ['inactive', 'hidden']) {
    const value = fixture()
    await value.attachWindow()
    value.owner.beginLanguageTransition('en')
    const staleDeadline = [...value.timers.values()][0].work
    value.nextFrame()
    const oldCover = value.animations.at(-1)
    value.windowEvent(event)
    value.finish(oldCover)
    staleDeadline()
    assertRetired(value, 'en')
    assert.deepEqual(value.writes, ['en'])
    value.owner.beginLanguageTransition('ar')
    value.finish(oldCover)
    staleDeadline()
    assert.equal(value.owner.languageTransitionTarget, 'ar')
    value.owner.aboutToDisappear()
    assertRetired(value, 'ar')
    assert.equal(value.listeners.size, 0)
    assert.equal(value.disposed, 1)
    assert.deepEqual(value.offEvents, ['avoidAreaChange', 'windowEvent'])
  }
})

test('Either reduced-motion scale bypasses the cover and uses the production revision consumer only once', () => {
  for (const scales of [{ animatorScale: '0' }, { transitionScale: '0' }]) {
    const value = fixture(scales)
    value.owner.beginLanguageTransition('en')
    assert.equal(value.owner.languageOverlayVisible, false)
    assert.equal(value.frames.length, 0)
    assert.equal(value.animations.length, 0)
    assert.equal(value.timers.size, 0)
    assert.equal(value.owner.settingsSession.languageChangeTarget, 'en')
    value.applyRequest()
    value.applyRequest()
    assert.equal(value.owner.settingsSession.languageChangeAppliedRevision, value.owner.languageTransitionEpoch)
    assert.deepEqual(value.writes, ['en'])
  }
})
