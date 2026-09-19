import test from 'node:test'
import assert from 'node:assert/strict'
import { DEFAULT_SETTINGS, normalizeCourseReminderMinutes, validCourseReminderMinutes,
  reminderSettingsPayload, savedSettingsToState, settingsToPayload } from '../src/planner-domain.js'

test('pre-class defaults are independent from the daily summary', () => {
  assert.equal(DEFAULT_SETTINGS.courseRemindersEnabled, false)
  assert.deepEqual(savedSettingsToState({}).courseReminderMinutes, [10])
  const saved = savedSettingsToState({ account: 'saved-account', course_reminders_enabled: true, course_reminder_minutes: [10, 5] })
  assert.equal(saved.dailyCourseNotificationsEnabled, false)
  assert.deepEqual(settingsToPayload(saved).course_reminder_minutes, [10, 5])
  const payload = reminderSettingsPayload(saved, true, 450, true, [15, 5])
  assert.equal(payload.account, 'saved-account')
  assert.equal(payload.password, null)
  assert.deepEqual(payload.course_reminder_minutes, [15, 5])
  assert.equal(payload.daily_course_notifications_enabled, true)
})

test('custom lead values and count are validated rather than silently saved', () => {
  for (const value of [[], [0], [-1], [1441], [5.5], ['10'], [10, 10], [1, 2, 3, 4, 5, 6], null]) {
    assert.equal(validCourseReminderMinutes(value), false)
    assert.deepEqual(normalizeCourseReminderMinutes(value), [10])
    if (value !== null) assert.throws(() => reminderSettingsPayload(DEFAULT_SETTINGS, false, 450, true, value))
  }
  for (const value of [[5], [10, 5], [1440, 60, 10, 5, 1]]) assert.equal(validCourseReminderMinutes(value), true)
})

test('round trips and daily-only edits preserve the pre-class preference', () => {
  const original = { ...DEFAULT_SETTINGS, courseRemindersEnabled: true, courseReminderMinutes: [30, 10, 5] }
  const payload = reminderSettingsPayload(original, true, 480)
  const restored = savedSettingsToState(payload)
  assert.equal(restored.courseRemindersEnabled, true)
  assert.deepEqual(restored.courseReminderMinutes, original.courseReminderMinutes)
  assert.equal(restored.dailyCourseNotificationMinutes, 480)
  const copy = normalizeCourseReminderMinutes(original.courseReminderMinutes)
  copy.push(2)
  assert.equal(original.courseReminderMinutes.length, 3)
})
