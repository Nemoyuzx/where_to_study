import assert from 'node:assert/strict'
import test from 'node:test'

import {
  calendarSurfaceKey,
  calendarTransition,
  queuedCalendarPage,
} from '../src/planner-domain.js'

test('repeated forward pages each have a new animated surface even when direction stays next', () => {
  for (const view of ['day', 'week', 'month', 'year']) {
    let date = '2026-10-02'
    for (let step = 0; step < 3; step += 1) {
      const target = queuedCalendarPage(date, view, null, 1)
      assert.equal(calendarTransition(date, view, target.date, target.view).motion, 'next')
      assert.notEqual(calendarSurfaceKey(view, date), calendarSurfaceKey(target.view, target.date))
      date = target.date
    }
  }
})

test('rapid calendar intent accumulates forward clicks and allows a reverse to cancel one', () => {
  const current = queuedCalendarPage('2026-10-02', 'week', null, 1)
  const second = queuedCalendarPage(current.date, current.view, null, 1)
  const third = queuedCalendarPage(current.date, current.view, second, 1)
  assert.deepEqual([current.date, second.date, third.date], [
    '2026-10-09', '2026-10-16', '2026-10-23',
  ])

  const reversed = queuedCalendarPage(current.date, current.view, second, -1)
  assert.deepEqual(reversed, current)
  assert.equal(calendarTransition(current.date, current.view, reversed.date, reversed.view).motion, '')
})
