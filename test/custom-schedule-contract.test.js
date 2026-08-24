import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import test from 'node:test'

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')

const schema = JSON.parse(read('../contracts/v1/custom-deadline-feed.schema.json'))
const fixture = JSON.parse(read('../contracts/v1/fixtures/custom-deadline-feed.json'))
const contractDoc = read('../docs/custom-schedule-api.md')
const readme = read('../README.md')
const privacy = read('../PRIVACY.md')
const desktopApp = read('../src/App.jsx')
const desktopDomain = read('../src/planner-domain.js')
const desktopBackend = read('../src-tauri/src/deadlines.rs')
const desktopCapability = JSON.parse(read('../src-tauri/capabilities/default.json'))
const androidFeed = read('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/CustomDeadlineFeed.kt')
const androidPreferences = read('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/SecureCredentialStore.kt')
const appleFeed = read('../native/apple/Sources/Shared/CustomDeadlineFeedClient.swift')
const appleModel = read('../native/apple/Sources/Shared/AppModel.swift')
const harmonyFeed = read('../native/harmony/entry/src/main/ets/net/CalendarDailyInfoClient.ets')
const harmonyModel = read('../native/harmony/entry/src/main/ets/model/AppModel.ets')

test('custom schedule fixture conforms to the published v1 boundary', () => {
  assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema')
  assert.deepEqual(schema.required, ['version', 'source', 'items'])
  assert.equal(schema.properties.version.const, 1)
  assert.equal(schema.properties.items.maxItems, 5000)
  assert.deepEqual(schema.$defs.item.properties.event_type.enum, [
    'competition', 'summer_camp', 'hackathon', 'custom',
  ])

  assert.equal(fixture.version, 1)
  assert.ok(fixture.source.length >= 1 && fixture.source.length <= 80)
  assert.ok(fixture.items.length <= schema.properties.items.maxItems)
  for (const item of fixture.items) {
    assert.ok(schema.$defs.item.properties.event_type.enum.includes(item.event_type))
    assert.match(item.primary_deadline, /(?:Z|[+-]\d{2}:\d{2})$/)
    assert.ok(!Number.isNaN(Date.parse(item.primary_deadline)))
    if (item.official_url) assert.match(item.official_url, /^https:\/\//)
  }
})

test('the public custom feed documentation defines security, cache, and favorite semantics', () => {
  assert.match(contractDoc, /2 MiB/)
  assert.match(contractDoc, /100 项/)
  assert.match(contractDoc, /370 天/)
  assert.match(contractDoc, /缓存成功响应 5 分钟/)
  assert.match(contractDoc, /来源关闭、请求失败或上游删除条目后，收藏仍会显示/)
  assert.match(readme, /docs\/custom-schedule-api\.md/)
  assert.match(privacy, /public HTTPS JSON URL/)
  assert.match(privacy, /neither uploaded nor synchronized/)
})

test('every graphical client enforces the same custom feed transport limits', () => {
  assert.match(desktopBackend, /const MAX_RESPONSE_BYTES: usize = 2 \* 1024 \* 1024/)
  assert.match(desktopBackend, /const MAX_ITEMS_PER_DAY: usize = 100/)
  assert.match(desktopBackend, /const MAX_CUSTOM_ITEMS: usize = 5_000/)
  assert.match(desktopBackend, /const MAX_CALENDAR_RANGE_DAYS: i64 = 370/)
  assert.match(desktopBackend, /redirect\(reqwest::redirect::Policy::none\(\)\)/)

  assert.match(androidFeed, /const val maximumItems = 5_000/)
  assert.match(androidFeed, /const val maximumItemsPerDay = 100/)
  assert.match(androidFeed, /const val maximumCalendarRangeDays = 370/)
  assert.match(androidFeed, /instanceFollowRedirects = false/)

  assert.match(appleFeed, /static let maximumItems = 5_000/)
  assert.match(appleFeed, /maximumItemsPerDay/)
  assert.match(appleFeed, /requestedDates\.count <= 370/)
  assert.match(appleFeed, /completionHandler\(nil\)/)

  assert.match(harmonyFeed, /maximumItemsPerDay: number = 100/)
  assert.match(harmonyFeed, /records\.length > 5000/)
  assert.match(harmonyFeed, /maxRedirects: 0/)
  assert.match(harmonyFeed, /customDeadlineCache/)
})

test('favorites are capped local full snapshots and bypass disabled source filters', () => {
  assert.match(desktopDomain, /normalizeFavoriteDeadlines\(value, maximum = 500\)/)
  assert.match(desktopDomain, /source_name:/)
  assert.match(desktopDomain, /source_url:/)
  assert.match(desktopApp, /FAVORITE_DEADLINES_STORAGE_KEY/)
  assert.match(desktopApp, /favoriteDeadlinesForDate\(favoriteDeadlines, dateString\)/)
  assert.match(desktopApp, /const customSources = \[\.\.\.new Map/)

  assert.match(androidPreferences, /const val maximumFavoriteDeadlines = 500/)
  assert.match(androidPreferences, /fun favoriteDeadlineItems\(date: String\)/)

  assert.match(appleModel, /static let maximumFavoriteDeadlines = 500/)
  assert.match(appleModel, /func favoriteDeadlineItems\(on date: String\)/)

  assert.match(harmonyFeed, /maximumFavorites: number = 500/)
  assert.match(harmonyFeed, /record\['source_name'\] = item\.sourceName/)
  assert.match(harmonyFeed, /record\['source_homepage'\] = item\.sourceHomepage/)
  assert.match(harmonyModel, /for \(const favorite of this\.favoriteDeadlines\)/)
  assert.match(harmonyModel, /favorite\.deadline\.startsWith\(date\)/)
})

test('Tauri exposes the custom calendar command through generated permissions', () => {
  assert.ok(desktopCapability.permissions.includes('allow-fetch-custom-deadline-calendar'))
  assert.equal(
    existsSync(new URL(
      '../src-tauri/permissions/autogenerated/fetch_custom_deadline_calendar.toml',
      import.meta.url,
    )),
    true,
  )
  assert.match(desktopApp, /command\('fetch_custom_deadline_calendar'/)
})
