import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const indexCss = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const appCss = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')
const indexHtml = readFileSync(new URL('../index.html', import.meta.url), 'utf8')
const tauriAndroidLightTheme = readFileSync(
  new URL(
    '../src-tauri/gen/android/app/src/main/res/values/themes.xml',
    import.meta.url,
  ),
  'utf8',
)
const tauriAndroidDarkTheme = readFileSync(
  new URL(
    '../src-tauri/gen/android/app/src/main/res/values-night/themes.xml',
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

test('mobile week calendar stays in one viewport and pages from the full timeline', () => {
  assert.match(appCss, /\.calendar-swipe-surface\s*\{[^}]*touch-action:\s*pan-y/s)
  assert.match(appCss, /\.time-calendar:not\(\.single-day\)\s*\{[^}]*repeat\(var\(--day-count\), minmax\(0, 1fr\)\)/s)
  assert.match(appSource, /'single-day'\s*:\s*'week-calendar'/)
  assert.match(appSource, /addEventListener\('touchmove', updateCalendarSwipe, \{ passive: false \}\)/)
  assert.doesNotMatch(appSource, /week-calendar-scroll|calendar-week-swipe-handle/)
})

test('calendar paging keeps an outgoing page while the new page slides in', () => {
  assert.match(appSource, /cloneNode\(true\)/)
  assert.match(appSource, /calendar-motion-outgoing/)
  assert.match(appSource, /calendarTransitionHostRef/)
  assert.match(appCss, /@keyframes calendar-slide-exit-next\s*\{[^}]*translateX\(0\)[\s\S]*translateX\(-100%\)/)
  assert.match(appCss, /@keyframes calendar-slide-exit-previous\s*\{[^}]*translateX\(0\)[\s\S]*translateX\(100%\)/)
  assert.doesNotMatch(appCss, /calendar-view-enter/)
})

test('month expansion keeps gestures and an assistive action without a visible toggle', () => {
  assert.match(appSource, /calendarMonthExpansion\(deltaX, deltaY\)/)
  assert.match(appSource, /month-expanded-hidden/)
  assert.match(appSource, /handleMonthCalendarKeyDown/)
  assert.match(appSource, /month-expansion-accessibility-action/)
  assert.match(appSource, /month-expansion-accessibility-action[\s\S]*tabIndex=\{-1\}/)
  assert.match(appCss, /\.assistive-only\s*\{[^}]*clip-path:\s*inset\(50%\)/s)
  assert.doesNotMatch(appSource, /month-density-button/)
})

test('Tauri Android chrome follows the active system theme', () => {
  assert.match(tauriAndroidLightTheme, /MaterialComponents\.DayNight\.NoActionBar/)
  assert.match(tauriAndroidLightTheme, /windowLightStatusBar">true/)
  assert.match(tauriAndroidLightTheme, /windowLightNavigationBar">true/)
  assert.match(tauriAndroidLightTheme, /statusBarColor">#F5F6F3/)
  assert.match(tauriAndroidLightTheme, /navigationBarColor">#F5F6F3/)
  assert.match(tauriAndroidLightTheme, /windowBackground">#F5F6F3/)

  assert.match(tauriAndroidDarkTheme, /MaterialComponents\.DayNight\.NoActionBar/)
  assert.match(tauriAndroidDarkTheme, /windowLightStatusBar">false/)
  assert.match(tauriAndroidDarkTheme, /windowLightNavigationBar">false/)
  assert.match(tauriAndroidDarkTheme, /statusBarColor">#101412/)
  assert.match(tauriAndroidDarkTheme, /navigationBarColor">#101412/)
  assert.match(tauriAndroidDarkTheme, /windowBackground">#101412/)
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
