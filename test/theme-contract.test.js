import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const indexCss = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const appCss = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')
const tauriSource = readFileSync(new URL('../src-tauri/src/lib.rs', import.meta.url), 'utf8')
const tauriBuildSource = readFileSync(new URL('../src-tauri/build.rs', import.meta.url), 'utf8')
const tauriDeadlineSource = readFileSync(new URL('../src-tauri/src/deadlines.rs', import.meta.url), 'utf8')
const tauriAssignmentSource = readFileSync(new URL('../src-tauri/src/assignments.rs', import.meta.url), 'utf8')
const tauriConfig = readFileSync(new URL('../src-tauri/tauri.conf.json', import.meta.url), 'utf8')
const tauriCapabilities = readFileSync(
  new URL('../src-tauri/capabilities/default.json', import.meta.url),
  'utf8',
)
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
const appleLocalizationSource = readFileSync(
  new URL('../native/apple/Sources/Shared/AppLocalization.swift', import.meta.url),
  'utf8',
)
const appleThemeSource = readFileSync(
  new URL('../native/apple/Sources/Shared/AppTheme.swift', import.meta.url),
  'utf8',
)
const appleSettingsSource = readFileSync(
  new URL('../native/apple/Sources/Shared/SettingsView.swift', import.meta.url),
  'utf8',
)
const appleTimelineSource = readFileSync(
  new URL('../native/apple/Sources/Shared/CalendarTimelineView.swift', import.meta.url),
  'utf8',
)
const appleMobileTimelineSource = readFileSync(
  new URL('../native/apple/Sources/Shared/MobileCalendarTimelineView.swift', import.meta.url),
  'utf8',
)
const appleWidgetDataSource = readFileSync(
  new URL('../native/apple/Sources/WidgetShared/TodayCourseWidgetData.swift', import.meta.url),
  'utf8',
)
const androidPlannerSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/PlannerPage.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidSettingsSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/SettingsPage.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidMainActivitySource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/MainActivity.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidTimelineSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/CalendarTimelineView.kt',
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
const androidCalendarDailyInfoSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/CalendarDailyInfoClient.kt',
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
const androidLocaleSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/AppLocale.kt',
    import.meta.url,
  ),
  'utf8',
)
const androidWidgetSource = readFileSync(
  new URL(
    '../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/TodayCourseWidget.kt',
    import.meta.url,
  ),
  'utf8',
)
const harmonyLocalizationSource = readFileSync(
  new URL('../native/harmony/entry/src/main/ets/common/AppLocalization.ets', import.meta.url),
  'utf8',
)
const harmonyWidgetSource = readFileSync(
  new URL('../native/harmony/entry/src/main/ets/widget/TodayCourseWidgetData.ets', import.meta.url),
  'utf8',
)
const harmonyMobileCalendarSource = readFileSync(
  new URL(
    '../native/harmony/entry/src/main/ets/view/calendar/MobileTeachingCalendarView.ets',
    import.meta.url,
  ),
  'utf8',
)
const harmonyTimelineSource = readFileSync(
  new URL(
    '../native/harmony/entry/src/main/ets/view/calendar/MobileCalendarTimelineView.ets',
    import.meta.url,
  ),
  'utf8',
)
const harmonySettingsSource = readFileSync(
  new URL('../native/harmony/entry/src/main/ets/view/SettingsView.ets', import.meta.url),
  'utf8',
)
const harmonyThemeSource = readFileSync(
  new URL('../native/harmony/entry/src/main/ets/common/AppTheme.ets', import.meta.url),
  'utf8',
)
const harmonyLightColors = readFileSync(
  new URL('../native/harmony/entry/src/main/resources/base/element/color.json', import.meta.url),
  'utf8',
)
const harmonyDarkColors = readFileSync(
  new URL('../native/harmony/entry/src/main/resources/dark/element/color.json', import.meta.url),
  'utf8',
)
const harmonyExpandedCalendarSource = readFileSync(
  new URL(
    '../native/harmony/entry/src/main/ets/view/calendar/ExpandedTeachingCalendarView.ets',
    import.meta.url,
  ),
  'utf8',
)
const harmonyCalendarLogicSource = readFileSync(
  new URL(
    '../native/harmony/entry/src/main/ets/view/calendar/CalendarLogic.ets',
    import.meta.url,
  ),
  'utf8',
)
const harmonyAppModelSource = readFileSync(
  new URL('../native/harmony/entry/src/main/ets/model/AppModel.ets', import.meta.url),
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
  assert.match(appCss, /\.app-frame\s*\{[^}]*grid-template-columns:\s*clamp\(210px, 230px, 250px\) minmax\(0, 1fr\)/s)
  assert.match(appCss, /\.topbar\s*\{[^}]*justify-content:\s*space-between/s)
  assert.doesNotMatch(appCss, /\.topbar\s*\{[^}]*max-width:\s*1200px/s)
  assert.match(appCss, /\.panel\s*\{[^}]*padding:\s*16px/s)
  assert.match(appCss, /\.panel,\s*\.summary-band\s*\{[^}]*border-radius:\s*8px/s)
  assert.match(appCss, /\.app-nav\s*\{[^}]*grid-auto-rows:\s*32px/s)
  assert.match(appCss, /h1\s*\{[^}]*font-size:\s*34px/s)
  assert.match(appCss, /\.settings-layout\s*\{[^}]*repeat\(2, minmax\(0, 1fr\)\)/s)
})

