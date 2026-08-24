import assert from 'node:assert/strict'
import test from 'node:test'
import {
  accountHasSavedPassword,
  buildingsForCampus,
  dateFromString,
  deadlinePreheatPlan,
  calendarMonthExpansion,
  calendarDeadlineBorderKinds,
  calendarDeadlineBorderPriority,
  calendarMonthDragProgress,
  calendarMonthExpansionTarget,
  calendarSurfaceKey,
  calendarTransition,
  calendarSwipeDirection,
  DEFAULT_SETTINGS,
  desktopMonthGridMetrics,
  expandedMonthGridMetrics,
  favoriteDeadlineKey,
  favoriteDeadlinesForDate,
  formatTeachingWeek,
  FALLBACK_SLOTS,
  fallbackHolidayItems,
  getCampusClassrooms,
  getWeekState,
  isValidAccountScope,
  isValidTermId,
  isValidTermStartDate,
  manualTermValidationError,
  msUntilNextShanghaiMidnight,
  nonHourlyCourseBoundaryMinutes,
  suggestTermForDate,
  termMatchesCurrentPeriod,
  normalizeClassroomsCache,
  normalizeFavoriteDeadlines,
  requestBody,
  scheduleRequestTerm,
  savedSettingsToState,
  settingsWithScheduleTerm,
  settingsToPayload,
  normalizeUiLanguage,
  resolvedUiLanguage,
  shanghaiDateString,
  shiftDate,
  slotsToRanges,
  summarizeMonthEntries,
  startupSettingsToState,
  yearCourseOpacity,
} from '../src/planner-domain.js'

test('campus building catalog keeps every original building visible', () => {
  assert.deepEqual(buildingsForCampus('1'), ['教1', '教2', '教3', '教4', '主楼'])
  assert.deepEqual(buildingsForCampus('04'), [
    '综合教学楼N',
    '综合教学楼S',
    '教学实验综合楼N',
    '教学实验综合楼S',
    '智慧教学楼',
  ])
  assert.deepEqual(buildingsForCampus('unknown'), [])
})

test('month navigation clamps dates at the destination month boundary', () => {
  assert.equal(shiftDate('2026-01-31', 'month', 1), '2026-02-28')
  assert.equal(shiftDate('2024-01-31', 'month', 1), '2024-02-29')
  assert.equal(shiftDate('2026-03-31', 'month', -1), '2026-02-28')
})

test('year navigation clamps leap day without changing the month', () => {
  assert.equal(shiftDate('2024-02-29', 'year', 1), '2025-02-28')
  assert.equal(shiftDate('2024-02-29', 'year', -1), '2023-02-28')
})

test('day and week navigation preserve their existing increments', () => {
  assert.equal(shiftDate('2026-06-01', 'day', 1), '2026-06-02')
  assert.equal(shiftDate('2026-06-01', 'week', -1), '2026-05-25')
})

test('calendar swipe navigation requires an intentional horizontal gesture', () => {
  assert.equal(calendarSwipeDirection(-80, 12), 1)
  assert.equal(calendarSwipeDirection(80, -8), -1)
  assert.equal(calendarSwipeDirection(42, 2), 0)
  assert.equal(calendarSwipeDirection(-90, 80), 0)
})

test('month expansion only follows deliberate vertical gestures', () => {
  assert.equal(calendarMonthExpansion(8, 72), true)
  assert.equal(calendarMonthExpansion(-10, -72), false)
  assert.equal(calendarMonthExpansion(8, 32), null)
  assert.equal(calendarMonthExpansion(70, 72), null)
})

