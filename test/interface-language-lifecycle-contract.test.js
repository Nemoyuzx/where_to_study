import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')

test('Apple language updates preserve tab identity and cannot replace a measured card anchor with an empty default', () => {
  const root = read('native/apple/Sources/Shared/RootView.swift')
  const anchor = read('native/apple/Sources/Shared/SettingsLanguageScrollAnchor.swift')
  assert.match(root, /compactTabIdentity\(languageRawValue _: String\)[\s\S]*?"compact-tabs"/)
  assert.match(root, /\.background\(CompactTabLanguageLayout\(language: model\.appLanguage\)\)/)
  assert.match(anchor, /if next\.width > 0 && next\.height > 0 \{ value = next \}/)
  assert.match(anchor, /transaction\.disablesAnimations = true/)
  assert.match(anchor, /self\.revision == requestedRevision/)
  assert.match(anchor, /\.onDisappear \{ state\.cancel\(\) \}/)
})

test('Tauri language changes keep the mounted page and do not own business fetch effects', () => {
  const app = read('src/App.jsx')
  assert.match(app, /key=\{activePage\}/)
  assert.match(app, /pageContentRef\.current\?\.scrollTo\(\{ top: 0, left: 0, behavior: 'auto' \}\)\s*\}, \[activePage, favoriteManagerOpen\]\)/)
  assert.match(app, /<select value=\{settings\.uiLanguage\} onChange=\{event => updateSetting\('uiLanguage', event\.target\.value\)\}/)
  assert.match(app, /UI_LANGUAGES\.map\(\(\{code, name\}\)/)
  assert.doesNotMatch(app, /key=\{(?:uiLanguage|settings\.uiLanguage)\}/)
  const weather = app.slice(app.indexOf('if (!settings.weatherEnabled)'), app.indexOf('if (!settings.weatherEnabled)') + 470)
  assert.doesNotMatch(weather, /uiLanguage/)
  const automaticSchedule = app.slice(app.indexOf('if (settingsSaving\n      || !settingsLoaded'), app.indexOf('if (settingsSaving\n      || !settingsLoaded') + 1000)
  assert.doesNotMatch(automaticSchedule, /uiLanguage/)
})

test('Harmony query session retains only UI state and a bounded scoped public shuttle snapshot', () => {
  const root = read('native/harmony/entry/src/main/ets/view/RootView.ets')
  const query = read('native/harmony/entry/src/main/ets/view/QueryView.ets')
  const session = read('native/harmony/entry/src/main/ets/view/QuerySession.ets')
  assert.match(root, /@Local querySession: QuerySession = new QuerySession\(\)/)
  assert.equal((root.match(/QueryView\(\{ session: this\.querySession,/g) || []).length, 3)
  assert.match(query, /@Param session: QuerySession = new QuerySession\(\)/)
  assert.match(query, /private loadShuttle\(force: boolean = false\): void \{\s*void this\.session\.loadShuttle\(this\.shuttleClient, this\.model\.isSampleMode\(\), force\)/)
  assert.match(query, /\.onClick\(\(\) => this\.loadShuttle\(true\)\)/)
  assert.match(session, /shuttleCacheLifetimeMs: number = 5 \* 60 \* 1000/)
  assert.match(session, /activateScope\(sampleMode: boolean\)/)
  assert.match(session, /Promise\.race\(\[fetch, watchdog\]\)/)
  assert.match(session, /detachView\(\): void \{[\s\S]*?if \(this\.viewOwners === 0\) \{ this\.shuttleFlight\?\.suspend\(\); \}/)
  assert.match(session, /activateScope\(sampleMode: boolean\): void \{[\s\S]*?this\.shuttleFlight\?\.cancel\(\)/)
  assert.match(session, /dispose\(\): void \{[\s\S]*?this\.shuttleFlight\?\.cancel\(\)/)
  assert.match(query, /this\.session\.attachView\(\)/)
  assert.match(query, /this\.session\.detachView\(\)/)
  assert.match(root, /this\.querySession\.dispose\(\)/)
  assert.match(session, /generation !== this\.shuttleRequestGeneration \|\| scope !== this\.shuttleScope/)
  assert.match(query, /本机获取时间：/)
  assert.doesNotMatch(session, /account|password|credential|cookie|token|setInterval/)
  assert.match(read('native/harmony/entry/src/test/QuerySession.test.ets'), /sample_and_live_snapshots_never_cross_the_scope_boundary/)
})
