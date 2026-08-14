import assert from 'node:assert/strict'
import test from 'node:test'
import {
  accountHasSavedPassword,
  buildingsForCampus,
  FALLBACK_SLOTS,
  fallbackHolidayItems,
  getCampusClassrooms,
  getScheduleExamWeeks,
  getWeekState,
  isValidAccountScope,
  normalizeClassroomsCache,
  savedSettingsToState,
  settingsToPayload,
  shiftDate,
  slotsToRanges,
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

test('exam weeks are the seventeenth and eighteenth existing schedule weeks', () => {
  const existingWeeks = [1, 2, 4, 5, 7, 8, 10, 11, 13, 14, 16, 17, 19, 20, 22, 23, 25, 26]
  const course = {
    id: 'exam-course',
    name: '考试课程',
    weekday: 1,
    week_numbers: existingWeeks,
    exam_week_numbers: [],
    start_slot: 0,
    end_slot: 1,
  }

  assert.deepEqual(getScheduleExamWeeks([course]), [25, 26])
  assert.equal(getWeekState([course], '2026-01-05', '2026-06-22').dayCourses[0].is_exam, true)
})

test('slot ranges merge adjacent sections and preserve gaps', () => {
  assert.deepEqual(slotsToRanges([0, 1, 3, 3], FALLBACK_SLOTS), [
    { start: 0, end: 1, label: '08:00-09:35' },
    { start: 3, end: 3, label: '10:40-11:25' },
  ])
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
  })

  assert.equal(state.password, '')
  assert.equal(state.hasSavedPassword, true)
  assert.equal(state.dailyCourseNotificationsEnabled, true)
  assert.equal(settingsToPayload(state).daily_course_notifications_enabled, true)
  assert.equal(accountHasSavedPassword(' student ', { account: 'student', hasSavedPassword: true }), true)
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