test('month expansion follows drag progress before snapping to an endpoint', () => {
  assert.equal(calendarMonthDragProgress(false, 0, 120), 0)
  assert.equal(calendarMonthDragProgress(false, 60, 120), 0.5)
  assert.equal(calendarMonthDragProgress(0.25, 30, 120), 0.5)
  assert.equal(calendarMonthDragProgress(true, -30, 120), 0.75)
  assert.equal(calendarMonthDragProgress(false, 240, 120), 1)
  assert.equal(calendarMonthDragProgress(true, -240, 120), 0)

  assert.equal(calendarMonthExpansionTarget(0.49), false)
  assert.equal(calendarMonthExpansionTarget(0.5), true)
  assert.equal(calendarMonthExpansionTarget(0.2, 0.6), true)
  assert.equal(calendarMonthExpansionTarget(0.8, -0.6), false)
})

test('expanded month cells reserve the last row for a hidden-entry count', () => {
  assert.deepEqual(summarizeMonthEntries(['a', 'b'], 2), {
    visible: ['a', 'b'],
    hiddenCount: 0,
  })
  assert.deepEqual(summarizeMonthEntries(['a', 'b', 'c', 'd'], 2), {
    visible: ['a'],
    hiddenCount: 3,
  })
})

test('teaching week labels never fall back to Gregorian week wording', () => {
  assert.equal(formatTeachingWeek(8), '第 8 教学周')
  assert.equal(formatTeachingWeek(0), '非教学周')
})

test('calendar period keys and transition direction share one navigation contract', () => {
  assert.equal(calendarSurfaceKey('week', '2026-08-24'), 'week:2026-08-24')
  assert.equal(calendarSurfaceKey('week', '2026-08-30'), 'week:2026-08-24')
  assert.equal(calendarSurfaceKey('month', '2026-08-24'), 'month:2026-08')
  assert.equal(calendarTransition('2026-08-24', 'week', '2026-08-26').motion, '')
  assert.equal(calendarTransition('2026-08-24', 'week', '2026-08-31').motion, 'next')
  assert.equal(calendarTransition('2026-08-31', 'week', '2026-08-24').motion, 'previous')
  assert.equal(calendarTransition('2026-08-24', 'year', '2026-08-24', 'month').motion, 'previous')
  assert.equal(calendarTransition('2026-08-24', 'day', '2026-08-24', 'year').motion, 'next')
})

test('desktop month layout follows native macOS remaining-height metrics', () => {
  assert.deepEqual(desktopMonthGridMetrics(900), {
    weekdayHeight: 30,
    cellHeight: 145,
    height: 900,
    maximumEventRows: 4,
  })
  assert.deepEqual(desktopMonthGridMetrics(600), {
    weekdayHeight: 30,
    cellHeight: 95,
    height: 600,
    maximumEventRows: 3,
  })
  assert.deepEqual(desktopMonthGridMetrics(400), {
    weekdayHeight: 30,
    cellHeight: 70,
    height: 520,
    maximumEventRows: 2,
  })
})

test('year deadline borders use assignment then school then public priority', () => {
  const publicDeadline = { type: 'public-deadline' }
  const schoolNotice = { type: 'school-notice' }
  const assignment = { type: 'assignment' }

  assert.equal(calendarDeadlineBorderPriority([]), '')
  assert.equal(calendarDeadlineBorderPriority([publicDeadline]), 'public-deadline')
  assert.equal(
    calendarDeadlineBorderPriority([publicDeadline, schoolNotice]),
    'school-notice',
  )
  assert.equal(
    calendarDeadlineBorderPriority([schoolNotice, publicDeadline, assignment]),
    'assignment',
  )
})

test('calendar deadline borders keep the two highest distinct deadline kinds', () => {
  const publicDeadline = { type: 'public-deadline' }
  const schoolNotice = { type: 'school-notice' }
  const assignment = { type: 'assignment' }

  assert.deepEqual(calendarDeadlineBorderKinds([]), [])
  assert.deepEqual(calendarDeadlineBorderKinds([publicDeadline]), ['public-deadline'])
  assert.deepEqual(
    calendarDeadlineBorderKinds([publicDeadline, publicDeadline, schoolNotice]),
    ['school-notice', 'public-deadline'],
  )
  assert.deepEqual(
    calendarDeadlineBorderKinds([publicDeadline, assignment, schoolNotice]),
    ['assignment', 'school-notice'],
  )
  assert.deepEqual(
    calendarDeadlineBorderKinds([publicDeadline, assignment, schoolNotice], 3),
    ['assignment', 'school-notice', 'public-deadline'],
  )
  assert.deepEqual(calendarDeadlineBorderKinds([assignment], 0), [])
})

