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

test('desktop month and year cells render two distinct deadline border layers', () => {
  assert.equal(
    appSource.match(/calendarDeadlineBorderKinds\(supplementalEntries\)/g)?.length,
    2,
  )
  assert.equal(appSource.match(/deadline-border-inner-\$\{deadlineBorderSecondary\}/g)?.length, 2)
  assert.match(
    appCss,
    /\.month-cell\[class\*="deadline-border-"\]::before\s*\{[^}]*border-width:\s*1\.5px;[^}]*inset:\s*1px;/s,
  )
  assert.match(
    appCss,
    /\.month-cell\[class\*="deadline-border-inner-"\]::after\s*\{[^}]*border-width:\s*1px;[^}]*inset:\s*4px;/s,
  )
  assert.match(
    appCss,
    /\.mini-month-grid button\[class\*="deadline-border-"\]::before\s*\{[^}]*border-width:\s*1\.5px;[^}]*inset:\s*1px;/s,
  )
  assert.match(
    appCss,
    /\.mini-month-grid button\[class\*="deadline-border-inner-"\]::after\s*\{[^}]*border-width:\s*1px;[^}]*inset:\s*4px;/s,
  )
  assert.match(appCss, /\.month-cell\s*\{[^}]*position:\s*relative;/s)
  assert.match(appCss, /pointer-events:\s*none;/)
  for (const selector of ['month-cell', 'mini-month-grid button']) {
    const selectorPattern = `\\.${selector}`
    assert.match(appCss, new RegExp(`${selectorPattern}\\.deadline-border-assignment\\s*\\{[^}]*var\\(--busy-border\\)`, 's'))
    assert.match(appCss, new RegExp(`${selectorPattern}\\.deadline-border-inner-school-notice\\s*\\{[^}]*var\\(--school-notice-outline\\)`, 's'))
    assert.match(appCss, new RegExp(`${selectorPattern}\\.deadline-border-inner-public-deadline\\s*\\{[^}]*var\\(--other-deadline-outline\\)`, 's'))
  }
  const darkTokens = indexCss.slice(indexCss.indexOf('@media (prefers-color-scheme: dark)'))
  assert.match(darkTokens, /--busy-border:\s*#FFC14D;/)
  assert.match(darkTokens, /--school-notice-outline:\s*#B7A8FF;/)
  assert.match(darkTokens, /--other-deadline-outline:\s*#68D5E5;/)
})

test('desktop month geometry and typography mirror the native macOS grid', () => {
  assert.match(appSource, /desktopMonthGridMetrics\(availableHeight\)/)
  assert.match(appSource, /setDesktopMonthEventRows/)
  assert.match(appSource, /compactCalendarLayout \? 2 : desktopMonthEventRows/)
  assert.match(appSource, /className="month-cell-head"/)
  assert.match(appSource, /calendarWeekOfYear\(dateString\)/)
  assert.match(appSource, /className="month-weekday-desktop"/)
  assert.match(appSource, /className=\{`month-entry-icon \$\{entry\.type\}`\}/)
  assert.match(appSource, /className="month-entry-title"/)
  assert.match(appSource, /<time>\{String\(entry\.time\)\.split\('-'\)\[0\]\}<\/time>/)
  assert.match(
    appCss,
    /\.month-view\.desktop-month-view \.month-calendar\s*\{[^}]*30px[^}]*repeat\(6, var\(--desktop-month-row-height, 81px\)\)[^}]*var\(--desktop-month-grid-height, 520px\)/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-weekday\s*\{[^}]*border-bottom:\s*0\.5px[^}]*font-size:\s*12px;[^}]*font-weight:\s*500;[^}]*min-height:\s*30px;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell\s*\{[^}]*border-bottom:\s*0\.5px[^}]*border-radius:\s*0;[^}]*gap:\s*3px;[^}]*grid-template-rows:\s*22px[^}]*padding:\s*4px 6px;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell-date-button,[\s\S]*font-size:\s*12px;[\s\S]*height:\s*22px;[\s\S]*width:\s*22px;/,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell small\.month-entry\s*\{[^}]*border-radius:\s*3px;[^}]*font-size:\s*9px;[^}]*font-weight:\s*600;[^}]*height:\s*15px;[^}]*padding:\s*0 5px;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-entry time\s*\{[^}]*font-size:\s*8px;[^}]*margin-left:\s*auto;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-entry-icon\s*\{[^}]*flex:\s*0 0 7px;[^}]*font-size:\s*7px;[^}]*height:\s*7px;[^}]*width:\s*7px;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell \.month-entry-overflow\s*\{[^}]*font-size:\s*9px;[^}]*height:\s*15px;[^}]*padding:\s*0 6px;/s,
  )
  const monthAgendaStart = appSource.indexOf('const monthAgendaEntries = [')
  const monthAgendaEnd = appSource.indexOf('const monthEntries =', monthAgendaStart)
  const monthAgendaSource = appSource.slice(monthAgendaStart, monthAgendaEnd)
  assert.ok(monthAgendaSource.indexOf('calendarItems.map') < monthAgendaSource.indexOf('dayState.dayCourses.map'))
  assert.ok(monthAgendaSource.indexOf('dayState.dayCourses.map') < monthAgendaSource.indexOf('supplementalEntries.map'))
})

test('desktop month selection matches the macOS light-blue cell and solid date badge', () => {
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell\.selected,[\s\S]*background:\s*color-mix\(in srgb, var\(--selected-date-fill\) 14%, transparent\);/,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell\.selected \.month-cell-date-button\s*\{[^}]*background:\s*var\(--selected-date-fill\);[^}]*border-radius:\s*50%;[^}]*var\(--selected-date-text\)/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell\.today\.selected \.month-cell-date-button\s*\{[^}]*var\(--selected-date-fill\)[^}]*var\(--current-time\)/s,
  )
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
  assert.match(appCss, /\.settings-color-dot\.school-notice\s*\{[^}]*var\(--school-notice-outline\)/s)
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
