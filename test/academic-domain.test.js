import assert from 'node:assert/strict'
import test from 'node:test'
import { academicTimelineHours, courseTimeBounds, courseTimeLabel, FALLBACK_SLOTS, getWeekState } from '../src/planner-domain.js'

const normal = { id: 'ordinary', name: 'Synthetic course', weekday: 1, week_numbers: [1, 2], start_slot: 0, end_slot: 1 }
const exam = { id: 'exam', name: 'Synthetic exam', event_kind: 'exam', event_date: '2026-12-21',
  week_numbers: [], weekday: 1, start_slot: 0, end_slot: 0, start_time: '10:07', end_time: '11:43' }

test('ordinary course periods remain authoritative over stale display times', () => {
  const course = { ...normal, start_slot: 4, end_slot: 5, time_range: '08:00-08:45', start_time: '08:00', end_time: '08:45' }
  const bounds = courseTimeBounds(course, FALLBACK_SLOTS)
  assert.equal(bounds.start, FALLBACK_SLOTS[4].start)
  assert.equal(bounds.end, FALLBACK_SLOTS[5].end)
  assert.deepEqual(getWeekState([course], '2026-08-31', '2026-08-31').busySlots, [4, 5])
})

test('dated exams appear beyond teaching weeks without changing teaching-week bounds', () => {
  const state = getWeekState([normal, exam], '2026-08-31', '2026-12-21')
  assert.equal(state.weekNumber, 0)
  assert.deepEqual(state.dayCourses.map(item => item.id), ['exam'])
  assert.deepEqual(state.busySlots, [2, 3, 4])
  assert.equal(getWeekState([exam], '', exam.event_date).dayCourses.length, 1)
  assert.equal(getWeekState([exam], '2026-08-31', '2026-12-22').dayCourses.length, 0)
})

test('exam bounds use exact minutes, not matching course-slot placeholders', () => {
  assert.deepEqual(courseTimeBounds(exam, FALLBACK_SLOTS), { start: '10:07', end: '11:43', startMinutes: 607, endMinutes: 703, timed: true })
  assert.equal(courseTimeLabel(exam, FALLBACK_SLOTS), '10:07-11:43')
  assert.deepEqual(getWeekState([{ ...exam, start_time: '08:45', end_time: '08:50' }], '2026-08-31', exam.event_date).busySlots, [])
})

test('pending or invalid exam times never invent a busy period or timeline block', () => {
  for (const pair of [['', ''], ['TBD', ''], ['11:43', '10:07'], ['25:00', '26:00'], ['24:00', '24:00']]) {
    const pending = { ...exam, start_time: pair[0], end_time: pair[1] }
    assert.equal(courseTimeBounds(pending, FALLBACK_SLOTS).timed, false)
    assert.equal(courseTimeLabel(pending, FALLBACK_SLOTS, 'Pending'), 'Pending')
    assert.deepEqual(getWeekState([pending], '2026-08-31', exam.event_date).busySlots, [])
    assert.deepEqual(academicTimelineHours([pending], [exam.event_date], FALLBACK_SLOTS, '2026-08-31'), { start: 8, end: 22 })
  }
})

test('axis includes early, late and midnight exam boundaries only for the visible dates', () => {
  const exams = [{ ...exam, start_time: '06:15', end_time: '07:20' }, { ...exam, id: 'late', start_time: '22:50', end_time: '24:00' }]
  assert.deepEqual(academicTimelineHours(exams, [exam.event_date], FALLBACK_SLOTS, '2026-08-31'), { start: 6, end: 24 })
  assert.deepEqual(academicTimelineHours(exams, ['2026-12-22'], FALLBACK_SLOTS, '2026-08-31'), { start: 8, end: 22 })
})