test('expanded month grid caps web rows at the native mobile height', () => {
  assert.deepEqual(expandedMonthGridMetrics(900), { rowHeight: 68, height: 438 })
  assert.deepEqual(expandedMonthGridMetrics(320), { rowHeight: 48, height: 318 })
})

test('teaching week calculation uses calendar days and reports busy slots', () => {
  const courses = [{
    id: 'course-1',
    name: '数据挖掘',
    weekday: 1,
    week_numbers: [1, 2],
    exam_week_numbers: [],
    start_slot: 2,
    end_slot: 4,
  }]

  const state = getWeekState(courses, '2026-03-02', '2026-03-09')
  assert.equal(state.weekNumber, 2)
  assert.equal(state.weekday, 1)
  assert.deepEqual(state.busySlots, [2, 3, 4])
  assert.equal(state.dayCourses[0].is_exam, false)
})

test('teaching week is hidden without a timetable or beyond its actual final week', () => {
  assert.equal(getWeekState([], '2026-03-02', '2026-03-02').weekNumber, 0)
  const shortSchedule = [{
    id: 'course-1',
    name: 'Short course',
    weekday: 1,
    week_numbers: [1, 2],
    exam_week_numbers: [],
    start_slot: 0,
    end_slot: 1,
  }]
  assert.equal(getWeekState(shortSchedule, '2026-03-02', '2026-03-09').weekNumber, 2)
  assert.equal(getWeekState(shortSchedule, '2026-03-02', '2026-03-16').weekNumber, 0)
})

test('exam badges follow the backend-provided exam week numbers only', () => {
  const course = {
    id: 'exam-course',
    name: '考试课程',
    weekday: 1,
    week_numbers: [1, 2, 25],
    exam_week_numbers: [25],
    start_slot: 0,
    end_slot: 1,
  }

  assert.equal(getWeekState([course], '2026-01-05', '2026-06-22').dayCourses[0].is_exam, true)
  const plainCourse = { ...course, exam_week_numbers: [] }
  assert.equal(getWeekState([plainCourse], '2026-01-05', '2026-06-22').dayCourses[0].is_exam, false)
})

test('shanghai date helpers are independent of the device timezone', () => {
  // 2026-08-17T20:00:00Z is already 2026-08-18 04:00 in Shanghai.
  assert.equal(shanghaiDateString(new Date('2026-08-17T20:00:00Z')), '2026-08-18')
  // 2026-08-17T15:59:00Z is 2026-08-17 23:59 in Shanghai -> one minute until midnight.
  assert.equal(msUntilNextShanghaiMidnight(new Date('2026-08-17T15:59:00Z')), 60000)
})

test('Shanghai midnight calculation stays correct in any device timezone', () => {
  // Noon in Shanghai (2026-08-18T04:00:00Z) is exactly 12h before midnight,
  // regardless of which local timezone the process runs in.
  assert.equal(msUntilNextShanghaiMidnight(new Date('2026-08-18T04:00:00Z')), 12 * 60 * 60 * 1000)
  // 08:00 Shanghai is 16h before midnight.
  assert.equal(msUntilNextShanghaiMidnight(new Date('2026-08-18T00:00:00Z')), 16 * 60 * 60 * 1000)
  // Right at midnight, the timer must not be zero (min 1000ms guard).
  const atMidnight = msUntilNextShanghaiMidnight(new Date('2026-08-17T16:00:00Z'))
  assert.ok(atMidnight >= 1000 && atMidnight <= 24 * 60 * 60 * 1000)
})

