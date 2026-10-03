import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = file => readFileSync(new URL(file, import.meta.url), 'utf8')
const policy = read('../native/apple/Sources/Shared/PrivacyPolicyView.swift')
const settings = read('../native/apple/Sources/Shared/SettingsView.swift')
const root = read('../native/apple/Sources/Shared/RootView.swift')
const session = read('../native/apple/Sources/Shared/SettingsViewSession.swift')
const consent = read('../native/apple/Sources/Shared/PrivacyConsentView.swift')
const probe = read('../native/apple/Sources/Shared/MobileDetailPresentationProbe.swift')

test('privacy long-form text and theme resolution are lazy, without data loading', () => {
  assert.match(policy, /ScrollView \{\s*LazyVStack\(alignment: \.leading, spacing: 20\)/)
  assert.match(policy, /private func privacySection[\s\S]*PrivacyPolicySection\(title: title, content: body\)/)
  assert.match(policy, /private struct PrivacyPolicySection: View[\s\S]*Text\(content\)/)
  assert.doesNotMatch(policy, /URLSession|FileManager|\.task|Task\s*\{|Timer|DispatchQueue/)
  assert.match(policy, /action\.open-privacy-github/)
  assert.match(policy, /action\.dismiss-privacy-policy/)
})

test('privacy presentation is observed only in a stable host, not the full settings screen', () => {
  assert.match(policy, /final class PrivacyPolicyPresentation: ObservableObject/)
  assert.match(policy, /struct PrivacyPolicyPresentationHost: View \{\s*@ObservedObject/)
  assert.match(policy, /PrivacyPolicyView\(\)\.buttonStyle\(\.automatic\)/)
  assert.match(consent, /@State private var privacyPresentation = PrivacyPolicyPresentation\(\)/)
  assert.match(consent, /\.background \{ PrivacyPolicyPresentationHost\(presentation: privacyPresentation\) \}/)
  assert.match(root, /@State private var settingsSession = SettingsViewSession\(\)/)
  assert.match(root, /case \.settings: SettingsView\(session: settingsSession\)/)
  assert.match(root, /\.background \{ SettingsPresentationHost\(session: settingsSession\) \}/)
  assert.match(session, /let privacyPresentation = PrivacyPolicyPresentation\(\)/)
  assert.match(session, /PrivacyPolicyPresentationHost\(presentation: session\.privacyPresentation\)/)
  assert.doesNotMatch(session, /SettingsViewSession: ObservableObject|@(?:Published|ObservedObject|StateObject)/)
  assert.match(settings, /let session: SettingsViewSession/)
  assert.doesNotMatch(settings, /@(?:State|StateObject|ObservedObject).*privacyPresentation|showingPrivacyPolicy/)
  assert.doesNotMatch(consent, /@(?:StateObject|ObservedObject).*privacyPresentation|showingPrivacyPolicy/)
  assert.equal(settings.match(/PrivacyPolicyButton\(presentation: privacyPresentation, beforePresent: dismissKeyboard\)/g).length, 2)
  assert.match(consent, /PrivacyPolicyButton\(presentation: privacyPresentation\)/)
  assert.match(policy, /guard !presentation\.isPresented else \{ return \}/)
})

test('the timing probe is opt-in iOS DEBUG only and records monotonic lifecycle times', () => {
  assert.match(probe, /^#if os\(iOS\) && DEBUG/)
  assert.match(probe, /--ui-test-privacy-presentation/)
  assert.match(probe, /guard isEnabled else \{ return \}/)
  assert.match(probe, /ProcessInfo\.processInfo\.systemUptime/)
  assert.match(probe, /requestToWillAppear/)
  assert.match(probe, /requestToDidAppear/)
  assert.match(probe, /Calendar detail presentation metrics/)
  assert.doesNotMatch(probe, /UserDefaults|FileManager|URLSession|Timer|DispatchQueue|Task\s*\{/)
})
