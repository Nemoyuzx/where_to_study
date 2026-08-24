import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const indexCss = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const appCss = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')
const calendarExportSource = readFileSync(new URL('../src-tauri/src/calendar_export.rs', import.meta.url), 'utf8')
const scheduleSource = readFileSync(new URL('../src-tauri/src/schedule.rs', import.meta.url), 'utf8')
const scheduleStoreSource = readFileSync(new URL('../src-tauri/src/schedule_store.rs', import.meta.url), 'utf8')
const tauriSource = readFileSync(new URL('../src-tauri/src/lib.rs', import.meta.url), 'utf8')
const tauriCapabilities = readFileSync(new URL('../src-tauri/capabilities/default.json', import.meta.url), 'utf8')

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
  assert.match(appSource, /date\.getDay\(\) === 1/)
  assert.match(appSource, /formatUiCalendarWeek\(dateString, uiLanguage\)/)
  assert.match(appSource, /formatUiTeachingWeek\(dayState\.weekNumber, uiLanguage\)/)
  assert.match(appSource, /calendarWeekOfYear\(dateString\)/)
  assert.match(appSource, /className="month-weekday-desktop"/)
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
    /\.desktop-month-view \.month-cell \.month-entry\s*\{[^}]*border-radius:\s*3px;[^}]*font-size:\s*9px;[^}]*font-weight:\s*600;[^}]*height:\s*15px;[^}]*padding:\s*0 5px;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-entry time\s*\{[^}]*font-size:\s*8px;[^}]*margin-left:\s*auto;/s,
  )
  assert.match(
    appCss,
    /\.desktop-month-view \.month-cell \.month-entry-overflow\s*\{[^}]*font-size:\s*9px;[^}]*height:\s*15px;[^}]*padding:\s*0 6px;/s,
  )
  assert.match(appSource, /const monthAgendaEntries = \[/)
  assert.match(appSource, /className="month-agenda-entries"/)
  assert.match(appSource, /const monthEntrySummary = summarizeMonthEntries\(/)
  assert.doesNotMatch(appSource, /monthAllDayEntries|month-all-day-entries|month-all-day-entry/)
  assert.match(
    appSource,
    /const compactMarkers = Math\.min\(calendarItems\.length \+ dayState\.dayCourses\.length \+ supplementalEntries\.length, 3\)/,
  )
  assert.match(appSource, /sourceView: 'month'/)
})

