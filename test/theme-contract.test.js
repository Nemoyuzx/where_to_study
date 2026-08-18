import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const indexCss = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const appCss = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')
const applePlannerSource = readFileSync(
  new URL('../native/apple/Sources/Shared/PlannerView.swift', import.meta.url),
  'utf8',
)
const appleCalendarSource = readFileSync(
  new URL('../native/apple/Sources/Shared/TeachingCalendarView.swift', import.meta.url),
  'utf8',
)
const appleMobileCalendarSource = readFileSync(
  new URL('../native/apple/Sources/Shared/MobileTeachingCalendarView.swift', import.meta.url),
  'utf8',
)
const androidPlannerSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/PlannerPage.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidCalendarSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/TeachingCalendarPage.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidYearCalendarSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/YearCalendarView.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidSettingsIcon = readFileSync(
  new URL(
    '../native/android/app/src/main/res/drawable/ic_nav_settings.xml',
    import.meta.url,
  ),
  'utf8',
)
const androidUiSupportSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/UiSupport.kt',
    import.meta.url,
  ),
  'utf8',
)
const indexHtml = readFileSync(new URL('../index.html', import.meta.url), 'utf8')
const nativeAndroidLightTheme = readFileSync(
  new URL(
    '../native/android/app/src/main/res/values/themes.xml',
    import.meta.url,
  ),
  'utf8',
)
const nativeAndroidDarkTheme = readFileSync(
  new URL(
    '../native/android/app/src/main/res/values-night/themes.xml',
    import.meta.url,
  ),
  'utf8',
)

