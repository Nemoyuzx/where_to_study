import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')

test('iOS language transition uses a bounded native window material without private snapshots or root replacement', () => {
  const source = read('native/apple/Sources/Shared/LanguageChangeTransition.swift')
  const settings = read('native/apple/Sources/Shared/SettingsView.swift')
  const owner = read('native/apple/Sources/Shared/SettingsViewSession.swift')
  assert.match(source, /^#if os\(iOS\)/)
  assert.match(source, /UIVisualEffectView\(effect: nil\)/)
  assert.match(source, /effectView\.frame = window\.bounds/)
  assert.match(source, /window\.bringSubviewToFront\(effectView\)/)
  assert.match(source, /UIAccessibility\.isReduceMotionEnabled/)
  assert.match(source, /revision == currentRevision/)
  assert.match(source, /func finishImmediately\(\)[\s\S]*?applyPendingChange\(\)[\s\S]*?removeCover\(\)/)
  assert.match(source, /cover\?\.removeFromSuperview\(\)/)
  assert.doesNotMatch(source, /snapshotView|drawHierarchy|UIGraphics|\.blur\(|CADisplayLink|Timer\(/)
  assert.match(owner, /let languageTransition = LanguageChangeTransition\(\)/)
  assert.match(owner, /LanguageChangeTransitionHost\(transition: session\.languageTransition\)/)
  assert.match(settings, /changeInterfaceLanguage\(to: language\)/)
  assert.match(settings, /transaction\.disablesAnimations = true/)
  assert.match(settings, /session\.languageScroll\.capture\(beforeSwitchTo: language\)/)
  assert.match(settings, /session\.languageTransition\.request\(/)
  assert.match(source, /guard current != target else \{[\s\S]*?pendingChange = nil[\s\S]*?removeCover\(\)/)
})