test('date parsing rejects impossible calendar dates instead of rolling them', () => {
  assert.equal(dateFromString('2026-03-02').getFullYear(), 2026)
  assert.ok(Number.isNaN(dateFromString('2026-02-30').getTime()), 'Feb 30 must be rejected')
  assert.ok(Number.isNaN(dateFromString('2026-13-01').getTime()), 'month 13 must be rejected')
  assert.ok(Number.isNaN(dateFromString('2026-00-10').getTime()), 'month 0 must be rejected')
  assert.ok(Number.isNaN(dateFromString('2026-04-31').getTime()), 'Apr 31 must be rejected')
  assert.ok(Number.isNaN(dateFromString('2026-2-03').getTime()), 'unpadded must be rejected')
  assert.ok(Number.isNaN(dateFromString('not-a-date').getTime()), 'garbage must be rejected')
  // Leap day is valid.
  assert.equal(dateFromString('2024-02-29').getDate(), 29)
})

test('malformed schedules never crash week state or slot ranges', () => {
  const brokenCourse = {
    id: 'broken',
    name: '异常课程',
    weekday: 1,
    week_numbers: null,
    start_slot: 0,
    end_slot: 99,
  }
  const state = getWeekState([brokenCourse], '2026-03-02', '2026-03-09')
  assert.equal(state.dayCourses.length, 0)
  assert.deepEqual(slotsToRanges([0, 1, 14, -2, 'x'], FALLBACK_SLOTS), [
    { start: 0, end: 1, label: '08:00-09:35' },
  ])
})

test('slot ranges merge adjacent sections and preserve gaps', () => {
  assert.deepEqual(slotsToRanges([0, 1, 3, 3], FALLBACK_SLOTS), [
    { start: 0, end: 1, label: '08:00-09:35' },
    { start: 3, end: 3, label: '10:40-11:25' },
  ])
})

test('timeline course boundaries include every unique non-hour slot edge', () => {
  assert.deepEqual(nonHourlyCourseBoundaryMinutes(FALLBACK_SLOTS), [
    525, 530, 575, 590, 635, 640, 685, 690, 735, 825, 830, 875, 885,
    930, 940, 985, 995, 1040, 1045, 1090, 1110, 1155, 1160, 1205, 1210, 1255,
  ])
  assert.deepEqual(nonHourlyCourseBoundaryMinutes([
    { start: 'invalid', end: '24:20' },
    { start: '07:50', end: '22:10' },
    { start: '09:00', end: '09:45' },
    { start: '09:45', end: '09:45' },
  ]), [585])
})

test('saved settings never hydrate a password into web state', () => {
  const state = savedSettingsToState({
    account: 'student',
    password: 'must-not-cross-the-bridge',
    has_saved_password: true,
    term_id: '2025-2026-2',
    term_start_date: '2026-03-02',
    campus_id: '04',
    default_min_seats: 30,
    daily_course_notifications_enabled: true,
    competition_deadlines_enabled: false,
    school_contest_notices_enabled: true,
  })

  assert.equal(state.password, '')
  assert.equal(state.hasSavedPassword, true)
  assert.equal(state.dailyCourseNotificationsEnabled, true)
  assert.equal(state.competitionDeadlinesEnabled, false)
  assert.equal(state.schoolContestNoticesEnabled, true)
  assert.equal(settingsToPayload(state).daily_course_notifications_enabled, true)
  assert.equal(settingsToPayload(state).competition_deadlines_enabled, false)
  assert.equal(settingsToPayload(state).school_contest_notices_enabled, true)
  assert.equal(accountHasSavedPassword(' student ', { account: 'student', hasSavedPassword: true }), true)
})

