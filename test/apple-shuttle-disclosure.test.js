import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const disclosure = read('native/apple/Sources/Shared/ShuttleFullTimetableDisclosure.swift')
const queries = read('native/apple/Sources/Shared/InformationQueriesView.swift')
const fullTable = queries.slice(queries.indexOf('private func shuttleFullTimetable('),
  queries.indexOf('private func shuttleFullScheduleCard('))

// Updated specifications only; local automated execution remains disabled.
test('Apple timetable periods and directions use stable default-collapsed clipped content', () => {
  assert.match(disclosure, /@State private var isExpanded = false/)
  assert.match(disclosure, /ExpandableContent\(expanded: isExpanded\)/)
  assert.match(disclosure, /\.easeInOut\(duration: 0\.22\)/)
  assert.match(disclosure, /accessibilityReduceMotion/)
  assert.match(disclosure, /isExpanded \? "已展开" : "已折叠"/)
  assert.match(disclosure, /queries\.shuttle\.full-timetable\.toggle/)
  assert.match(disclosure, /queries\.shuttle\.full-timetable\.content/)
  assert.doesNotMatch(disclosure, /Task\s*\{|\.task\b|\.load\(|\.reset\(|selectedMode|shuttleStore|URLSession/)
})

test('The complete table stays visible while each period and direction has a disclosure', () => {
  assert.match(fullTable, /ShuttleFullTimetableDisclosure\(language: model\.appLanguage\)/)
  assert.match(fullTable, /ForEach\(shuttlePeriods\(notice\.schedules\)/)
  assert.match(fullTable, /ForEach\(group\.schedules\)/)
  assert.match(fullTable, /shuttleFullScheduleCard\(schedule\)/)
  assert.match(fullTable, /Label\("完整班车时刻表", systemImage: "bus\.doubledecker"\)/)
  assert.match(fullTable, /queries\.shuttle\.full-timetable/)
  assert.doesNotMatch(fullTable, /\.load\(|\.task\b|\.id\(|selectedMode\s*=/)

  const snapshot = queries.slice(queries.indexOf('private func shuttleSnapshot('),
    queries.indexOf('private func shuttleFullTimetable('))
  assert.match(snapshot, /shuttleRouteCard\([\s\S]*?shuttleFullTimetable\(snapshot\)[\s\S]*?sourceNotice\(/)
  assert.doesNotMatch(snapshot, /ShuttleFullTimetableDisclosure/)
  const rows = queries.slice(queries.indexOf('private func shuttleFullScheduleCard('),
    queries.indexOf('private func shuttlePeriodState('))
  assert.match(rows, /ShuttleBusTodayLogic\.fullWeek\(for: schedule\)/)
  for (const rawField of ['schedule.from', 'schedule.to', 'departure.departureTime', 'departure.service.vehicle']) {
    assert.ok(rows.includes(rawField), rawField)
  }
})

test('Disclosure reuses existing localized accessibility states without adding language resources', () => {
  for (const locale of ['zh-Hans', 'en', 'zh-Hant', 'ja', 'es', 'pt', 'ar', 'ru', 'tr', 'th', 'ms', 'vi', 'id']) {
    const source = read(`native/apple/Resources/Localizations/${locale}.lproj/Localizable.strings`)
    for (const key of ['完整班车时刻表', '已展开', '已折叠']) {
      assert.ok(source.includes(`"${key}" = `), `${locale}: ${key}`)
    }
  }
})