test('desktop week all-day row stays in each date column and opens the whole event card', () => {
  assert.match(
    appCss,
    /@media \(max-width: 1100px\)[\s\S]*\.time-calendar\.has-all-day:not\(\.single-day\)\s*\{[^}]*grid-template-rows:\s*auto auto 900px;/s,
  )
  assert.match(appSource, /style=\{\{ gridColumn: dayIndex \+ 3, gridRow: 2 \}\}/)
  assert.match(appSource, /style=\{\{ gridColumn: dayIndex \+ 3, gridRow: visibleAllDayItems \? 3 : 2 \}\}/)
  assert.match(appSource, /className=\{`time-all-day-item \$\{item\.type\}`\}[\s\S]*href=\{item\.url\}/)
  assert.match(appSource, /\{item\.time \? <time>\{item\.time\}<\/time> : null\}/)
  assert.match(appSource, /setCalendarAgendaDialog\(\{ date: dateString, sourceView: calendarView \}\)/)
  assert.match(appSource, /className=\{`time-day-head[^`]*`\}[\s\S]*onClick=\{\(\) => chooseCalendarDate\(dateString\)\}/)
  const pointerStart = appSource.indexOf('function beginCalendarPointerSwipe(')
  const pointerUpdate = appSource.indexOf('function updateCalendarPointerSwipe(', pointerStart)
  const pointerFinish = appSource.indexOf('function finishCalendarPointerSwipe(', pointerUpdate)
  assert.doesNotMatch(appSource.slice(pointerStart, pointerUpdate), /setPointerCapture/)
  assert.match(
    appSource.slice(pointerUpdate, pointerFinish),
    /start\.axis === 'horizontal'[\s\S]*setPointerCapture/,
  )
})

test('desktop calendar navigation, background data, and year scrolling stay independent', () => {
  const transitionStart = appSource.indexOf('function transitionCalendar(')
  const transitionEnd = appSource.indexOf('function beginCalendarSwipe(', transitionStart)
  const transitionSource = appSource.slice(transitionStart, transitionEnd)
  assert.match(transitionSource, /calendarTransition\(/)
  assert.doesNotMatch(transitionSource, /command\(|fetch_/)

  const controllerStart = appSource.indexOf('// Calendar network work is owned by this background controller.')
  const controllerEnd = appSource.indexOf('const todayVisible', controllerStart)
  const controllerSource = appSource.slice(controllerStart, controllerEnd)
  assert.match(controllerSource, /window\.setTimeout\(\(\) => void refreshTarget\(false\), 320\)/)
  assert.match(controllerSource, /calendarDateRef\.current/)
  assert.doesNotMatch(controllerSource, /activePage|calendarView/)

  assert.match(appSource, /className="year-day-popover-scroll"/)
  assert.match(appCss, /\.year-day-popover-scroll\s*\{[^}]*overflow-y:\s*auto;/s)
  assert.match(appCss, /\.year-day-popover\s*\{[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\) auto;/s)
  assert.match(appCss, /\.calendar-motion-exit-next\s*\{[^}]*desktop-calendar-exit-next 180ms/s)
  assert.match(appCss, /\.calendar-motion-exit-previous\s*\{[^}]*desktop-calendar-exit-previous 180ms/s)
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

test('favorite management is a settings subpage that preserves primary navigation', () => {
  assert.match(appSource, /<aside className="side-nav">/)
  assert.match(appSource, /activePage === 'settings' && favoriteManagerOpen/)
  assert.match(appSource, /activePage === 'settings' && !favoriteManagerOpen/)
  assert.match(appSource, /className="favorite-topbar-title"/)
  assert.match(appSource, /aria-label=\{t\('返回设置'\)\}/)
  assert.doesNotMatch(appSource, /aria-hidden=\{favoriteManagerOpen/)
  assert.doesNotMatch(appCss, /\.app-frame\.favorite-manager-open/)
  assert.match(appCss, /\.favorite-manager-page\s*\{[^}]*min-height:/s)
  assert.doesNotMatch(appCss, /\.favorite-manager-page\s*\{[^}]*position:\s*fixed/s)
})

test('wide empty-classroom results switch to two columns', () => {
  assert.match(
    appCss,
    /@media \(min-width: 1180px\)[\s\S]*\.planner-results-panel \.room-list\s*\{[^}]*repeat\(2, minmax\(0, 1fr\)\)/s,
  )
})

test('desktop calendar imports locally persisted favorite event snapshots', () => {
  assert.match(appSource, /function importFavoriteDeadlines\(\)/)
  assert.match(appSource, /command\('import_favorite_deadlines_to_calendar'/)
  assert.match(appSource, /\{t\('导入已收藏日程'\)\}/)
  assert.match(tauriSource, /fn import_favorite_deadlines_to_calendar\(/)
  assert.match(tauriCapabilities, /allow-import-favorite-deadlines-to-calendar/)
  assert.match(calendarExportSource, /fn build_favorite_ics\(/)
  assert.match(calendarExportSource, /DTSTART;TZID=Asia\/Shanghai/)
  assert.match(calendarExportSource, /URL:\{url\}/)
})

test('deprecated exam-week metadata has no desktop presentation or backend application', () => {
  assert.doesNotMatch(appSource, /course\.is_exam|course-exam-badge/)
  assert.doesNotMatch(scheduleSource, /annotate_exam_weeks|EXAM_WEEK_ORDINALS/)
  assert.doesNotMatch(scheduleStoreSource, /annotate_exam_weeks/)
  assert.match(scheduleStoreSource, /course\.exam_week_numbers\.clear\(\)/)
  assert.doesNotMatch(calendarExportSource, /exam_week_numbers|\u3010试】/)
  assert.doesNotMatch(tauriSource, /exam_week_numbers\.contains|desktop_text\("试"/)
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
    /function openYearDayPopover[\s\S]*transitionCalendar\(dateString, 'year'\)/,
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