test('interface language persists safely and follows non-Chinese systems in English', () => {
  assert.equal(normalizeUiLanguage('en'), 'en')
  assert.equal(normalizeUiLanguage('zh-Hans'), 'zh-Hans')
  assert.equal(normalizeUiLanguage('unexpected'), 'system')
  assert.equal(resolvedUiLanguage('system', 'zh-CN'), 'zh-Hans')
  assert.equal(resolvedUiLanguage('system', 'en-US'), 'en')

  const english = savedSettingsToState({ ui_language: 'en' })
  assert.equal(english.uiLanguage, 'en')
  assert.equal(settingsToPayload(english).ui_language, 'en')
})

test('custom schedule settings round-trip without leaking into unrelated fields', () => {
  const state = savedSettingsToState({
    custom_deadlines_enabled: true,
    custom_deadlines_url: '  https://example.com/calendar.json  ',
  })

  assert.equal(state.customDeadlinesEnabled, true)
  assert.equal(state.customDeadlinesUrl, 'https://example.com/calendar.json')
  assert.equal(settingsToPayload(state).custom_deadlines_enabled, true)
  assert.equal(
    settingsToPayload(state).custom_deadlines_url,
    'https://example.com/calendar.json',
  )
})

test('favorite deadlines keep complete normalized snapshots and survive source switches', () => {
  const favorite = {
    id: 'custom-1',
    name: 'Independent hackathon',
    event_type: 'hackathon',
    source_type: 'custom',
    primary_deadline: '2026-08-24T23:59:00+08:00',
    organizer: 'Example Lab',
    official_url: 'https://example.com/events/1',
    source_name: 'Example Calendar',
    source_url: 'https://example.com/calendar.json',
  }
  const normalized = normalizeFavoriteDeadlines([
    favorite,
    { ...favorite, name: 'duplicate with the same stable key' },
    { ...favorite, id: '', primary_deadline: 'invalid' },
  ])

  assert.deepEqual(normalized, [favorite])
  assert.equal(favoriteDeadlineKey(normalized[0]), favoriteDeadlineKey(favorite))
  assert.deepEqual(favoriteDeadlinesForDate(normalized, '2026-08-24'), [favorite])
  assert.deepEqual(favoriteDeadlinesForDate(normalized, '2026-08-25'), [])
})

test('favorite deadline snapshots reject unsafe links and cap local storage', () => {
  const makeItem = (index) => ({
    id: `item-${index}`,
    name: `Item ${index}`,
    event_type: 'competition',
    source_type: 'contest_ddl',
    primary_deadline: `2026-09-${String((index % 28) + 1).padStart(2, '0')}T12:00:00+08:00`,
    official_url: index === 0 ? 'https://user@example.com/private' : 'https://example.com',
  })
  const normalized = normalizeFavoriteDeadlines(Array.from({ length: 8 }, (_, index) => makeItem(index)), 3)

  assert.equal(normalized.length, 3)
  assert.equal(normalized.find((item) => item.id === 'item-0')?.official_url, null)
})

test('custom favorites from different feeds keep independent source identities', () => {
  const base = {
    id: 'same-id',
    name: 'Same event',
    event_type: 'custom',
    source_type: 'custom',
    primary_deadline: '2026-09-18T23:59:00+08:00',
  }
  const left = { ...base, source_name: 'Left', source_url: 'https://left.example/feed.json' }
  const right = { ...base, source_name: 'Right', source_url: 'https://right.example/feed.json' }

  assert.notEqual(favoriteDeadlineKey(left), favoriteDeadlineKey(right))
  assert.equal(normalizeFavoriteDeadlines([left, right]).length, 2)
})

