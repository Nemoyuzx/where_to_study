import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')
const css = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')

test('desktop date and all-day rows pin to the same bounded timeline scroller', () => {
  const desktop = css.slice(css.indexOf('/* Desktop calendars own vertical scrolling;'))
  assert.match(desktop, /@media \(min-width: 721px\)/)
  assert.match(desktop, /\.time-calendar\s*\{[^}]*max-height: var\(--desktop-calendar-viewport-height[^}]*overflow: auto/s)
  assert.match(desktop, /\.time-calendar \.time-day-head\s*\{[^}]*position: sticky;[^}]*top: 0;[^}]*z-index: 5/s)
  assert.match(desktop, /\.time-calendar \.time-all-day-cell\s*\{[^}]*position: sticky;[^}]*top: var\(--time-day-header-height, 72px\);[^}]*z-index: 4/s)
  assert.match(source, /header\.getBoundingClientRect\(\)\.height/)
  assert.match(source, /new ResizeObserver\(scheduleMeasure\)/)
  assert.match(source, /surface\.getBoundingClientRect\(\)\.top - page\.scrollTop - 16/)
  assert.match(desktop, /\.time-calendar \.time-day-lane\s*\{[^}]*isolation: isolate;/s)
})

test('desktop month weekday header is outside the scrolling grid, phone header is unchanged', () => {
  assert.match(source, /!compactCalendarLayout \? \(\s*<div className="desktop-month-weekdays">/)
  assert.match(source, /compactCalendarLayout \? uiWeekdayLabels\.map/)
  assert.ok(source.indexOf('className="desktop-month-weekdays"') < source.indexOf('id="teaching-month-calendar"'))
  assert.match(css, /\.desktop-month-weekdays\s*\{[^}]*position: sticky;[^}]*top: 0;[^}]*background: var\(--surface\)/s)
  assert.match(source, /outgoing\.scrollTop = source\.scrollTop/)
  assert.match(source, /outgoing\.scrollLeft = source\.scrollLeft/)
})
