import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const text = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')

const app = text('../src/App.jsx')
const queryHub = text('../src/QueryHub.jsx')
const queryDomain = text('../src/query-domain.js')
const tauriDeadlines = text('../src-tauri/src/deadlines.rs')
const tauriShuttle = text('../src-tauri/src/shuttle.rs')
const tauriCapability = text('../src-tauri/capabilities/default.json')

const appleQuery = text('../native/apple/Sources/Shared/InformationQueriesView.swift')
const appleAppModel = text('../native/apple/Sources/Shared/AppModel.swift')
const appleRoot = text('../native/apple/Sources/Shared/RootView.swift')
const appleDeadlineClient = text('../native/apple/Sources/Shared/CalendarDeadlineClient.swift')
const appleShuttle = text('../native/apple/Sources/Shared/ShuttleBusClient.swift')
const appleSettings = text('../native/apple/Sources/Shared/SettingsView.swift')
const appleDesktopCalendar = text('../native/apple/Sources/Shared/TeachingCalendarView.swift')
const appleMobileCalendar = text('../native/apple/Sources/Shared/MobileTeachingCalendarView.swift')

const androidQuery = text('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/InformationQueryPage.kt')
const androidMain = text('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/MainActivity.kt')
const androidDeadlineClient = text('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/CalendarDailyInfoClient.kt')
const androidShuttle = text('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/ShuttleBusClient.kt')
const androidSettings = text('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/SettingsPage.kt')
const androidCalendar = text('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/TeachingCalendarPage.kt')

const harmonyQuery = text('../native/harmony/entry/src/main/ets/view/QueryView.ets')
const harmonyRoot = text('../native/harmony/entry/src/main/ets/view/RootView.ets')
const harmonySections = text('../native/harmony/entry/src/main/ets/common/AppSection.ets')
const harmonyLogic = text('../native/harmony/entry/src/main/ets/common/QueryLogic.ets')
const harmonyModel = text('../native/harmony/entry/src/main/ets/model/AppModel.ets')
const harmonyDeadlineClient = text('../native/harmony/entry/src/main/ets/net/CalendarDailyInfoClient.ets')
const harmonyShuttle = text('../native/harmony/entry/src/main/ets/net/ShuttleBusClient.ets')
const harmonySettings = text('../native/harmony/entry/src/main/ets/view/SettingsView.ets')
const harmonyCalendar = text('../native/harmony/entry/src/main/ets/view/CalendarSectionView.ets')

const corePublicQueries = text('../where-to-study-core/src/public_queries.rs')
const cliMain = text('../wts-cli/src/main.rs')
const cliCommands = text('../wts-cli/src/commands.rs')
const tuiMain = text('../wts-tui/src/main.rs')
const tuiApp = text('../wts-tui/src/app.rs')
const tuiQuery = text('../wts-tui/src/ui/query.rs')
const tuiCalendar = text('../wts-tui/src/ui/calendar.rs')

const assertOrdered = (source, fragments) => {
  let cursor = -1
  for (const fragment of fragments) {
    const next = source.indexOf(fragment, cursor + 1)
    assert.notEqual(next, -1, `missing ordered fragment: ${fragment}`)
    assert.ok(next > cursor, `out-of-order fragment: ${fragment}`)
    cursor = next
  }
}