test('deadline startup preheat follows every shared-feed switch and covers the whole year', () => {
  const disabled = {
    competitionDeadlinesEnabled: false,
    schoolContestNoticesEnabled: false,
    summerCampDeadlinesEnabled: false,
    hackathonDeadlinesEnabled: false,
  }
  assert.equal(deadlinePreheatPlan(disabled, '2026-08-23'), null)

  for (const field of Object.keys(disabled)) {
    assert.deepEqual(deadlinePreheatPlan({ ...disabled, [field]: true }, '2026-08-23'), {
      startDate: '2026-01-01',
      endDate: '2026-12-31',
    })
  }
  assert.equal(deadlinePreheatPlan(DEFAULT_SETTINGS, '2026-02-30'), null)
})

test('minimum seat settings remain finite non-negative integers', () => {
  for (const value of [
    -1,
    Number.NEGATIVE_INFINITY,
    Number.POSITIVE_INFINITY,
    Number.MAX_VALUE,
    'invalid',
  ]) {
    assert.equal(savedSettingsToState({ default_min_seats: value }).defaultMinSeats, 0)
    assert.equal(
      settingsToPayload({ ...DEFAULT_SETTINGS, defaultMinSeats: value }).default_min_seats,
      0,
    )
  }

  assert.equal(savedSettingsToState({ default_min_seats: 12.9 }).defaultMinSeats, 12)
  assert.equal(
    settingsToPayload({ ...DEFAULT_SETTINGS, defaultMinSeats: 24.8 }).default_min_seats,
    24,
  )
})

test('a classroom query can override campus without changing the saved default', () => {
  const settings = { ...DEFAULT_SETTINGS, campusId: '01' }
  const queryPayload = requestBody(settings, { campus_id: '04', target_date: '2026-06-01' })

  assert.equal(queryPayload.campus_id, '04')
  assert.equal(settings.campusId, '01')
  assert.equal(settingsToPayload(settings).campus_id, '01')
})

test('legacy single-campus classroom data is normalized without changing rooms', () => {
  const legacy = {
    cache_version: 2,
    campus_id: '1',
    campus_name: '西土城',
    target_date: '2026-06-01',
    rooms: [{ id: 'room-1', building: '主楼', room: '101' }],
  }
  const normalized = normalizeClassroomsCache(legacy)

  assert.equal(normalized.campuses.length, 1)
  assert.equal(getCampusClassrooms(normalized, '01'), legacy)
  assert.equal(normalized.campuses[0].rooms[0].room, '101')
})

test('account scopes and fallback holiday data enforce their boundaries', () => {
  assert.equal(isValidAccountScope(`opaque-v1:${'a'.repeat(64)}`), true)
  assert.equal(isValidAccountScope('opaque-v1:student-number'), false)
  assert.ok(fallbackHolidayItems(2026).some((item) => item.date === '2026-10-01' && item.type === 'holiday'))
  assert.deepEqual(fallbackHolidayItems(2027), [])
})

test('year heat intensity increases with course count and remains bounded', () => {
  assert.equal(yearCourseOpacity(0), 0)
  assert.ok(yearCourseOpacity(1) < yearCourseOpacity(4))
  assert.ok(yearCourseOpacity(100) < 0.84)
})

test('suggestTermForDate picks the spring semester in March', () => {
  const suggested = suggestTermForDate(new Date(2026, 2, 15))
  assert.equal(suggested.termId, '2025-2026-2')
  assert.equal(suggested.termStartDate, '2026-03-02')
})

test('suggestTermForDate picks the fall semester in September', () => {
  const suggested = suggestTermForDate(new Date(2026, 8, 10))
  assert.equal(suggested.termId, '2026-2027-1')
  assert.equal(suggested.termStartDate, '2026-08-31')
})

test('term detection follows Shanghai across a UTC month boundary', () => {
  const beforeShanghaiAugust = suggestTermForDate(new Date('2026-07-31T15:59:59Z'))
  const inShanghaiAugust = suggestTermForDate(new Date('2026-07-31T16:00:00Z'))

  assert.equal(beforeShanghaiAugust.termId, '2025-2026-2')
  assert.equal(inShanghaiAugust.termId, '2026-2027-1')
})

