import assert from 'node:assert/strict'
import test from 'node:test'

import {
  buildShuttleDayView,
  buildShuttleTimetable,
  filterImportantEvents,
  importantEventFavorite,
  importantEventFilterOptions,
  importantEventVisibleCount,
  isLegalShuttleHoliday,
  IMPORTANT_EVENT_BATCH_SIZE,
  mergeImportantEventCatalog,
  nextImportantEventVisibleCount,
  resolvedShuttleSelection,
  selectShuttleNotice,
  shuttlePeriodState,
} from '../src/query-domain.js'

test('important events append in bounded UI batches without refetching', () => {
  assert.equal(IMPORTANT_EVENT_BATCH_SIZE, 20)
  assert.equal(nextImportantEventVisibleCount(0, 53), 20)
  assert.equal(nextImportantEventVisibleCount(20, 53), 40)
  assert.equal(nextImportantEventVisibleCount(40, 53), 53)
  assert.equal(nextImportantEventVisibleCount(53, 53), 53)
  assert.equal(nextImportantEventVisibleCount(-4, 8), 8)
  assert.equal(importantEventVisibleCount({ key: 'old', count: 40 }, 'old', 60), 40)
  assert.equal(
    importantEventVisibleCount({ key: 'old', count: 40 }, 'same-length-new-filter', 60),
    20,
    'a same-length filter must synchronously hide the old extra batches',
  )
  assert.equal(importantEventVisibleCount({ key: '', count: 20 }, 'new', 7), 7)
})

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
          rows: [
            { departure_time: '08:00', services: { monday: { vehicle: '大巴', count: 1 } } },
          ],
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

test('shuttle next departure uses clock order rather than response order', () => {
  const payload = structuredClone(shuttlePayload)
  payload.items[1].schedules[0].rows.reverse()
  const view = buildShuttleDayView(payload, {
    today: '2026-08-31', weekday: 'monday', currentWeekday: 'monday', nowMinutes: 7 * 60,
  })
  assert.deepEqual(view.routes[0].departures.map((row) => row.departureTime), ['08:30', '12:00'])
  assert.deepEqual(view.routes[0].departures.map((row) => row.next), [true, false])
})

test('shuttle day uses the newest active verified period and excludes unreadable options', () => {
  const period = (label, start, status, rows) => ({
    period: { label, start_date: start, end_date: null },
    from: '西土城路校区', to: '沙河校区', parse_status: status, rows,
  })
  const row = (time) => ({ departure_time: time, services: { thursday: { vehicle: '大巴', count: 1 } } })
  const payload = {
    items: [{
      id: 'latest', stops: [], schedules: [
        period('未核实', '2026-09-09', 'needs_review', [row('06:00')]),
        period('较早时段', '2026-09-01', 'parsed', [row('07:00')]),
        period('较新时段', '2026-09-07', 'parsed', [row('08:00')]),
        period('空时段', '2026-09-10', 'parsed', []),
        period('无班次服务', '2026-09-11', 'parsed', [
          { departure_time: '09:00', services: { monday: null } },
        ]),
      ],
    }],
  }
  const view = buildShuttleDayView(payload, {
    today: '2026-09-10', weekday: 'thursday', currentWeekday: 'thursday', nowMinutes: 0,
  })
  assert.deepEqual(view.periods.map(({ period: item }) => item.label), ['较早时段', '较新时段'])
  assert.equal(view.period.label, '较新时段')
  assert.deepEqual(view.routes[0].departures.map(({ departureTime }) => departureTime), ['08:00'])
  assert.deepEqual(buildShuttleTimetable(payload, '2026-09-10').periods.map(({ period: item }) => item.label),
    ['较早时段', '较新时段'])
})

