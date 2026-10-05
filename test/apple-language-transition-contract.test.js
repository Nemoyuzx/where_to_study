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

// Specifications only: not run during this change because local automated
// testing has been disabled at the user's request.
test('completion waits for local language work, scroll and an acknowledged native tab layout', () => {
  const ios = read('native/apple/Sources/Shared/LanguageChangeTransition.swift')
  const mac = read('native/apple/Sources/Shared/MacLanguageChangeTransition.swift')
  const settings = read('native/apple/Sources/Shared/SettingsView.swift')
  const model = read('native/apple/Sources/Shared/AppModel.swift')
  const tabs = read('native/apple/Sources/Shared/CompactTabLanguageLayout.swift')
  const gate = read('native/apple/Sources/Shared/LanguageTransitionLayoutGate.swift')
  assert.match(settings, /languageUpdateSucceeded == true/)
  assert.match(settings, /scroll\?\.isSettled\(for: language\)/)
  assert.match(model, /await widgetWork\?\.value/)
  assert.match(model, /await notificationWork\?\.value/)
  assert.match(model, /awaitLocalRemovals/)
  assert.match(ios, /navigation\.translationIsReady\(for: target\)/)
  assert.match(tabs, /appliedAccessibilityLabels == accessibilityLabels/)
  assert.match(gate, /stableSamples >= 3/)
  for (const source of [ios, mac]) {
    assert.match(source, /Switching…/)
    assert.match(source, /completionFailed\(\).*finishImmediately\(\)/)
    assert.match(source, /readinessDeadline/)
    assert.match(source, /"completed"/)
  }
})