test('suggestTermForDate handles spring months 2..7 and fall months 8..12', () => {
  for (const month of [8, 9, 10, 11, 12]) {
    const fall = suggestTermForDate(new Date(2026, month - 1, 15))
    assert.match(fall.termId, /^2026-2027-1$/)
  }
  for (const month of [2, 3, 4, 5, 6, 7]) {
    const spring = suggestTermForDate(new Date(2026, month - 1, 15))
    assert.match(spring.termId, /^2025-2026-2$/)
  }
})

test('January remains in the fall term that started the previous year', () => {
  const suggested = suggestTermForDate(new Date(2026, 0, 15))
  assert.equal(suggested.termId, '2025-2026-1')
  assert.equal(suggested.termStartDate, '2025-09-01')
})

test('spring term anchor stays in early March', () => {
  // 2026-03-01 is Sunday; the week of March 2 anchors the start on 03-02.
  const suggested = suggestTermForDate(new Date(2026, 2, 1))
  assert.equal(suggested.termStartDate, '2026-03-02')
})

test('isValidTermId accepts standard ids and rejects garbage', () => {
  assert.equal(isValidTermId('2025-2026-2'), true)
  assert.equal(isValidTermId('2026-2027-1'), true)
  assert.equal(isValidTermId('2025-2026-3'), false)
  assert.equal(isValidTermId('2025-2026'), false)
  assert.equal(isValidTermId('abc'), false)
  assert.equal(isValidTermId(''), false)
})

test('isValidTermStartDate rejects impossible dates', () => {
  assert.equal(isValidTermStartDate('2026-03-02'), true)
  assert.equal(isValidTermStartDate('2026-02-30'), false)
  assert.equal(isValidTermStartDate('2026-13-01'), false)
  assert.equal(isValidTermStartDate('2026-3-2'), false)
  assert.equal(isValidTermStartDate(''), false)
})

test('termMatchesCurrentPeriod flags mismatched terms', () => {
  const suggested = suggestTermForDate()
  assert.equal(termMatchesCurrentPeriod(suggested.termId, suggested.termStartDate), true)
  assert.equal(termMatchesCurrentPeriod('1999-2000-1', '2000-09-04'), false)
  assert.equal(termMatchesCurrentPeriod('garbage', '2026-03-02'), false)
})

test('term defaults stay empty while automatic startup uses a Shanghai-date suggestion', () => {
  assert.equal(DEFAULT_SETTINGS.termId, '')
  assert.equal(DEFAULT_SETTINGS.termStartDate, '')
  assert.equal(settingsToPayload(DEFAULT_SETTINGS).term_id, '')
  assert.equal(settingsToPayload(DEFAULT_SETTINGS).term_start_date, '')

  const automatic = startupSettingsToState({}, {}, null, new Date('2026-08-24T04:00:00Z'))
  assert.equal(automatic.termId, '2026-2027-1')
  assert.equal(automatic.termStartDate, '2026-08-31')
})

test('automatic startup trusts same-term cache but never saved term metadata', () => {
  const now = new Date('2026-08-24T04:00:00Z')
  const oldSaved = {
    term_id: '2025-2026-2',
    term_start_date: '2026-03-02',
    automatic_term_detection_enabled: true,
  }
  const currentCache = {
    term_id: '2026-2027-1',
    term_start_date: '2026-09-07',
  }
  const fromCache = startupSettingsToState(oldSaved, {}, currentCache, now)
  assert.equal(fromCache.termId, '2026-2027-1')
  assert.equal(fromCache.termStartDate, '2026-09-07')

  const fromCurrentSaved = startupSettingsToState({
    ...oldSaved,
    term_id: '2026-2027-1',
    term_start_date: '2026-09-07',
  }, {}, null, now)
  assert.equal(fromCurrentSaved.termId, '2026-2027-1')
  assert.equal(fromCurrentSaved.termStartDate, '2026-08-31')

  const fromDate = startupSettingsToState(oldSaved, {}, {
    term_id: '2025-2026-2',
    term_start_date: '2026-03-02',
  }, now)
  assert.equal(fromDate.termId, '2026-2027-1')
  assert.equal(fromDate.termStartDate, '2026-08-31')
})

