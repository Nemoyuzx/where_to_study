import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = path => readFileSync(new URL(path, import.meta.url), 'utf8')
const web = source('../src/QueryHub.jsx')
const css = source('../src/App.css')
const apple = source('../native/apple/Sources/Shared/InformationQueriesView.swift')
const android = source('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/InformationQueryPage.kt')
const harmony = source('../native/harmony/entry/src/main/ets/view/QueryView.ets')

test('shuttle content has transportation glyphs instead of academic query glyphs', () => {
  const webShuttle = web.slice(web.indexOf("{tab === 'shuttle' ? ("), web.indexOf("{tab === 'events' ? ("))
  assert.match(webShuttle, /departure\.next \? <BusFront[\s\S]*: <Route/)
  assert.doesNotMatch(webShuttle, /<(CheckCircle2|CalendarClock|Clock3)\b/)
  const appleShuttle = apple.slice(apple.indexOf('private var shuttleContent'), apple.indexOf('private var importantEventsContent'))
  assert.match(appleShuttle, /\? "bus" : "bus\.fill"/)
  assert.match(appleShuttle, /Label\("完整班车时刻表", systemImage: "bus\.doubledecker"\)/)
  assert.doesNotMatch(appleShuttle, /systemImage: "calendar(?:\.badge\.exclamationmark)?"/)
  const androidStatus = android.slice(android.indexOf('private fun LinearLayout.renderShuttleSnapshot'), android.indexOf('private fun fullTimetableCell'))
  assert.match(androidStatus, /shuttleIcon\(R\.drawable\.ic_shuttle_bus\)/)
  assert.doesNotMatch(androidStatus, /ic_nav_calendar/)
  assert.match(android, /shuttleIcon\(R\.drawable\.ic_shuttle_notice\)/)
  const harmonyShuttle = harmony.slice(harmony.indexOf('shuttleMessage(title:'), harmony.indexOf('eventsContent() {'))
  assert.match(harmonyShuttle, /SymbolGlyph\(\$r\('sys\.symbol\.bus_fill'\)\)/)
  assert.doesNotMatch(harmonyShuttle, /sys\.symbol\.calendar/)
})

test('ordinary shuttle notices follow secondary theme ink and neutral themed surfaces', () => {
  assert.match(css, /\.shuttle-holiday-notice p \{ color: var\(--text-secondary\)/)
  assert.match(css, /\.shuttle-holiday-notice > svg \{ color: var\(--primary-text\)/)
  for (const selector of ['.shuttle-holiday-notice', '.shuttle-full-fallback', '.shuttle-status-card.stale']) {
    const escaped = selector.replaceAll('.', '\\.')
    assert.match(css, new RegExp(`${escaped} \\{[^}]*background: var\\(--surface-muted\\)`))
  }
  assert.match(apple, /\.foregroundStyle\(theme\.secondaryText\)[\s\S]*\.accessibilityIdentifier\("queries\.shuttle\.holiday-warning"\)/)
  assert.match(android, /text = "当前展示最近一次成功同步的缓存"[\s\S]*?setThemeTextColor \{ Palette\.muted \}/)
  assert.match(harmony, /'今日为法定节假日，班车不一定运行；请以学校放假安排为准，放假期间无班车。'[\s\S]*?\.fontColor\(AppTheme\.secondaryText\(\)\)/)
})

test('all UI actions and localizations use the full teaching cloud platform name', () => {
  const paths = [
    '../src/App.jsx', '../src/PrivateQueriesPanel.jsx',
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/InformationQueryPage.kt',
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/AppLocale.kt',
    '../native/apple/Sources/Shared/AssignmentQueryView.swift',
    '../native/apple/Resources/Localizations/zh-Hans.lproj/Localizable.strings',
    '../native/apple/Resources/Localizations/en.lproj/Localizable.strings',
    '../native/harmony/entry/src/main/ets/view/AcademicQueryViews.ets',
    '../native/harmony/entry/src/main/ets/common/AppLocalization.ets',
  ]
  for (const path of paths) {
    const text = source(path)
    assert.match(text, /打开教学云平台/, path)
    assert.doesNotMatch(text, /打开教学云(?!平台)|Open [Tt]eaching [Cc]loud(?! Platform)|平台平台/, path)
  }
  assert.match(source('../native/harmony/entry/src/main/ets/view/AcademicQueryViews.ets'),
    /Flex\(\{ wrap: FlexWrap\.Wrap[\s\S]*打开教学云平台/)
})