test('Windows and Linux keep native-style daily information without a faux course widget', () => {
  assert.match(appSource, /<WeatherStrip[\s\S]*className="workspace planner-workspace"/)
  assert.match(
    appSource,
    /function WeatherStrip[\s\S]*useState\(false\)[\s\S]*aria-expanded=\{expanded\}/,
  )
  assert.match(appCss, /\.weather-strip-toggle\[aria-expanded='true'\][^}]*weather-strip-chevron/s)
  assert.match(
    appSource,
    /className="month-detail-stack"[\s\S]*<SelectedDaySchedule[\s\S]*<AlmanacCard/,
  )
  assert.match(tauriSource, /fetch_weather/)
  assert.match(tauriSource, /fetch_almanac/)
  assert.doesNotMatch(appSource, /APP_WIDGET_MODE|show_desktop_widget|hide_desktop_widget|course-widget/)
  assert.doesNotMatch(appCss, /course-widget|settings-widget/)
  assert.doesNotMatch(tauriSource, /show_desktop_widget|hide_desktop_widget/)
  assert.doesNotMatch(tauriConfig, /course-widget/)
  assert.doesNotMatch(tauriCapabilities, /show-desktop-widget|hide-desktop-widget/)
  assert.equal(
    existsSync(new URL('../src-tauri/capabilities/course-widget.json', import.meta.url)),
    false,
  )
})