test('metadata term defaults cannot overwrite or fill manual settings', () => {
  const metadata = {
    default_term_id: '2030-2031-1',
    default_term_start_date: '2030-09-02',
    campuses: [{ id: '04', name: '沙河' }],
  }
  const manual = startupSettingsToState({
    term_id: '2024-2025-2',
    term_start_date: '2025-02-24',
    campus_id: '01',
    automatic_term_detection_enabled: false,
  }, metadata, null, new Date('2026-08-24T04:00:00Z'))
  assert.equal(manual.termId, '2024-2025-2')
  assert.equal(manual.termStartDate, '2025-02-24')
  assert.equal(manual.campusId, '01')

  const emptyManual = startupSettingsToState({
    term_id: '',
    term_start_date: '',
    campus_id: '',
    automatic_term_detection_enabled: false,
  }, metadata, null, new Date('2026-08-24T04:00:00Z'))
  assert.equal(emptyManual.termId, '')
  assert.equal(emptyManual.termStartDate, '')
  assert.equal(emptyManual.campusId, '04')
})

test('schedule refresh uses date fallback in automatic mode and exact manual values otherwise', () => {
  const now = new Date('2026-08-24T04:00:00Z')
  assert.deepEqual(scheduleRequestTerm({
    automaticTermDetectionEnabled: true,
    termId: '2025-2026-2',
    termStartDate: '2026-03-02',
  }, now), {
    termId: '2026-2027-1',
    termStartDate: '2026-08-31',
  })
  assert.deepEqual(scheduleRequestTerm({
    automaticTermDetectionEnabled: true,
    termId: '2026-2027-1',
    termStartDate: '2026-09-07',
  }, now), {
    termId: '2026-2027-1',
    termStartDate: '2026-09-07',
  })
  assert.deepEqual(scheduleRequestTerm({
    automaticTermDetectionEnabled: false,
    termId: '2024-2025-2',
    termStartDate: '2025-02-24',
  }, now), {
    termId: '2024-2025-2',
    termStartDate: '2025-02-24',
  })
})

test('manual term validation rejects malformed ids consistently before save or fetch', () => {
  assert.equal(manualTermValidationError('', '2026-03-02'), '请填写学期编号。')
  for (const invalid of ['garbage', '2025-2026-3', '2025-26-1']) {
    assert.equal(
      manualTermValidationError(invalid, '2026-03-02'),
      '学期编号格式不正确，请使用 YYYY-YYYY-1 或 YYYY-YYYY-2。',
    )
  }
  assert.equal(manualTermValidationError('2025-2026-2', ''), '请填写第一周周一日期。')
  assert.equal(
    manualTermValidationError('2025-2026-2', '2026-02-30'),
    '第一周周一日期格式不正确，请使用 yyyy-MM-dd。',
  )
  assert.equal(manualTermValidationError('2025-2026-2', '2026-03-02'), '')
})

test('authoritative schedule term wins after a successful automatic refresh', () => {
  const settings = {
    ...DEFAULT_SETTINGS,
    automaticTermDetectionEnabled: true,
    termId: '2026-2027-1',
    termStartDate: '2026-08-31',
  }
  const resolved = settingsWithScheduleTerm(settings, {
    term_id: '2026-2027-1',
    term_start_date: '2026-09-07',
  })
  assert.equal(resolved.termStartDate, '2026-09-07')

  const manual = settingsWithScheduleTerm({
    ...settings,
    automaticTermDetectionEnabled: false,
  }, {
    term_id: '2026-2027-1',
    term_start_date: '2026-09-07',
  })
  assert.equal(manual.termStartDate, '2026-08-31')
})
