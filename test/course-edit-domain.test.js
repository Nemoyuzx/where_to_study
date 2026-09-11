import assert from 'node:assert/strict'
import test from 'node:test'
import {
  applyCourseDeletions, courseEditRequest, DEFAULT_SETTINGS, getWeekState,
  savedSettingsToState, settingsToPayload, settingsWithCredentialDraft, reminderSettingsPayload,
  semesterSettingsPayload,
} from '../src/planner-domain.js'

const course = (extra = {}) => ({
  id: 'row-one', source_course_id: 'source-one', name: 'Course', teacher: 'Teacher', room: 'A',
  week_numbers: [1, 2, 3], weekday: 1, start_slot: 0, end_slot: 1, ...extra,
})
const schedule = (courses = [course()]) => ({
  term_id: '2026-2027-1', term_start_date: '2026-08-31', courses,
})
const rule = (extra = {}) => ({
  id: 'removal-one', term_id: '2026-2027-1', source_course_id: 'source-one', name: 'Course',
  teacher: 'Teacher', date: null, start_slot: 0, end_slot: 1, ...extra,
})

test('course edit payload is scoped to the saved identity and distinguishes occurrence and course', () => {
  assert.deepEqual(courseEditRequest(' student ', '2026-2027-1', 'raw-course', '2026-09-07'), {
    account: 'student', term_id: '2026-2027-1', course_id: 'raw-course', date: '2026-09-07',
  })
  assert.equal(courseEditRequest('student', '2026-2027-1', 'removal-id').date, null)
  assert.throws(() => courseEditRequest('', '2026-2027-1', 'course'))
  assert.throws(() => courseEditRequest('student', 'wrong-term', 'course'))
  assert.throws(() => courseEditRequest('student', '2026-2027-1', 'course', '2026-02-30'))
})

test('single occurrence filtering preserves other weeks, dates, periods, and the raw cache', () => {
  const raw = schedule([course(), course({ id: 'later', start_slot: 4, end_slot: 5 }),
    course({ id: 'wednesday', weekday: 3 })])
  const filtered = applyCourseDeletions(raw, [rule({ date: '2026-09-07' })])
  assert.deepEqual(filtered.courses[0].week_numbers, [1, 3])
  assert.deepEqual(filtered.courses[1].week_numbers, [1, 2, 3])
  assert.deepEqual(filtered.courses[2].week_numbers, [1, 2, 3])
  assert.deepEqual(raw.courses[0].week_numbers, [1, 2, 3])
  assert.deepEqual(getWeekState(filtered.courses, raw.term_start_date, '2026-09-07').busySlots, [4, 5])
})

test('whole courses survive row and room changes and recover without affecting another source or term', () => {
  const raw = schedule([course({ id: 'changed-row', room: 'Changed' }),
    course({ id: 'other', source_course_id: 'source-other' })])
  assert.equal(applyCourseDeletions(raw, [rule()]).courses.length, 1)
  assert.equal(applyCourseDeletions(raw, [rule({ term_id: '2026-2027-2' })]).courses.length, 2)
  assert.equal(applyCourseDeletions(raw, []).courses.length, 2)
  assert.equal(applyCourseDeletions(schedule(), [rule({ source_course_id: '' })]).courses.length, 0)
  assert.equal(applyCourseDeletions(schedule(), [rule({ source_course_id: '', teacher: 'Other' })]).courses.length, 1)
})

test('cloud secrets remain blank on hydration, preserve on blank edits, and clear only explicitly', () => {
  const saved = savedSettingsToState({ account: 'student', has_saved_password: true,
    password: 'must-not-hydrate', teaching_cloud_password: 'must-not-hydrate',
    has_saved_teaching_cloud_password: true })
  assert.equal(saved.password, '')
  assert.equal(saved.teachingCloudPassword, '')
  assert.equal(settingsToPayload(saved).teaching_cloud_password, null)
  assert.equal(settingsToPayload(saved).clear_teaching_cloud_password, false)
  const withDraft = settingsWithCredentialDraft(saved, 'teachingCloudPassword', 'cloud-test', {})
  assert.equal(settingsToPayload(withDraft).teaching_cloud_password, 'cloud-test')
  const reset = settingsWithCredentialDraft(withDraft, 'clearTeachingCloudPassword', true, {})
  assert.equal(reset.teachingCloudPassword, '')
  assert.equal(settingsToPayload(reset).clear_teaching_cloud_password, true)
  const newDraft = settingsWithCredentialDraft(reset, 'teachingCloudPassword', 'replacement', {})
  assert.equal(newDraft.clearTeachingCloudPassword, false)
})

test('changing accounts discards cloud drafts and does not inherit the old saved cloud flag', () => {
  const snapshot = { account: 'student', hasSavedPassword: true, hasSavedTeachingCloudPassword: true }
  const draft = { ...DEFAULT_SETTINGS, account: 'student', teachingCloudPassword: 'cloud-test', clearTeachingCloudPassword: true }
  const changed = settingsWithCredentialDraft(draft, 'account', 'other', snapshot)
  assert.equal(changed.teachingCloudPassword, '')
  assert.equal(changed.hasSavedTeachingCloudPassword, false)
  assert.equal(changed.clearTeachingCloudPassword, false)
  assert.equal(settingsWithCredentialDraft(changed, 'account', ' student ', snapshot).hasSavedTeachingCloudPassword, true)
  const saved = savedSettingsToState({ account: 'student', has_saved_teaching_cloud_password: true })
  assert.equal(reminderSettingsPayload(saved, true, 450).teaching_cloud_password, null)
  assert.equal(reminderSettingsPayload(saved, true, 450).clear_teaching_cloud_password, false)
  const termPayload = semesterSettingsPayload(saved, {
    ...draft, account: 'not-saved', termId: '2026-2027-2', termStartDate: '2027-03-01',
    automaticTermDetectionEnabled: false,
  })
  assert.equal(termPayload.account, 'student')
  assert.equal(termPayload.teaching_cloud_password, null)
  assert.equal(termPayload.clear_teaching_cloud_password, false)
  assert.equal(termPayload.term_id, '2026-2027-2')
})