test('desktop weather and period controls keep shared gutters and centered labels', () => {
  assert.match(
    appCss,
    /@media \(min-width: 721px\)[\s\S]*\.planner-page-content > \.weather-strip,[\s\S]*\.planner-page-content \.planner-workspace,[\s\S]*margin:\s*0 16px 16px/s,
  )
  assert.match(appCss, /\.slot-cell\s*\{[^}]*align-content:\s*center/s)
  assert.match(appCss, /\.slot-cell\s*\{[^}]*justify-items:\s*center/s)
  assert.match(appCss, /\.slot-cell\s*\{[^}]*text-align:\s*center/s)
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
  assert.match(appSource, /: t\('联动查询'\)/)
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
  assert.match(appSource, /const calendarHeaderTitle = formatUiCalendarTitle/)
  assert.match(appSource, /const calendarWeekContext = \[/)
  assert.match(appSource, /formatUiCalendarWeek\(calendarDate, uiLanguage\)/)
  assert.match(appSource, /formatUiTeachingWeek\(calendarWeekState\.weekNumber, uiLanguage\)/)
  assert.match(appSource, /className="calendar-week-context"/)
  assert.match(appSource, /className="time-all-day-label"[\s\S]*>\{t\('全天'\)\}</)
  assert.match(appSource, /className="time-all-day-cell"/)
  assert.match(appCss, /\.calendar-view-switch\s*\{[^}]*border:\s*0/s)
  assert.match(appCss, /\.teaching-calendar-main\s*\{[^}]*border:\s*0/s)
  assert.match(
    appCss,
    /@media \(max-width: 720px\)[\s\S]*\.year-calendar\s*\{[^}]*repeat\(2, minmax\(0, 1fr\)\)/s,
  )
})

test('desktop calendar supplements are year-preheated, cached, and rendered in every view', () => {
  assert.match(appSource, /command\('fetch_assignment_calendar'/)
  assert.match(appSource, /command\('fetch_deadline_calendar'/)
  assert.match(appSource, /const targetYear = target\.getFullYear\(\)/)
  assert.match(appSource, /const startDate = `\$\{targetYear\}-01-01`/)
  assert.match(appSource, /const endDate = `\$\{targetYear\}-12-31`/)
  assert.match(appSource, /Calendar network work is owned by this background controller/)
  assert.doesNotMatch(appSource, /useEffect\(\(\) => \{[\s\S]{0,240}activePage !== 'calendar'[\s\S]{0,240}loadCalendarSupplements/)
  assert.match(appSource, /requestedCalendarSupplementRanges/)
  assert.match(tauriAssignmentSource, /fetch_assignment_calendar/)
  assert.match(tauriAssignmentSource, /cached_items\(account_scope\)/)
  assert.match(tauriDeadlineSource, /SOURCE_CACHE_TTL/)
  assert.match(tauriDeadlineSource, /fetch_deadline_calendar/)
  assert.match(appSource, /className="time-all-day-overflow"/)
  assert.match(appSource, /className=\{`time-all-day-item \$\{item\.type\}`\}/)
  assert.match(appSource, /setCalendarAgendaDialog\(\{ date: dateString, sourceView: calendarView \}\)/)
  assert.match(
    appSource,
    /const visibleAllDayItems = visibleCalendarDays\.reduce\([\s\S]*allDayEntriesFor\(dateString\)\.length/,
  )
  assert.match(appSource, /calendar-agenda-dialog/)
  assert.match(appSource, /const monthAgendaEntries = \[/)
  assert.match(appSource, /className=\{`month-entry \$\{entry\.type\}`\}/)
  assert.match(appSource, /className="school-notice"/)
  assert.match(appSource, /type: calendarDeadlineVisualKind\(item\)/)
  assert.match(appSource, /deadlineItemEnabled\(item, enabledDeadlineTypes\)/)
  assert.match(appSource, /sourceView: 'month'/)
  assert.match(appSource, /entries: allDayEntriesFor\(dateString\)/)
  assert.match(
    appSource,
    /className="month-detail-stack"[\s\S]*<SelectedDaySchedule[\s\S]*<AssignmentDeadlineCard[\s\S]*<AlmanacCard[\s\S]*<ContestDeadlineCard/,
  )
  assert.match(appSource, /sourceView: calendarView/)
  assert.match(appSource, /agendaViewLabel\(calendarAgendaDialog\.sourceView, t\)/)
  assert.match(appCss, /\.month-cell \.month-entry\.assignment/)
  assert.match(appCss, /\.month-cell \.month-entry\.school-notice/)
  for (const kind of ['competition', 'conference', 'summer-camp', 'hackathon', 'custom']) {
    assert.match(appCss, new RegExp(`\\.month-cell \\.month-entry\\.${kind}-deadline`))
    assert.match(appCss, new RegExp(`\\.time-all-day-cell > \\.time-all-day-item\\.${kind}-deadline`))
    assert.match(appCss, new RegExp(`\\.calendar-agenda-list \\.${kind}-deadline`))
  }
  assert.match(appCss, /\.popover-supplement-list/)
  assert.match(appCss, /\.popover-supplement-list \.conference-deadline/)
  assert.match(appSource, /calendarDeadlineBorderPriority\(supplementalEntries\)/)
  assert.match(appCss, /\.month-cell\.deadline-border-assignment/)
  assert.match(appCss, /\.month-cell\.deadline-border-school-notice/)
  assert.match(appCss, /\.month-cell\.deadline-border-competition-deadline/)
  assert.match(appCss, /\.mini-month-grid button\.deadline-border-assignment/)
  assert.match(appCss, /\.mini-month-grid button\.deadline-border-school-notice/)
  assert.match(appCss, /\.mini-month-grid button\.deadline-border-competition-deadline/)
  assert.match(
    appCss,
    /\.mini-month-grid button\.today\[class\*="deadline-border-"\] > span/,
  )
})

test('desktop school notices preheat after settings load instead of starting on calendar paging', () => {
  assert.match(appSource, /deadlinePreheatPlan\(settings, `\$\{todayYear\}-01-01`\)/)
  assert.match(appSource, /void preheatDeadlineCalendar\(plan\)/)
  assert.match(appSource, /deadlinePreheatPromiseRef/)
  assert.match(appSource, /deadlineCoveredDatesRef/)
  assert.match(appSource, /scheduleDeadlinePreheat\(plan, DEADLINE_PREFETCH_RETRY_MS\)/)
  assert.match(appSource, /scheduleDeadlinePreheat\(plan, DEADLINE_SOURCE_REFRESH_MS\)/)
  assert.match(appSource, /rangeDates\.every\(\(date\) => deadlineCoveredDatesRef\.current\.has\(date\)\)/)
})

test('native calendars render public deadlines, centered agendas, and shared month-year priority', () => {
  assert.match(appleCalendarSource, /case competition/)
  assert.match(appleCalendarSource, /case conference/)
  assert.match(appleCalendarSource, /case summerCamp/)
  assert.match(appleCalendarSource, /case hackathon/)
  assert.match(appleCalendarSource, /case customDeadline/)
  assert.match(appleCalendarSource, /CalendarDeadlinePresentation\.topTwoDeadlineKinds/)
  assert.match(appleTimelineSource, /showsSecondaryTodayIndicator/)
  assert.doesNotMatch(appleCalendarSource, /calendar\.regular\.month-agenda-dialog/)
  assert.doesNotMatch(appleMobileCalendarSource, /calendar\.mobile\.month-agenda-dialog/)
  assert.match(
    appleCalendarSource,
    /if layout\.hiddenEventCount > 0 \{[\s\S]*?Button \{[\s\S]*?selectMonthDay\(day\)/,
  )
  assert.match(
    appleMobileCalendarSource,
    /if eventLayout\.hiddenEventCount > 0 \{[\s\S]*?Button \{[\s\S]*?requestMonthDaySelection\(day\)/,
  )
  assert.match(appleMobileCalendarSource, /calendar\.mobile\.week-agenda-dialog/)
  assert.match(appleMobileCalendarSource, /if deadlineKinds\.count > 1/)
  assert.match(appleMobileCalendarSource, /if today \{[\s\S]*Circle\(\)[\s\S]*AppTheme\.danger/)

  assert.match(androidCalendarSource, /DeadlineVisualKind\.COMPETITION/)
  assert.match(androidCalendarSource, /DeadlineVisualLogic\.color/)
  assert.match(androidCalendarSource, /showCenteredAgendaDialog/)
  assert.match(androidCalendarSource, /monthCellBorderColor/)
  assert.match(androidCalendarSource, /val showsTodayBadge = today && supplementaryKinds\.isNotEmpty\(\)/)
  assert.match(androidCalendarSource, /LayerDrawable\(arrayOf\(outer, inner\)\)/)
  assert.match(androidCalendarSource, /monthCellInnerBorderWidthDp\(\): Float/)
  assert.match(androidCalendarSource, /activeYearCalendar\?\.updateDays/)
  assert.match(androidCalendarDailyInfoSource, /fun loadCalendarMarkers\(/)
  assert.match(
    androidCalendarDailyInfoSource,
    /if \(assignmentDates\.isNotEmpty\(\)\) \{[\s\S]*?worker\.execute/,
  )
  assert.match(
    androidCalendarDailyInfoSource,
    /if \(deadlineDates\.isNotEmpty\(\)\) \{[\s\S]*?worker\.execute/,
  )
  assert.match(androidYearCalendarSource, /fun borderKinds\(/)
  assert.match(androidYearCalendarSource, /borderKinds\.getOrNull\(1\)/)
  assert.match(androidYearCalendarSource, /today && borderKinds\.isNotEmpty\(\)/)
  assert.match(androidYearCalendarSource, /canvas\.drawCircle\(/)

  assert.match(harmonyMobileCalendarSource, /DeadlineVisual\.borderKinds/)
  assert.match(harmonyMobileCalendarSource, /presentAllDayDialog/)
  assert.match(harmonyMobileCalendarSource, /deadlineBorderLayers\(day/)
  assert.doesNotMatch(harmonyExpandedCalendarSource, /monthAllDayDialogOverlay/)
  assert.match(
    harmonyCalendarLogicSource,
    /supportsAllDayDialog\(mode: CalendarMode\): boolean \{[\s\S]*mode === CalendarMode\.day \|\| mode === CalendarMode\.week/,
  )
  assert.match(harmonyExpandedCalendarSource, /DeadlineVisual\.color\(kind\)/)
  assert.match(harmonyAppModelSource, /assignmentMarkerLoadingDates/)
  assert.match(harmonyAppModelSource, /deadlineMarkerLoadingDates/)
  assert.match(harmonyAppModelSource, /assignmentWork\.finally/)
  assert.match(harmonyAppModelSource, /deadlineWork\.finally/)
  assert.match(harmonyAppModelSource, /this\.assignmentDeadlinesByDate = assignments/)
  assert.match(harmonyAppModelSource, /this\.publicDeadlinesByDate = deadlines/)
})

test('Apple calendars and settings preserve selected-date, timeline, and category-color semantics', () => {
  assert.match(appleThemeSource, /selectedDate: AppThemeColor\(red: 37, green: 99, blue: 235\)/)
  assert.match(appleThemeSource, /selectedDate: AppThemeColor\(red: 29, green: 78, blue: 216\)/)
  assert.match(appleThemeSource, /static let selectedDate = adaptiveColor\(\\\.selectedDate\)/)
  for (const source of [appleCalendarSource, appleMobileCalendarSource, appleTimelineSource]) {
    assert.match(source, /AppTheme\.selectedDate/)
  }
  assert.match(appleMobileTimelineSource, /AppTheme\.selectedDate\.opacity\(0\.10\)/)
  assert.ok(
    appleTimelineSource.indexOf('selectedColumn(dayWidth: dayWidth)') <
      appleTimelineSource.indexOf('dayGrid(width: width, dayWidth: dayWidth)'),
    'wide Apple selected column must be painted before solid and dashed timeline lines',
  )
  assert.ok(
    appleMobileTimelineSource.indexOf('selectedColumn(dayWidth: dayWidth)') <
      appleMobileTimelineSource.indexOf('grid(width: width, dayWidth: dayWidth)'),
    'mobile Apple selected column must be painted before solid and dashed timeline lines',
  )
  assert.match(appleCalendarSource, /topTwoDeadlineKinds/)
  assert.match(appleCalendarSource, /if deadlineKinds\.count > 1/)
  assert.match(appleMobileCalendarSource, /if deadlineKinds\.count > 1/)
  assert.match(appleCalendarSource, /if isToday \{[\s\S]*Circle\(\)/)
  assert.match(appleMobileCalendarSource, /if today \{[\s\S]*Circle\(\)/)

  assert.match(appleSettingsSource, /deadlineLegend\("课程作业 DDL", color: AppTheme\.assignment\)/)
  for (const [title, color] of [
    ['学科竞赛 DDL', 'competitionDeadline'],
    ['校内竞赛通知', 'schoolNotice'],
    ['学术会议/期刊专题 DDL', 'conferenceDeadline'],
    ['夏令营/预推免 DDL', 'summerCampDeadline'],
    ['黑客松 DDL', 'hackathonDeadline'],
  ]) {
    assert.match(
      appleSettingsSource,
      new RegExp(`featureToggle\\(\\s*"${title}"[\\s\\S]*?markerColor: AppTheme\\.${color}\\s*\\)`),
      `${title} must display its own ${color} marker beside the matching switch`,
    )
  }
  assert.match(
    appleSettingsSource,
    /Text\(model\.localized\("自定义日程源"\)\)[\s\S]*?Circle\(\)[\s\S]*?\.fill\(AppTheme\.customDeadline\)/,
  )
  assert.match(appleSettingsSource, /Toggle\([\s\S]*\.toggleStyle\(\.switch\)/)
  assert.match(appleSettingsSource, /ForEach\(1 \.\.\. TodayCourseWidgetData\.maximumCourseLimit/)
  assert.match(appleSettingsSource, /Picker\("预览尺寸"/)
  assert.ok(
    (appleSettingsSource.match(/\.pickerStyle\(\.segmented\)/g) || []).length >= 4,
    'Apple campus, language, widget count, and preview size must all use segmented controls',
  )

  assert.match(
    appleTimelineSource,
    /for minute in CalendarTimelineLogic\.wholeHourMinutes[\s\S]*context\.stroke\(hourLines, with: \.color\(AppTheme\.border\), lineWidth: 1\)/,
  )
  assert.match(
    appleTimelineSource,
    /for minute in CalendarTimelineLogic\.nonHourlyCourseBoundaryMinutes[\s\S]*StrokeStyle\(lineWidth: 0\.7, dash: \[4, 4\]\)/,
  )
  assert.equal(
    appleTimelineSource.match(/for minute in CalendarTimelineLogic\.wholeHourMinutes/g)?.length,
    2,
    'axis and day areas must both draw solid whole-hour lines',
  )
  assert.equal(
    appleTimelineSource.match(/for minute in CalendarTimelineLogic\.nonHourlyCourseBoundaryMinutes/g)
      ?.length,
    2,
    'axis and day areas must both draw dashed non-hour course boundaries',
  )
})

test('Android and Harmony mobile day-week chrome follows the iOS presentation contract', () => {
  assert.match(androidLocaleSource, /const val oneStepSmallerScale = 0\.92f/)
  assert.match(
    androidLocaleSource,
    /fontScale = AppTypography\.adjustedFontScale\(base\.resources\.configuration\.fontScale\)/,
  )
  assert.match(
    androidMainActivitySource,
    /override fun attachBaseContext\(newBase: Context\)[\s\S]*super\.attachBaseContext\(AppLocale\.wrap\(newBase, languageCode\)\)/,
  )

  const androidAgendaSection = androidCalendarSource.match(
    /private fun dayWeekAgendaSection\([\s\S]*?private fun compactCourseArea/,
  )?.[0] ?? ''
  assert.match(androidAgendaSection, /firstOrNull \{ sameDay\(it\.date, selectedDate\) \}/)
  assert.match(androidAgendaSection, /calendar_day_week_agenda_content/)
  assert.match(
    androidAgendaSection,
    /visibility = if \(TeachingCalendarLogic\.shouldShowDayWeekCourseContent\(/,
  )
  assert.match(androidAgendaSection, /val indicator = ImageView\(activity\)/)
  assert.match(androidAgendaSection, /setImageResource\(R\.drawable\.ic_chevron_down\)/)
  assert.match(androidAgendaSection, /TransitionManager\.beginDelayedTransition/)
  assert.match(androidAgendaSection, /addView\(compactCourseArea\(selectedDay\.date, compact\)\)/)
  assert.ok(
    androidAgendaSection.indexOf('addView(allDayStrip(days, compact))') >
      androidAgendaSection.indexOf('calendar_day_week_agenda_content'),
    'Android all-day events must remain outside the course-only collapsed container',
  )

  assert.match(
    androidCalendarSource,
    /private fun singleDayAllDayStrip\([\s\S]*?\): HorizontalScrollView = HorizontalScrollView\(activity\)/,
  )
  const androidAllDaySection = androidCalendarSource.match(
    /private fun allDayStrip\([\s\S]*?private fun singleDayAllDayStrip/,
  )?.[0] ?? ''
  assert.match(androidAllDaySection, /if \(days\.size == 1\)/)
  assert.match(androidAllDaySection, /days\.forEach \{ day ->/)
  assert.match(androidAllDaySection, /val compactWeek = compact && days\.size > 1/)
  assert.match(
    androidCalendarSource,
    /fun agendaVisibleItemCount\([\s\S]*if \(compactWeek\) 1 else 3/,
  )
  assert.match(androidTimelineSource, /if \(compact\) return 56/)
  assert.match(androidCalendarSource, /const val bottomNavigationContentInsetDp = 78/)
  assert.match(
    androidCalendarSource,
    /if \(usesBottomNavigation\) bottomNavigationContentInsetDp else 0/,
  )

  const harmonyTimelineSection = harmonyMobileCalendarSource.match(
    /timelineContent\(renderMode:[\s\S]*?private timelineDays/,
  )?.[0] ?? ''
  assert.match(harmonyTimelineSection, /timelineCourseSummaryDate\(renderMode, renderDate\)/)
  assert.match(
    harmonyTimelineSection,
    /if \(this\.courseSectionExpanded && this\.coursesOn\([\s\S]*this\.selectedDateCourses/,
  )
  assert.ok(
    harmonyTimelineSection.indexOf('this.allDayItems(renderMode, renderDate, interactive)') >
      harmonyTimelineSection.indexOf('if (this.courseSectionExpanded)'),
    'Harmony all-day events must remain visible when only the course list is collapsed',
  )
  assert.match(harmonyMobileCalendarSource, /dayAllDayItems\(renderDate:/)
  assert.match(harmonyMobileCalendarSource, /allDayItemsOn\(renderDate\)\.slice\(0, 3\)/)
  assert.match(
    harmonyMobileCalendarSource,
    /weekAllDayItems\(renderDate:[\s\S]*ForEach\(this\.weekDates\(renderDate\)[\s\S]*\.fontSize\(9\.5\)[\s\S]*\.height\(40\)/,
  )
  assert.match(harmonyMobileCalendarSource, /this\.presentAllDayDialog\(day, CalendarMode\.week\)/)
  assert.match(
    harmonyCalendarLogicSource,
    /static agendaDialogChangesSelectedDate\(mode: CalendarMode\): boolean \{\s*return mode === CalendarMode\.day/,
  )
})

test('Harmony selected dates, deadline legends, switches, and timeline lines stay visible', () => {
  const light = JSON.parse(harmonyLightColors).color
  const dark = JSON.parse(harmonyDarkColors).color
  const colorValue = (colors, name) => colors.find((entry) => entry.name === name)?.value
  assert.equal(colorValue(light, 'app_selected_date'), '#2563EB')
  assert.equal(colorValue(dark, 'app_selected_date'), '#1D4ED8')
  assert.match(harmonyThemeSource, /static selectedDate\(\): Resource/)
  assert.match(harmonyThemeSource, /static assignment\(\): Resource/)
  assert.match(harmonyThemeSource, /static schoolNotice\(\): Resource/)
  assert.match(harmonyThemeSource, /static publicDeadline\(\): Resource/)

  assert.match(
    harmonyMobileCalendarSource,
    /backgroundColor\(day\.equals\(this\.selectedDate\(\)\) \? AppTheme\.selectedDate\(\)/,
  )
  assert.match(
    harmonyMobileCalendarSource,
    /backgroundColor\(day\.equals\(this\.selectedDate\(\)\) \?\s*AppTheme\.selectedDate\(\)/,
  )
  assert.match(
    harmonyExpandedCalendarSource,
    /backgroundColor\(day\.equals\(this\.selectedDate\(\)\) \?\s*AppTheme\.selectedDate\(\)/,
  )
  assert.match(harmonyMobileCalendarSource, /DeadlineVisual\.borderKinds/)
  assert.match(harmonyMobileCalendarSource, /deadlineBorderLayers\(day, 10, 7, 6\)/)
  assert.match(harmonyMobileCalendarSource, /deadlineBorderLayers\(day, 4, 2, 4\)/)
  assert.match(harmonyExpandedCalendarSource, /deadlineBorderLayers\(day/)
  assert.match(harmonyMobileCalendarSource, /width: index === 0 \? 1\.5 : 1/)
  assert.match(harmonyExpandedCalendarSource, /width: index === 0 \? 1\.5 : 1/)
  assert.match(harmonyCalendarLogicSource, /static showsTodayMarker\(isToday: boolean\)/)

  const selectedLayer = harmonyTimelineSource.indexOf("'selected-column.'")
  const hourLayer = harmonyTimelineSource.indexOf('// 小时线', selectedLayer)
  const slotLayer = harmonyTimelineSource.indexOf('// 课程节次边界', hourLayer)
  assert.ok(selectedLayer >= 0 && selectedLayer < hourLayer && hourLayer < slotLayer)
  assert.match(harmonyTimelineSource, /'axis-hour-line\.'/)
  assert.match(harmonyTimelineSource, /'axis-slot-line\.'/)
  assert.match(harmonyTimelineSource, /style: BorderStyle\.Dashed/)

  assert.match(harmonySettingsSource, /deadlineLegend\('课程作业 DDL', AppTheme\.assignment\(\)\)/)
  assert.match(harmonySettingsSource, /'校内竞赛通知'[\s\S]*AppTheme\.schoolNotice\(\), true/)
  assert.match(harmonySettingsSource, /'学科竞赛 DDL'[\s\S]*AppTheme\.competitionDeadline\(\), true/)
  assert.match(harmonySettingsSource, /'学术会议\/期刊专题 DDL'[\s\S]*AppTheme\.conferenceDeadline\(\), true/)
  assert.match(harmonySettingsSource, /'夏令营\/预推免 DDL'[\s\S]*AppTheme\.summerCampDeadline\(\), true/)
  assert.match(harmonySettingsSource, /'黑客松 DDL'[\s\S]*AppTheme\.hackathonDeadline\(\), true/)
  assert.match(harmonySettingsSource, /'显示自定义日程'[\s\S]*AppTheme\.customDeadline\(\), true/)
  assert.match(harmonySettingsSource, /Toggle\(\{ type: ToggleType\.Switch, isOn: isOn \}\)/)
  assert.doesNotMatch(harmonySettingsSource, /\bSelect\(/)
  assert.match(harmonySettingsSource, /segmentedOptions\(labels: string\[\]/)
})

test('desktop calendar supplement commands are exposed by the Tauri capability manifest', () => {
  const capability = JSON.parse(tauriCapabilities)
  const commands = [
    'fetch_deadlines',
    'fetch_assignments',
    'fetch_deadline_calendar',
    'fetch_assignment_calendar',
    'fetch_custom_deadline_calendar',
    'fetch_important_events',
    'fetch_shuttle_bus',
  ]

  for (const command of commands) {
    assert.match(tauriBuildSource, new RegExp(`"${command}"`))
    assert.ok(capability.permissions.includes(`allow-${command.replaceAll('_', '-')}`))
    assert.equal(
      existsSync(new URL(`../src-tauri/permissions/autogenerated/${command}.toml`, import.meta.url)),
      true,
    )
  }
})

test('desktop interface language is persistent and updates the tray without translating API data', () => {
  assert.match(appSource, /resolvedUiLanguage\(settings\.uiLanguage/)
  assert.match(appSource, /\['system', t\('跟随系统'\)\]/)
  assert.match(appSource, /\['zh-Hans', t\('简体中文'\)\]/)
  assert.match(appSource, /\['en', 'English'\]/)
  assert.match(appSource, /command\('set_interface_language', uiLanguage\)/)
  assert.match(tauriSource, /fn set_interface_language/)
  assert.match(tauriSource, /DESKTOP_INTERFACE_ENGLISH/)
  assert.match(appSource, /item\.title/)
  assert.match(appSource, /item\.name/)
  assert.match(appSource, /day\.weather_day/)
})

test('native graphical clients and supported widgets share the system Chinese English boundary', () => {
  assert.match(appleLocalizationSource, /case system/)
  assert.match(appleLocalizationSource, /case simplifiedChinese = "zh-Hans"/)
  assert.match(appleLocalizationSource, /case english = "en"/)
  assert.match(appleLocalizationSource, /hasPrefix\("zh"\)/)
  assert.match(appleWidgetDataSource, /languageDefaultsKey = "appLanguage"/)
  assert.match(appleWidgetDataSource, /UserDefaults\(suiteName: appGroupIdentifier\)/)

  assert.match(androidLocaleSource, /SYSTEM\("system"\)/)
  assert.match(androidLocaleSource, /SIMPLIFIED_CHINESE\("zh-Hans"\)/)
  assert.match(androidLocaleSource, /ENGLISH\("en"\)/)
  assert.match(androidWidgetSource, /AppLocale\.wrap\(context, preferences\.languageCode\)/)

  assert.match(harmonyLocalizationSource, /system = 'system'/)
  assert.match(harmonyLocalizationSource, /simplifiedChinese = 'zh-Hans'/)
  assert.match(harmonyLocalizationSource, /english = 'en'/)
  assert.match(harmonyWidgetSource, /prefs\.language === AppLanguage\.english/)
  assert.match(appleCalendarSource, /Text\(item\.name\)/)
  assert.match(androidLocaleSource, /third-party content/)
  assert.match(harmonyLocalizationSource, /API 返回/)
})

test('native Android year calendar follows the compact iOS mini-month layout', () => {
  assert.match(
    androidCalendarSource,
    /private fun yearView\(onDateChanged: \(\) -> Unit\): LinearLayout = LinearLayout\(activity\)\.apply/,
  )
  assert.match(androidCalendarSource, /text = "颜色越深表示当天课程越多，彩色边框表示作业与 DDL"/)
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

test('native Android compact surfaces and timeline keep the iOS density contracts', () => {
  assert.match(
    androidUiSupportSource,
    /fun surface\([\s\S]*showsBorder: Boolean = true[\s\S]*if \(showsBorder\) Palette\.border else Color\.TRANSPARENT/,
  )
  assert.doesNotMatch(androidPlannerSource, /surface\(activity\)\.apply/)
  assert.doesNotMatch(androidSettingsSource, /surface\(activity\)\.apply/)
  assert.match(androidPlannerSource, /roundedBackground\([\s\S]*Palette\.border/)
  assert.match(androidSettingsSource, /roundedBackground\([\s\S]*Palette\.border/)
  assert.match(androidPlannerSource, /text = "联动查询"[\s\S]*textSize = 28f/)
  assert.match(androidSettingsSource, /text = "设置"[\s\S]*textSize = 28f/)
  assert.doesNotMatch(androidPlannerSource, /setImageResource\(R\.drawable\.ic_refresh\)/)
  assert.match(
    androidPlannerSource,
    /private fun fetchButton\(\)[\s\S]*gravity = Gravity\.CENTER[\s\S]*contentDescription = if[\s\S]*"获取空教室信息"[\s\S]*addView\(label\)/,
  )
  assert.match(
    androidPlannerSource,
    /addView\(sectionTitle\([\s\S]*"空教室结果"[\s\S]*R\.drawable\.ic_section_check/,
  )
  assert.match(androidPlannerSource, /scrollBarStyle = View\.SCROLLBARS_INSIDE_OVERLAY/)
  assert.match(androidSettingsSource, /scrollBarStyle = View\.SCROLLBARS_INSIDE_OVERLAY/)
  assert.match(androidCalendarSource, /scrollBarStyle = View\.SCROLLBARS_INSIDE_OVERLAY/)
  assert.match(androidTimelineSource, /scrollBarStyle = View\.SCROLLBARS_INSIDE_OVERLAY/)
  assert.match(androidTimelineSource, /setBackgroundColor\(Palette\.surface\)/)
  assert.match(androidTimelineSource, /canvas\.drawColor\(Palette\.surface\)/)
  assert.match(androidTimelineSource, /showCourseSlots = true/)
  assert.match(androidTimelineSource, /DashPathEffect/)
  assert.match(androidTimelineSource, /density \* 0\.5f/)
  assert.doesNotMatch(
    androidMainActivitySource,
    /Palette\.surfaceVariant,\s*Palette\.border,\s*radius = 30/,
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
  assert.match(appSource, /handleMonthCalendarKeyDown/)
  assert.match(appSource, /month-expansion-accessibility-action/)
  assert.match(appSource, /month-expansion-accessibility-action[\s\S]*tabIndex=\{-1\}/)
  assert.match(appCss, /\.assistive-only\s*\{[^}]*clip-path:\s*inset\(50%\)/s)
  assert.match(appSource, /aria-label=\{t\('月历'\)\}/)
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
    /Capsule\(\)[\s\S]*rotationEffect\(\.degrees\(-24 \* expansionProgress\)\)[\s\S]*rotationEffect\(\.degrees\(24 \* expansionProgress\)\)/,
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
  assert.match(
    appleCalendarSource,
    /SpatialTapGesture\(\s*count: 2[\s\S]*?case \.first:[\s\S]*?changeMode\(to: \.month, selecting: day\)/,
  )
  assert.match(
    appleCalendarSource,
    /requestModeChange\(to rawValue: String,[\s\S]*?prepareModeTransition[\s\S]*?await Task\.yield\(\)[\s\S]*?commitModeTransition/,
  )
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

test('privacy and local data remain the final settings panels', () => {
  assert.ok(
    appSource.indexOf('className="panel settings-about"') <
      appSource.indexOf('className="panel settings-actions settings-local-data"'),
  )
  assert.match(appSource, /<h2>\{t\('关于本应用'\)\}<\/h2>/)
})

test('interface language settings stay directly above privacy and local data panels', () => {
  const languagePanel = appSource.indexOf('className="panel settings-language"')
  const localDataPanel = appSource.indexOf('className="panel settings-actions settings-local-data"')
  const privacyPanel = appSource.indexOf('className="panel settings-about"')

  assert.ok(languagePanel > appSource.indexOf('className="panel settings-daily-info"'))
  assert.ok(languagePanel < privacyPanel)
  assert.ok(privacyPanel < localDataPanel)
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

test('collapsed Android foldable rail centers icons inside selection frames', () => {
  const presentation = androidMainActivitySource.match(
    /private fun applyNavigationRailTabPresentation[\s\S]*?private fun updateNavigationRailPresentation/,
  )?.[0] ?? ''
  const collapsedBranch = presentation.match(
    /if \(navigationRailCollapsed\) \{([\s\S]*?)\} else/,
  )?.[1] ?? ''
  assert.match(
    collapsedBranch,
    /setCompoundDrawablesRelativeWithIntrinsicBounds\(\s*0,\s*0,\s*0,\s*0,?\s*\)/,
  )
  assert.match(collapsedBranch, /view\.foreground = getDrawable\(destination\.iconResource\)/)
  assert.match(collapsedBranch, /view\.foregroundGravity = Gravity\.CENTER/)
  assert.doesNotMatch(
    collapsedBranch,
    /setCompoundDrawablesRelativeWithIntrinsicBounds\(\s*destination\.iconResource,\s*0,\s*0,\s*0/,
  )
  assert.doesNotMatch(
    collapsedBranch,
    /setCompoundDrawablesRelativeWithIntrinsicBounds\(\s*0,\s*destination\.iconResource/,
  )
  assert.match(presentation, /view\.gravity = if \(navigationRailCollapsed\) Gravity\.CENTER/)
  assert.match(androidMainActivitySource, /view\.foregroundTintList = ColorStateList\.valueOf\(contentColor\)/)
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
    assertContrast(tokens, '--other-deadline-text', '--other-deadline-surface')
    assertContrast(tokens, '--school-notice-text', '--school-notice-surface')
    for (const kind of ['competition', 'conference', 'summer-camp', 'hackathon', 'custom']) {
      assertContrast(tokens, `--${kind}-deadline-text`, `--${kind}-deadline-surface`)
    }
  }
})
