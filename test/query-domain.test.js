import assert from 'node:assert/strict'
import test from 'node:test'

import {
  buildShuttleDayView,
  filterImportantEvents,
  importantEventFavorite,
  importantEventFilterOptions,
  mergeImportantEventCatalog,
  selectShuttleNotice,
  shuttlePeriodState,
} from '../src/query-domain.js'

const shuttlePayload = {
  last_parsed_notice_id: 'parsed',
  items: [
    { id: 'latest', schedules: [], stops: [] },
    {
      id: 'parsed',
      stops: [{ campus: '西土城路校区', location: '教三楼西侧' }],
      schedules: [
        {
          period: { label: '当前时段', start_date: '2026-08-27', end_date: '2026-09-04' },
          from: '西土城路校区',
          to: '沙河校区',
          parse_status: 'parsed',
          rows: [
            { departure_time: '08:30', services: { monday: { vehicle: '大巴', count: 1 } } },
            { departure_time: '12:00', services: { monday: { vehicle: '大巴', count: 2 } } },
          ],
        },
        {
          period: { label: '下一时段', start_date: '2026-09-07', end_date: null },
          from: '西土城路校区',
          to: '沙河校区',
          parse_status: 'parsed',
          rows: [],
        },
      ],
    },
  ],
}

test('shuttle query follows the website active-period and parsed-fallback rules', () => {
  const selected = selectShuttleNotice(shuttlePayload)
  assert.equal(selected.latest.id, 'latest')
  assert.equal(selected.notice.id, 'parsed')
  assert.equal(selected.usingFallback, true)
  assert.equal(
    shuttlePeriodState({ start_date: '2026-08-27', end_date: '2026-09-04' }, '2026-08-31'),
    'active',
  )

  const view = buildShuttleDayView(shuttlePayload, {
    today: '2026-08-31',
    weekday: 'monday',
    currentWeekday: 'monday',
    nowMinutes: 9 * 60,
  })
  assert.equal(view.period.label, '当前时段')
  assert.equal(view.routes.length, 1)
  assert.equal(view.routes[0].stop, '教三楼西侧')
  assert.equal(view.routes[0].departures[0].departed, true)
  assert.equal(view.routes[0].departures[1].next, true)
})

test('shuttle query never presents an upcoming or ended timetable as active today', () => {
  const gap = buildShuttleDayView(shuttlePayload, {
    today: '2026-09-05',
    weekday: 'saturday',
    currentWeekday: 'saturday',
    nowMinutes: 9 * 60,
  })
  assert.equal(gap.visiblePeriod, '')
  assert.equal(gap.period, null)
  assert.equal(gap.periodState, 'unknown')
  assert.deepEqual(gap.routes, [])

  const manuallySelectedFuture = buildShuttleDayView(shuttlePayload, {
    today: '2026-09-05',
    weekday: 'saturday',
    currentWeekday: 'saturday',
    nowMinutes: 9 * 60,
    selectedPeriod: '2026-09-07:open:下一时段',
  })
  assert.equal(manuallySelectedFuture.periodState, 'upcoming')
  assert.deepEqual(manuallySelectedFuture.routes, [])
})