test('shuttle selection keeps deliberate same-day browsing but resets at midnight or a new notice', () => {
  const weekdaySelection = { key: 'monday', date: '2026-09-07' }
  const periodSelection = { key: 'older', date: '2026-09-07', noticeIdentity: 'latest\u001fparsed' }
  const selection = (today, noticeIdentity) => resolvedShuttleSelection({
    weekdaySelection, periodSelection, today, currentWeekday: 'tuesday', noticeIdentity,
  })
  assert.deepEqual(selection('2026-09-07', 'latest\u001fparsed'), {
    weekday: 'monday', period: 'older',
  })
  assert.deepEqual(selection('2026-09-08', 'latest\u001fparsed'), {
    weekday: 'tuesday', period: '',
  })
  assert.deepEqual(selection('2026-09-07', 'new-latest\u001fparsed'), {
    weekday: 'monday', period: '',
  })
})

test('full shuttle timetable retains all verified periods, directions, and weekday services', () => {
  const payload = {
    last_parsed_notice_id: 'parsed',
    items: [
      { id: 'latest', notes: ['法定节假日期间，班车停运。'], schedules: [] },
      {
        id: 'parsed',
        notes: ['旧通知的假期安排'],
        stops: [{ campus: '沙河校区', location: '学生活动中心南侧' }],
        schedules: [
          {
            period: { label: '第一时段', start_date: '2026-08-27', end_date: '2026-09-04' },
            from: '西土城路校区', to: '沙河校区', parse_status: 'parsed',
            rows: [
              { departure_time: '12:00', services: { friday: { vehicle: '大巴', count: 2 } } },
              { departure_time: '08:00', services: { monday: { vehicle: '中巴', count: 1 }, sunday: null } },
            ],
          },
          {
            period: { label: '第一时段', start_date: '2026-08-27', end_date: '2026-09-04' },
            from: '沙河校区', to: '西土城路校区', parse_status: 'parsed',
            rows: [{ departure_time: '09:00', services: { tuesday: { vehicle: '大巴', count: 1 } } }],
          },
          {
            period: { label: '第二时段', start_date: '2026-09-07', end_date: null },
            from: '西土城路校区', to: '沙河校区', parse_status: 'parsed',
            rows: [{ departure_time: '07:30', services: { wednesday: { vehicle: '大巴', count: 3 } } }],
          },
          {
            period: { label: '未核实', start_date: '2026-09-07', end_date: null },
            from: '沙河校区', to: '西土城路校区', parse_status: 'needs_review',
            rows: [{ departure_time: '06:00', services: { monday: { vehicle: '大巴', count: 1 } } }],
          },
        ],
      },
    ],
  }
  const timetable = buildShuttleTimetable(payload, '2026-09-05')
  assert.equal(timetable.usingFallback, true)
  assert.equal(timetable.holidayNotice.text, '法定节假日期间，班车停运。')
  assert.equal(timetable.holidayNotice.source.id, 'latest')
  assert.deepEqual(timetable.periods.map(({ period, state }) => [period.label, state]), [
    ['第一时段', 'ended'], ['第二时段', 'upcoming'],
  ])
  assert.deepEqual(timetable.periods.map(({ routes }) => routes.length), [2, 1])
  assert.deepEqual(timetable.periods[0].routes[0].rows.map((row) => row.departure_time), ['08:00', '12:00'])
  assert.deepEqual(timetable.periods[0].routes[0].rows[0].services.monday, { vehicle: '中巴', count: 1 })
  assert.equal(timetable.periods[0].routes[0].rows[0].services.sunday, null)
  assert.equal(timetable.periods[0].routes[1].stop, '学生活动中心南侧')
  assert.deepEqual(timetable.periods[1].routes[0].rows[0].services.wednesday, { vehicle: '大巴', count: 3 })
})

test('shuttle holiday notice uses legal rest days and excludes festivals and transfer workdays', () => {
  const today = '2026-10-02'
  assert.equal(isLegalShuttleHoliday([{ date: today, type: 'holiday' }], today), true)
  assert.equal(isLegalShuttleHoliday([{ date: today, type: 'festival' }], today), false)
  assert.equal(isLegalShuttleHoliday([{ date: '2026-10-01', type: 'holiday' }], today), false)
  assert.equal(isLegalShuttleHoliday([
    { date: today, type: 'holiday' }, { date: today, type: 'workday' },
  ], today), false)
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
