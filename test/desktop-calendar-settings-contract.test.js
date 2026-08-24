import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const indexCss = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const appCss = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')

test('desktop teaching calendar uses the shared high-contrast selected-date blue', () => {
  assert.match(indexCss, /--selected-date-fill:\s*#2563EB;/)
  assert.match(
    indexCss,
    /@media \(prefers-color-scheme: dark\)[\s\S]*--selected-date-fill:\s*#1D4ED8;/,
  )
  assert.match(indexCss, /--selected-date-text:\s*#FFFFFF;/)
  assert.match(appCss, /\.time-day-head\.selected\s*\{[^}]*var\(--selected-date-fill\)/s)
  assert.match(appCss, /\.time-day-lane\.selected\s*\{[^}]*var\(--selected-date-lane\)/s)
  assert.match(appCss, /\.month-cell\.selected\s*\{[^}]*var\(--selected-date-fill\)/s)
  assert.match(
    appCss,
    /\.mini-month-grid button\.selected\s*\{[^}]*var\(--selected-date-fill\)/s,
  )
  assert.match(appSource, /className="time-all-day-cell"[\s\S]*data-selected=\{dateString === calendarDate\}/)
})

test('today and deadline priority indicators remain visible on selected dates', () => {
  assert.match(
    appCss,
    /\.month-cell\.today\.selected\s*\{[^}]*var\(--current-time\)/s,
  )
  assert.match(appCss, /\.month-cell\.deadline-border-assignment\s*\{/)
  assert.match(appCss, /\.month-cell\.deadline-border-school-notice\s*\{/)
  assert.match(appCss, /\.month-cell\.deadline-border-public-deadline\s*\{/)
  assert.match(appCss, /\.mini-month-grid button\.today\.deadline-border-assignment > span/)
})

test('desktop settings expose matching deadline color dots and switch controls', () => {
  assert.match(appSource, /settings-readonly-color-row[\s\S]*settings-color-dot assignment/)
  assert.match(
    appSource,
    /competitionDeadlinesEnabled[\s\S]*'public-deadline'[\s\S]*schoolContestNoticesEnabled[\s\S]*'school-notice'/,
  )
  assert.match(appSource, /summerCampDeadlinesEnabled[\s\S]*'public-deadline'/)
  assert.match(appSource, /hackathonDeadlinesEnabled[\s\S]*'public-deadline'/)
  assert.match(appCss, /\.settings-color-dot\.assignment\s*\{[^}]*var\(--busy-border\)/s)
  assert.match(appCss, /\.settings-color-dot\.school-notice\s*\{[^}]*var\(--gold-outline\)/s)
  assert.match(appCss, /\.settings-color-dot\.public-deadline\s*\{[^}]*var\(--other-deadline-outline\)/s)
  assert.doesNotMatch(appSource, /type="checkbox"/)
  assert.match(
    appSource,
    /className="planner-switch-row"[\s\S]*className="settings-switch"[\s\S]*role="switch"/,
  )
})

test('desktop day and week timelines separate hour and course-slot grid lines', () => {
  assert.match(appSource, /nonHourlyCourseBoundaryMinutes\(slotMeta\)/)
  assert.match(appSource, /className="slot-axis-grid-lines"/)
  assert.match(appSource, /className="time-grid-lines" aria-hidden="true"/)
  assert.match(appSource, /className="hour-line"/)
  assert.match(appSource, /className="slot-boundary-line"/)
  assert.match(
    appCss,
    /\.time-grid-lines span\.slot-boundary-line\s*\{[^}]*border-top-style:\s*dashed/s,
  )
  assert.match(
    appCss,
    /\.slot-axis-grid-lines i\.slot-boundary-line\s*\{[^}]*border-top-style:\s*dashed/s,
  )
  assert.ok(
    appSource.indexOf('className="time-grid-lines" aria-hidden="true"') <
      appSource.indexOf('className="time-course-layer"'),
    'grid lines must remain beneath course blocks and the current-time indicator',
  )
})

test('desktop year selection persists and today survives holiday and deadline priority', () => {
  assert.match(
    appSource,
    /currentMonth && dateString === calendarDate \? 'selected' : ''/,
  )
  assert.doesNotMatch(
    appSource,
    /currentMonth && calendarPopover\?\.date === dateString \? 'selected' : ''/,
  )
  assert.match(
    appSource,
    /function openYearDayPopover[\s\S]*setCalendarDate\(dateString\)/,
  )

  const holidayTodayRule = appCss.indexOf(
    '.mini-month-grid button.today {',
    appCss.indexOf('.mini-month-grid button.has-workday {'),
  )
  const holidayWorkdayRule = appCss.indexOf('.mini-month-grid button.has-workday {')
  const assignmentDeadlineRule = appCss.indexOf(
    '.mini-month-grid button.deadline-border-assignment',
  )
  assert.ok(holidayTodayRule > holidayWorkdayRule)
  assert.ok(assignmentDeadlineRule > holidayTodayRule)
  assert.match(
    appCss.slice(holidayTodayRule, assignmentDeadlineRule),
    /box-shadow:\s*inset 0 0 0 2px var\(--current-time\)/,
  )
  assert.doesNotMatch(
    appCss,
    /button\.has-(?:holiday|workday)\.(?:selected|today)[\s\S]*box-shadow:\s*inset 0 0 0 2px currentColor/,
  )
  assert.match(
    appCss,
    /\.mini-month-grid button\.today\.deadline-border-assignment > span/,
  )
})