function parseTokens(source) {
  return Object.fromEntries(
    [...source.matchAll(/(--[a-z0-9-]+):\s*(#[0-9a-f]{6})\s*;/gi)].map((match) => [
      match[1],
      match[2].toLowerCase(),
    ]),
  )
}

function relativeLuminance(hex) {
  const channels = hex
    .slice(1)
    .match(/../g)
    .map((channel) => Number.parseInt(channel, 16) / 255)
    .map((channel) =>
      channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4,
    )
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
}

function contrastRatio(foreground, background) {
  const values = [relativeLuminance(foreground), relativeLuminance(background)].sort(
    (left, right) => right - left,
  )
  return (values[0] + 0.05) / (values[1] + 0.05)
}

function assertContrast(tokens, foreground, background, minimum = 4.5) {
  const ratio = contrastRatio(tokens[foreground], tokens[background])
  assert.ok(
    ratio >= minimum,
    `${foreground} on ${background} has ${ratio.toFixed(2)}:1 contrast`,
  )
}

test('web surfaces follow the operating system color scheme', () => {
  assert.match(indexCss, /color-scheme:\s*light dark/)
  assert.match(indexCss, /@media \(prefers-color-scheme: dark\)/)
  assert.match(indexHtml, /name="color-scheme" content="light dark"/)
  assert.match(indexHtml, /prefers-color-scheme: light/)
  assert.match(indexHtml, /prefers-color-scheme: dark/)
})

test('component styles use semantic theme tokens instead of fixed colors', () => {
  const fixedColors = appCss
    .replace(/rgb\(var\(--primary-rgb\) \/ var\(--course-load-opacity, 0\.12\)\)/g, '')
    .match(/#[0-9a-f]{3,8}|rgba?\(/gi)
  assert.equal(fixedColors, null)
})

test('Windows workspace follows the native Apple layout metrics', () => {
  assert.match(appCss, /\.app-frame\s*\{[^}]*grid-template-columns:\s*230px minmax\(0, 1fr\)/s)
  assert.match(appCss, /\.topbar\s*\{[^}]*max-width:\s*1200px/s)
  assert.match(appCss, /\.panel\s*\{[^}]*padding:\s*16px/s)
  assert.match(appCss, /\.panel,\s*\.summary-band\s*\{[^}]*border-radius:\s*8px/s)
  assert.match(appCss, /\.app-nav\s*\{[^}]*grid-auto-rows:\s*36px/s)
  assert.match(appCss, /h1\s*\{[^}]*font-size:\s*34px/s)
  assert.match(appCss, /\.settings-layout\s*\{[^}]*repeat\(2, minmax\(0, 1fr\)\)/s)
})

test('scrolling content reserves scrollbar space without shifting the layout', () => {
  assert.match(appCss, /\.page-content\s*\{[^}]*scrollbar-gutter:\s*stable/s)
})

test('mobile navigation keeps the same icon and label hierarchy as iOS tabs', () => {
  assert.match(
    appCss,
    /@media \(max-width: 720px\)[\s\S]*\.app-nav \.nav-label\s*\{[^}]*display:\s*block/s,
  )
  assert.match(
    appCss,
    /@media \(max-width: 720px\)[\s\S]*\.app-nav button\s*\{[^}]*flex-direction:\s*column/s,
  )
})

test('every client uses the concise linked-query page title', () => {
  assert.match(appSource, /activePage === 'settings' \? '设置' : '联动查询'/)
  assert.match(applePlannerSource, /title: "联动查询"/)
  assert.match(androidPlannerSource, /"联动查询"/)
  for (const source of [appSource, applePlannerSource, androidPlannerSource]) {
    assert.doesNotMatch(source, /空教室与个人课表联动查询/)
  }
})

test('mobile week calendar stays in one viewport and pages from the full timeline', () => {
  assert.match(appCss, /\.calendar-swipe-surface\s*\{[^}]*touch-action:\s*pan-y/s)
  assert.match(appCss, /\.time-calendar:not\(\.single-day\)\s*\{[^}]*repeat\(var\(--day-count\), minmax\(0, 1fr\)\)/s)
  assert.match(appCss, /\.calendar-view-switch button\s*\{\s*height:\s*30px/s)
  assert.match(appCss, /\.time-corner,\s*\.time-day-head\s*\{\s*min-height:\s*62px/s)
  assert.match(appCss, /\.week-calendar \.time-day-head > small\s*\{\s*display:\s*none/s)
  assert.match(appCss, /content:\s*attr\(data-mobile-day\)/)
  assert.match(appSource, /calendar-day-tags[\s\S]*<i aria-hidden="true"/)
  assert.match(appSource, /data-mobile-day=\{date\.getDate\(\)\}/)
  assert.match(appSource, /'single-day'\s*:\s*'week-calendar'/)
  assert.match(appSource, /addEventListener\('touchmove', updateCalendarSwipe, \{ passive: false \}\)/)
  assert.doesNotMatch(appSource, /week-calendar-scroll|calendar-week-swipe-handle/)
})

test('calendar chrome is compact and all-day events stay above the timeline', () => {
  assert.match(appSource, /calendarHeaderTitle = calendarView === 'week'/)
  assert.match(appSource, /formatTeachingWeek\(calendarWeekState\.weekNumber\)/)
  assert.doesNotMatch(appSource, /className="topbar-subtitle"/)
  assert.match(appSource, /className="time-all-day-label">全天</)
  assert.match(appSource, /className="time-all-day-cell"/)
  assert.match(appCss, /\.calendar-view-switch\s*\{[^}]*border:\s*0/s)
  assert.match(appCss, /\.teaching-calendar-main\s*\{[^}]*border:\s*0/s)
  assert.match(
    appCss,
    /@media \(max-width: 720px\)[\s\S]*\.year-calendar\s*\{[^}]*repeat\(2, minmax\(0, 1fr\)\)/s,
  )
})

test('native Android year calendar follows the compact iOS mini-month layout', () => {
  assert.match(
    androidCalendarSource,
    /private fun yearView\(onDateChanged: \(\) -> Unit\): LinearLayout = LinearLayout\(activity\)\.apply/,
  )
  assert.match(androidCalendarSource, /text = "颜色越深表示当天课程越多"/)
  assert.doesNotMatch(androidCalendarSource, /\$year 年课程分布/)
  assert.doesNotMatch(androidCalendarSource, /颜色越深表示当天课程越多；点击日期查看日程/)
  assert.match(androidYearCalendarSource, /weekdayHeight = dp\(14\)/)
  assert.match(androidYearCalendarSource, /dayCellHeight = dp\(26\)/)
  assert.match(androidYearCalendarSource, /monthGap = dp\(16\)/)
  assert.match(androidYearCalendarSource, /boldPaint\.textSize = sp\(17f\)/)
  assert.match(androidYearCalendarSource, /textPaint\.textSize = sp\(8f\)/)
  assert.match(androidYearCalendarSource, /background = Palette\.background/)
  assert.match(androidSettingsIcon, /android:fillType="evenOdd"/)
  assert.doesNotMatch(androidSettingsIcon, /android:strokeWidth=/)
  assert.match(
    androidUiSupportSource,
    /fun TextView\.setCompactSelectedStyle[\s\S]*Palette\.segmentedSelection/,
  )
})

test('calendar paging keeps an outgoing page while the new page slides in', () => {
  assert.match(appSource, /cloneNode\(true\)/)
  assert.match(appSource, /calendar-motion-outgoing/)
  assert.match(appSource, /calendarTransitionHostRef/)
  assert.match(appCss, /@keyframes calendar-slide-exit-next\s*\{[^}]*translateX\(0\)[\s\S]*translateX\(-100%\)/)
  assert.match(appCss, /@keyframes calendar-slide-exit-previous\s*\{[^}]*translateX\(0\)[\s\S]*translateX\(100%\)/)
  assert.doesNotMatch(appCss, /calendar-view-enter/)
})

test('month expansion stays mobile-only and morphs its drag handle with progress', () => {
  assert.match(appSource, /calendarMonthExpansion\(deltaX, deltaY\)/)
  assert.match(appSource, /calendarMonthDragProgress\(/)
  assert.match(appSource, /calendarMonthExpansionTarget\(/)
  assert.match(appSource, /onPointerMove=\{compactCalendarLayout \? updateMonthPointerSwipe : undefined\}/)
  assert.match(appSource, /desktop-month-view/)
  assert.match(appSource, /compactCalendarLayout \? \(\s*<button[\s\S]*className="month-expansion-handle"/)
  assert.match(
    appSource,
    /target\?\.closest\('\.month-expansion-handle, \.month-expansion-accessibility-action'\)/,
  )
  assert.match(appSource, /month-expanded-hidden/)
  assert.match(appSource, /handleMonthCalendarKeyDown/)
  assert.match(appSource, /month-expansion-accessibility-action/)
  assert.match(appSource, /month-expansion-accessibility-action[\s\S]*tabIndex=\{-1\}/)
  assert.match(appCss, /\.assistive-only\s*\{[^}]*clip-path:\s*inset\(50%\)/s)
  assert.match(appSource, /下拉展开，上拉收起/)
  assert.match(appCss, /\.page-content\.calendar-gesture-locked\s*\{[^}]*overflow-y:\s*hidden/s)
  assert.match(appSource, /month-entry-overflow/)
  assert.match(appSource, /className="month-expansion-handle"/)
  assert.match(appCss, /\.month-expansion-handle\s*\{[^}]*height:\s*28px/s)
  assert.match(appCss, /\.month-expansion-handle > span::before,[\s\S]*\.month-expansion-handle > span::after/)
  assert.match(appCss, /--month-handle-left-angle/)
  assert.match(appCss, /\.month-view\.desktop-month-view\s*\{[^}]*height:\s*auto/s)
  assert.match(appCss, /\.month-view\s*\{[^}]*grid-template-rows:\s*minmax\(0, 1fr\) 28px/s)
  assert.match(appSource, /calendarView === 'month' \? 'calendar-month-page' : ''/)
  assert.match(appCss, /\.page-content\.calendar-month-page\s*\{[^}]*overflow:\s*hidden/s)
  assert.match(appCss, /\.month-view\s*\{[^}]*transition:\s*height 280ms/s)
  assert.match(appCss, /\.month-view\.month-dragging[\s\S]*transition:\s*none/s)
  assert.match(appCss, /--month-live-row-height/)
  assert.match(
    appleMobileCalendarSource,
    /Capsule\(\)[\s\S]*rotationEffect\(\.degrees\(isMonthExpanded \? -24 : 0\)\)/,
  )
  assert.match(androidCalendarSource, /class MonthExpansionIndicatorView/)
  assert.match(androidCalendarSource, /setExpansionProgress\(progress: Float\)/)
  assert.doesNotMatch(appSource, /month-density-button/)
})

test('desktop calendar keeps full month and single-select double-open year behavior', () => {
  assert.match(appSource, /className=\{`month-view \$\{[\s\S]*desktop-month-view/)
  assert.match(
    appSource,
    /onDoubleClick=\{\(event\) => currentMonth && openDesktopYearMonth\(event, dateString\)\}/,
  )
  assert.match(appleCalendarSource, /count: 2[\s\S]*mode = \.month/)
  assert.match(appleCalendarSource, /#if !os\(macOS\)[\s\S]*isMonthExpanded\.toggle\(\)/)
  assert.match(appCss, /\.planner-page-content \.planner-workspace,[\s\S]*margin:\s*0 16px 16px/)
  assert.match(applePlannerSource, /#if os\(macOS\)[\s\S]*page[\s\S]*\.padding\(16\)/)
})

test('month expansion reserves all six rows on desktop and mobile', () => {
  const baseMonthRule = appCss.match(/\.month-view\s*\{([^}]*)\}/)?.[1] ?? ''
  assert.match(baseMonthRule, /--month-collapsed-height:\s*440px/)
  assert.match(baseMonthRule, /height:\s*var\(--month-expanded-height, 776px\)/)
  assert.match(baseMonthRule, /overflow:\s*hidden/)
  assert.match(appCss, /repeat\(6, minmax\(0, var\(--month-expanded-row-height, 118px\)\)\)/)
  assert.match(
    appCss,
    /@media \(max-width: 720px\)[\s\S]*\.month-view\.expanded\s*\{[^}]*max-height:[^}]*overflow:\s*hidden/s,
  )
  assert.match(appSource, /matchMedia\('\(max-width: 720px\)'\)/)
  assert.match(appSource, /removeProperty\('--month-expanded-height'\)/)
})

test('about this app is the final settings panel', () => {
  assert.ok(appSource.indexOf('className="panel settings-about"') > appSource.indexOf('className="panel settings-actions"'))
  assert.match(appSource, /<h2>关于本应用<\/h2>/)
})

test('native Android chrome follows the active system theme', () => {
  assert.match(nativeAndroidLightTheme, /Theme\.Material\.Light\.NoActionBar/)
  assert.match(nativeAndroidLightTheme, /windowLightStatusBar">true/)
  assert.match(nativeAndroidLightTheme, /statusBarColor">@color\/background/)
  assert.match(nativeAndroidLightTheme, /navigationBarColor">@color\/surface/)
  assert.match(nativeAndroidLightTheme, /windowBackground">@color\/background/)

  assert.match(nativeAndroidDarkTheme, /Theme\.Material\.NoActionBar/)
  assert.match(nativeAndroidDarkTheme, /windowLightStatusBar">false/)
  assert.match(nativeAndroidDarkTheme, /statusBarColor">@color\/background/)
  assert.match(nativeAndroidDarkTheme, /navigationBarColor">@color\/surface/)
  assert.match(nativeAndroidDarkTheme, /windowBackground">@color\/background/)
})

test('light and dark text combinations meet WCAG AA contrast', () => {
  const [lightSource, darkSource] = indexCss.split(
    '@media (prefers-color-scheme: dark)',
  )
  const light = parseTokens(lightSource)
  const dark = { ...light, ...parseTokens(darkSource) }

  for (const tokens of [light, dark]) {
    assertContrast(tokens, '--text-primary', '--surface')
    assertContrast(tokens, '--text-secondary', '--surface')
    assertContrast(tokens, '--on-primary', '--primary')
    assertContrast(tokens, '--gold-text', '--gold-surface')
    assertContrast(tokens, '--error-text', '--error-surface')
  }
})