test('important-event query searches metadata, filters categories, and sorts by DDL', () => {
  const items = [
    {
      id: 'future-late', name: 'AI Conference', event_type: 'conference',
      source_type: 'contest_ddl', primary_deadline: '2026-09-10T12:00:00+08:00',
      categories: ['人工智能'], tags: ['CCF A'], location: 'Beijing', archived: false,
    },
    {
      id: 'school', name: '校内机器人竞赛', event_type: 'competition',
      source_type: 'school_notice', primary_deadline: '2026-09-02T12:00:00+08:00',
      categories: ['校内竞赛通知'], source_name: '北京邮电大学教学云平台', archived: false,
    },
    {
      id: 'expired', name: 'Old Hackathon', event_type: 'hackathon',
      source_type: 'contest_ddl', primary_deadline: '2026-08-01T12:00:00+08:00',
      categories: ['黑客松'], archived: false,
    },
    {
      id: 'assignment', name: '作业', event_type: 'assignment',
      source_type: 'assignment', primary_deadline: '2026-09-01T12:00:00+08:00',
      categories: [], archived: false,
    },
  ]
  const filtered = filterImportantEvents(items, {
    now: new Date('2026-08-31T00:00:00+08:00'),
  })
  assert.deepEqual(filtered.map((item) => item.id), ['school', 'future-late'])

  const conference = filterImportantEvents(items, {
    query: 'ccf',
    type: 'conference',
    category: '人工智能',
    source: 'public',
    now: new Date('2026-08-31T00:00:00+08:00'),
  })
  assert.deepEqual(conference.map((item) => item.id), ['future-late'])
  assert.deepEqual(importantEventFilterOptions(items).types, ['competition', 'conference', 'hackathon'])
  assert.deepEqual(importantEventFilterOptions(items, {
    type: 'conference',
    source: 'public',
    now: new Date('2026-08-31T00:00:00+08:00'),
  }).categories, ['人工智能'])
  assert.deepEqual(importantEventFilterOptions(items, {
    type: 'competition',
    source: 'school',
    now: new Date('2026-08-31T00:00:00+08:00'),
  }).categories, ['校内竞赛通知'])
  assert.deepEqual(importantEventFilterOptions(items, {
    type: 'hackathon',
    source: 'public',
    now: new Date('2026-08-31T00:00:00+08:00'),
  }).categories, [])
})

test('important-event favorites reuse the teaching-calendar snapshot contract', () => {
  assert.deepEqual(importantEventFavorite({
    id: 'conference-1',
    name: 'Conference',
    event_type: 'conference',
    source_type: 'contest_ddl',
    primary_deadline: '2026-09-10T12:00:00+08:00',
    organizer: 'IEEE',
    official_url: 'https://example.com',
    categories: ['AI'],
    tags: ['CCF A'],
    level: '国际会议',
    location: '北京',
    status: 'upcoming',
    description: 'Call for papers',
    eligibility: 'Open to students',
    notes: 'See official site',
    region: 'China',
    mode: 'hybrid',
    deadline_label: 'Submission deadline',
    published_at: '2026-08-01T00:00:00+08:00',
    stale: true,
    archived: false,
  }), {
    id: 'conference-1',
    name: 'Conference',
    event_type: 'conference',
    source_type: 'contest_ddl',
    primary_deadline: '2026-09-10T12:00:00+08:00',
    organizer: 'IEEE',
    official_url: 'https://example.com',
    source_name: null,
    source_url: null,
    deadline_label: 'Submission deadline',
    categories: ['AI'],
    tags: ['CCF A'],
    level: '国际会议',
    location: '北京',
    status: 'upcoming',
    description: 'Call for papers',
    eligibility: 'Open to students',
    notes: 'See official site',
    region: 'China',
    mode: 'hybrid',
    published_at: '2026-08-01T00:00:00+08:00',
    stale: true,
    archived: false,
  })
})

test('important-event catalog keeps favorite-only built-in types without duplicating live items', () => {
  const live = {
    id: 'live-competition',
    name: '现有竞赛',
    event_type: 'competition',
    source_type: 'contest_ddl',
    primary_deadline: '2099-06-01T12:00:00+08:00',
    categories: ['程序设计'],
  }
  const favorite = {
    id: 'saved-pre-admission',
    name: '已收藏预推免',
    event_type: 'pre_admission',
    source_type: 'contest_ddl',
    primary_deadline: '2099-06-02T12:00:00+08:00',
    categories: ['预推免'],
  }
  const custom = {
    ...favorite,
    id: 'custom-journal',
    event_type: 'journal_special_issue',
    source_type: 'custom',
  }
  const catalog = mergeImportantEventCatalog([live], [live, favorite, custom])
  assert.deepEqual(catalog, [live, favorite])
  assert.deepEqual(
    importantEventFilterOptions(catalog).types,
    ['competition', 'pre_admission'],
  )
})