test('every graphical platform exposes query as a primary destination between calendar and settings', () => {
  assertOrdered(app, ["id: 'planner'", "id: 'calendar'", "id: 'query'", "id: 'settings'"])
  assert.match(app, /activePage === 'query'[\s\S]*<QueryHub/)
  assert.doesNotMatch(app, /openQueryHub|queryHubOpen|queryHubReturnPage/)
  assert.match(queryHub, /role="tab"[\s\S]*'班车查询'/)
  assert.match(queryHub, /role="tab"[\s\S]*'重要事件'/)

  assertOrdered(appleAppModel, ['case planner', 'case calendar', 'case queries', 'case settings'])
  assert.match(appleRoot, /case \.queries:\s+InformationQueriesView\(/)
  assert.match(appleRoot, /shuttleStore: modeServices\.shuttle/)
  assert.match(appleRoot, /eventQueryStore: modeServices\.importantEvents/)
  assert.doesNotMatch(appleSettings, /InformationQueriesView|InformationQueriesPresentation/)
  assert.doesNotMatch(appleDesktopCalendar, /InformationQueriesView|InformationQueriesPresentation/)
  assert.doesNotMatch(appleMobileCalendar, /InformationQueriesView|InformationQueriesPresentation/)
  assert.match(appleQuery, /Picker\("查询类型"/)

  assertOrdered(androidMain, ['PLANNER("空教室"', 'CALENDAR("教学日历"', 'QUERY("查询"', 'SETTINGS("设置"'])
  assert.match(androidMain, /Destination\.QUERY ->[\s\S]*InformationQueryPage\(/)
  assert.doesNotMatch(androidSettings, /openInformationQuery|information_query_entry/)
  assert.doesNotMatch(androidCalendar, /openInformationQuery|calendar_information_query_menu_item/)
  assert.match(androidCalendar, /fun build\(\): View = phoneBuild\(\)/)
  assert.match(androidCalendar, /addView\(calendarImportButton\(compact = true\)\)/)
  assert.match(androidQuery, /SHUTTLE\("班车查询"\)/)
  assert.match(androidQuery, /IMPORTANT_EVENTS\("重要事件"\)/)

  assertOrdered(harmonySections, ['AppSection.planner', 'AppSection.calendar', 'AppSection.query', 'AppSection.settings'])
  assert.match(harmonyRoot, /currentSection === AppSection\.query[\s\S]*QueryView\(\)/)
  assert.doesNotMatch(harmonyRoot, /queryVisible|setQueryVisible/)
  assert.doesNotMatch(harmonySettings, /onQueryVisibilityChanged|打开查询/)
  assert.doesNotMatch(harmonyCalendar, /onQueryVisibilityChanged|onQueryRequested/)
  assert.match(harmonyQuery, /ForEach\(QueryPageContract\.tabs/)
  assert.match(harmonyQuery, /QueryPageContract\.tabTitle\(tab\)/)
  assert.match(harmonyLogic, /'班车查询'/)
  assert.match(harmonyLogic, /'重要事件'/)
})

test('fixed shuttle clients reject redirects and show only an active timetable', () => {
  assert.match(tauriShuttle, /SHUTTLE_URL: &str = "https:\/\/where-to-study\.cn\/api\/shuttle-bus"/)
  assert.match(tauriShuttle, /redirect\(reqwest::redirect::Policy::none\(\)\)/)
  assert.match(queryDomain, /shuttlePeriodState\(period, today\) === 'active'/)
  assert.doesNotMatch(queryDomain, /periodState\(period, today\) === 'upcoming'\)\?\.key/)

  assert.match(appleShuttle, /ShuttleBusRedirectDelegate\(\)/)
  assert.match(appleShuttle, /completionHandler\(nil\)/)
  assert.match(appleShuttle, /static func activeSchedules/)
  assert.match(appleShuttle, /\$0\.period\.contains\(dateString\)/)

  assert.match(androidShuttle, /FixedPublicJsonTransport::fetch/)
  assert.match(androidShuttle, /未找到当前生效的班车时刻表/)
  assert.doesNotMatch(androidShuttle, /upcoming.*routes/s)

  assert.match(harmonyShuttle, /periodState\(period, date\) === ShuttleBusPeriodState\.active/)
  assert.match(harmonyShuttle, /state !== ShuttleBusPeriodState\.active/)
  assert.match(harmonyShuttle, /spec\.maxRedirects = 0/)
  assert.match(harmonyQuery, /今日暂无生效的班车时刻表/)
})

test('important-event queries retain metadata, hide ended items, and never include assignments', () => {
  for (const source of [queryDomain, appleQuery, androidQuery, harmonyLogic]) {
    assert.match(source, /categor/i)
    assert.match(source, /archived|show.*ended|showsEnded/i)
  }
  for (const source of [appleDeadlineClient, androidDeadlineClient, harmonyDeadlineClient]) {
    assert.match(source, /categories/)
    assert.match(source, /tags/)
    assert.match(source, /level/)
    assert.match(source, /location/)
    assert.match(source, /description/)
  }
  assert.match(tauriDeadlines, /parse_important_public_events/)
  assert.match(tauriDeadlines, /categories: normalized_labels/)
  assert.match(queryHub, /command\('fetch_important_events'\)/)
  assert.doesNotMatch(queryHub, /fetch_assignments|fetch_assignment_calendar/)
  assert.doesNotMatch(appleQuery, /assignmentsByDate|fetchAssignments/)
  assert.doesNotMatch(androidQuery, /assignmentClient|loadAssignments/)
  assert.doesNotMatch(harmonyQuery, /assignmentDeadlines|loadAssignments/)
})

test('desktop important events render a small first batch and append near the scroll edge', () => {
  assert.match(queryHub, /importantEventVisibleCount\([\s\S]*eventRenderWindow,[\s\S]*eventRenderKey/)
  assert.match(queryHub, /if \(current\.key !== eventRenderKey\) return current/)
  assert.match(queryHub, /new IntersectionObserver[\s\S]*rootMargin: '320px 0px'/)
  assert.match(queryHub, /eventLoadSentinelRef[\s\S]*nextImportantEventVisibleCount/)
  assert.doesNotMatch(queryHub, /className="event-load-more"/)
})

test('all graphical clients incrementally render important events without paging the network', () => {
  assert.match(appleQuery, /ImportantEventIncrementalRendering[\s\S]*static let batchSize = 20/)
  assert.match(appleQuery, /ForEach\(Array\(visibleItems\.enumerated\(\)\)/)
  assert.match(appleQuery, /\.onAppear[\s\S]*loadMoreImportantEventsIfNeeded/)

  assert.match(androidQuery, /INITIAL_EVENT_COUNT = 20/)
  assert.match(androidQuery, /EVENT_PAGE_SIZE = 20/)
  assert.match(androidQuery, /setOnScrollChangeListener[\s\S]*appendImportantEventPage/)
  assert.doesNotMatch(androidQuery, /text = "加载更多"/)

  assert.match(harmonyLogic, /static readonly pageSize: number = 20/)
  assert.match(harmonyQuery, /List\(\{ space: 9, scroller: this\.eventScroller \}\)/)
  assert.match(harmonyQuery, /\.onScrollIndex[\s\S]*this\.appendEventPage\(end\)/)

  for (const source of [queryHub, appleQuery, androidQuery, harmonyQuery]) {
    assert.doesNotMatch(source, /fetch_important_events[\s\S]{0,120}(?:visibleCount|requestedVisibleEventCount)/)
  }
})

test('event-query network loading is independent from segment animation and shared where available', () => {
  assert.match(queryHub, /void loadShuttle\(\)[\s\S]*void loadImportantEvents\(\)/)
  assert.doesNotMatch(queryHub, /useEffect\([^)]*tab/)
  assert.match(appleQuery, /async let shuttleLoad/)
  assert.match(appleQuery, /async let eventLoad/)
  assert.doesNotMatch(appleQuery, /\.task\(id: selectedMode\)/)
  assert.match(androidQuery, /dailyInfoRepository\.loadImportantEvents\(\)/)
  assert.match(harmonyModel, /calendarDailyInfoClient\.fetchImportantEvents/)
  assert.doesNotMatch(harmonyQuery, /new CalendarDailyInfoClient/)
})

test('Tauri exposes pinned query commands through generated permissions', () => {
  const capability = JSON.parse(tauriCapability)
  for (const command of ['fetch_important_events', 'fetch_shuttle_bus']) {
    assert.ok(capability.permissions.includes(`allow-${command.replaceAll('_', '-')}`))
    assert.equal(
      existsSync(new URL(`../src-tauri/permissions/autogenerated/${command}.toml`, import.meta.url)),
      true,
    )
  }
})

test('CLI and TUI reuse the secure Core query and favorite contract', () => {
  assert.match(corePublicQueries, /SHUTTLE_URL: &str = "https:\/\/where-to-study\.cn\/api\/shuttle-bus"/)
  assert.match(corePublicQueries, /redirect\(reqwest::redirect::Policy::none\(\)\)/)
  assert.match(corePublicQueries, /fn active_shuttle_notice/)
  assert.match(corePublicQueries, /filter_important_events/)
  assert.match(corePublicQueries, /save_favorite_events/)
  assert.match(corePublicQueries, /source_type != "assignment"/)

  assert.match(cliMain, /Shuttle \{/)
  assert.match(cliMain, /Events \{/)
  assert.match(cliCommands, /public_queries::fetch_shuttle_bus/)
  assert.match(cliCommands, /public_queries::fetch_important_events/)

  assert.match(tuiApp, /TAB_LABELS: \[&str; 6\] = \["概览", "课表", "空教室", "日历", "查询", "设置"\]/)
  assert.match(tuiMain, /4 => Tab::Query/)
  assert.match(tuiMain, /if index == 4 \{\s*ensure_query_loaded\(app, tx\)/)
  assert.doesNotMatch(tuiMain, /KeyCode::Char\('i'\).*selected_tab_index/)
  assert.match(tuiQuery, /QuerySection::Shuttle/)
  assert.match(tuiQuery, /QuerySection::Events/)
  assert.match(tuiQuery, /app\.query_category/)
  assert.match(tuiQuery, /app\.query_include_ended/)
})

test('TUI teaching calendar renders conferences from the shared important-event cache', () => {
  assert.match(tuiMain, /refresh_events\(&mut app, &tx, false\)/)
  assert.match(tuiCalendar, /app\.all_query_events\(\)/)
  assert.match(tuiCalendar, /"conference" \| "journal_special_issue"/)
  assert.match(tuiCalendar, /会=会议/)
})

test('Tauri calendar scheduling uses one conference-aware built-in deadline gate', () => {
  assert.match(app, /const builtInDeadlineSourcesActive = builtInDeadlineSourcesEnabled\(settings\)/)
  assert.doesNotMatch(app, /const anyDeadlineTypeEnabled/)
  assert.match(
    app,
    /deadlinePreheatPlan\(settings,[\s\S]*?\}, \[\s*builtInDeadlineSourcesActive,\s*settingsLoaded,\s*todayYear,\s*\]\)/,
  )
  assert.match(
    app,
    /loadCalendarSupplements\(\s*startDate,\s*endDate,\s*builtInDeadlineSourcesActive,\s*periodic,\s*\)/,
  )
  assert.match(
    app,
    /calendarSupplementRevision,\s*builtInDeadlineSourcesActive,[\s\S]*?settingsLoaded,\s*\]\)/,
  )
  assert.match(app, /\{builtInDeadlineSourcesActive\s*\|\| settings\.customDeadlinesEnabled/)
  assert.match(app, /enabledTypes=\{enabledDeadlineTypes\}/)
  assert.match(
    app,
    /loadCalendarSupplements\(\s*calendarDate,\s*calendarDate,\s*builtInDeadlineSourcesActive,\s*true,\s*\)/,
  )
})
