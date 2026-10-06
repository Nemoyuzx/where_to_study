import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { transformSync } from 'esbuild'
import { DEFAULT_SETTINGS, savedSettingsToState, settingsToPayload, reminderSettingsPayload } from '../src/planner-domain.js'

// Exercise the real ArkTS preference methods with synthetic storage only.
function method(source, name) {
  const start = source.indexOf(`  ${name}(`)
  assert.notEqual(start, -1)
  const open = source.indexOf('{', start)
  let depth = 1, end = open + 1
  for (; depth > 0 && end < source.length; end++) {
    if (source[end] === '{') depth++
    if (source[end] === '}') depth--
  }
  assert.equal(depth, 0)
  return source.slice(start, end)
}

const modelSource = readFileSync(new URL('../native/harmony/entry/src/main/ets/model/AppModel.ets', import.meta.url), 'utf8')
const preferenceSource = readFileSync(new URL('../native/harmony/entry/src/main/ets/store/PreferencesStore.ets', import.meta.url), 'utf8')
const source = `
class SyntheticPreferences {
  values = new Map(); writes = []; fail = false;
  async getBool(key, fallback) { return this.values.has(key) ? this.values.get(key) : fallback; }
  async getString(key) { return this.values.get(key) ?? null; }
  async setBool(key, value) { if (this.fail) throw new Error('synthetic failure'); this.writes.push(value); this.values.set(key, value); }
  ${method(preferenceSource, 'async getOptionalBool')}
}
class Subject {
  qmplusEnabled = false; qmplusOffSafetyLatch = false; qmplusPreferenceRevision = 0;
  qmplusClearGeneration = 0; localDataClearWork = null; qmplusPreferenceWrite = Promise.resolve(); statusMessage = '';
  constructor(preferences) { this.preferences = preferences; }
  isSampleMode() { return false; }
  ${method(modelSource, 'private async restoreQMplusPreference')}
  ${method(modelSource, 'async setQMplusEnabled')}
}
return { SyntheticPreferences, Subject };
`
const { SyntheticPreferences, Subject } = new Function(transformSync(source, { loader: 'ts', target: 'es2022' }).code)()
const gate = () => {
  let release
  return { promise: new Promise(resolve => { release = resolve }), release: () => release() }
}

test('desktop QMplus setting defaults off and explicit off survives unrelated saves', () => {
  assert.equal(DEFAULT_SETTINGS.qmplusEnabled, false)
  assert.equal(savedSettingsToState({}).qmplusEnabled, false)
  const saved = savedSettingsToState({ qmplus_enabled: false }, { ...DEFAULT_SETTINGS, qmplusEnabled: true })
  assert.equal(saved.qmplusEnabled, false)
  assert.equal(settingsToPayload(saved).qmplus_enabled, false)
  assert.equal(reminderSettingsPayload(saved, true, 450).qmplus_enabled, false)
  assert.equal(savedSettingsToState({ qmplus_enabled: true }).qmplusEnabled, true)
})

test('Harmony migration keeps new users off and preserves non-secret legacy consent', async () => {
  for (const legacy of [false, true]) {
    const prefs = new SyntheticPreferences()
    if (legacy) prefs.values.set('qmplusAutoFillAuthorizedRecordID', 'synthetic-record-id')
    const model = new Subject(prefs)
    await model.restoreQMplusPreference(0, 0)
    assert.equal(model.qmplusEnabled, legacy)
    assert.equal(prefs.values.get('qmplusEnabled'), legacy)
  }
})

test('Harmony explicit off overrides old consent and never rewrites it', async () => {
  const prefs = new SyntheticPreferences()
  prefs.values.set('qmplusEnabled', false)
  prefs.values.set('qmplusAutoFillAuthorizedRecordID', 'synthetic-record-id')
  const model = new Subject(prefs)
  await model.restoreQMplusPreference(0, 0)
  assert.equal(model.qmplusEnabled, false)
  assert.deepEqual(prefs.writes, [])
})

test('Harmony late migration read cannot re-enable a newer off request', async () => {
  const prefs = new SyntheticPreferences()
  prefs.values.set('qmplusAutoFillAuthorizedRecordID', 'synthetic-record-id')
  const entered = gate(), release = gate()
  const read = prefs.getOptionalBool.bind(prefs)
  prefs.getOptionalBool = async key => { entered.release(); await release.promise; return read(key) }
  const model = new Subject(prefs)
  const migration = model.restoreQMplusPreference(0, 0)
  await entered.promise
  const off = model.setQMplusEnabled(false)
  release.release()
  await Promise.all([migration, off])
  assert.equal(model.qmplusEnabled, false)
  assert.deepEqual(prefs.writes, [false])
})

test('Harmony in-flight on write is serialized before off without publishing on', async () => {
  const prefs = new SyntheticPreferences(), entered = gate(), release = gate()
  const save = prefs.setBool.bind(prefs)
  prefs.setBool = async (key, value) => { if (value) { entered.release(); await release.promise } return save(key, value) }
  const model = new Subject(prefs), publications = []
  let effective = false
  Object.defineProperty(model, 'qmplusEnabled', { get: () => effective, set: value => { effective = value; publications.push(value) } })
  const on = model.setQMplusEnabled(true)
  await entered.promise
  const off = model.setQMplusEnabled(false)
  release.release()
  await Promise.all([on, off])
  assert.deepEqual(prefs.writes, [true, false])
  assert.equal(model.qmplusEnabled, false)
  assert.equal(publications.includes(true), false)
})

test('Harmony failed off remains off through later preference restoration', async () => {
  const prefs = new SyntheticPreferences()
  prefs.values.set('qmplusEnabled', true)
  const model = new Subject(prefs)
  model.qmplusEnabled = true
  prefs.fail = true
  assert.equal(await model.setQMplusEnabled(false), false)
  await model.restoreQMplusPreference(0, model.qmplusPreferenceRevision)
  assert.equal(model.qmplusEnabled, false)
  assert.equal(model.statusMessage, '无法保存本地偏好。')
})

test('settings remove the standalone QMplus disconnect control without removing destructive cleanup boundaries', () => {
  const apple = readFileSync(new URL('../native/apple/Sources/Shared/SettingsView.swift', import.meta.url), 'utf8')
  const android = readFileSync(new URL('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/SettingsPage.kt', import.meta.url), 'utf8')
  const harmony = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8')
  assert.doesNotMatch(apple, /settings\.qmplus\.disconnect/)
  assert.doesNotMatch(android, /\.id\s*=\s*R\.id\.settings_qmplus_disconnect/)
  assert.doesNotMatch(harmony, /\.onClick\([^\n]*qmplusSession\.logout/)
  const store = readFileSync(new URL('../native/apple/Sources/Shared/QMplusStore.swift', import.meta.url), 'utf8')
  assert.match(store, /func disconnect\(\)/)
  assert.match(store, /func disableCredentialAutofill\(\)/)
  assert.match(store, /clearOfficialSession\(\)/)
})
