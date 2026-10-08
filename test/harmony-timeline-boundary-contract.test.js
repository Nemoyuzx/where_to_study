import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL('../native/harmony/entry/src/main/ets/' + path, import.meta.url), 'utf8').replace(/\r\n/g, '\n')
const mobile = read('view/calendar/MobileTeachingCalendarView.ets')
const start = mobile.indexOf('  timelineContent(')
const end = mobile.indexOf('  private timelineCoursework(', start)
assert.ok(start >= 0 && end > start, 'inspect the actual mobile day/week timeline builder')
const builder = mobile.slice(start, end)
const scrollStart = builder.indexOf('      Scroll(interactive ? this.timelineScroller : this.incomingTimelineScroller)')
assert.ok(scrollStart >= 0, 'current and incoming timelines retain their native scrollers')
const scroll = builder.slice(scrollStart)

test('reported mobile day/week timeline has native rebound at both boundaries', () => {
  assert.match(scroll, /\.scrollable\(ScrollDirection\.Vertical\)/)
  assert.match(scroll, /\.edgeEffect\(EdgeEffect\.Spring, \{ alwaysEnabled: true \}\)\s*\.width\('100%'\)\s*\.id\('calendar\.mobile\.timeline-scroll'\)/)
  assert.doesNotMatch(scroll, /EdgeEffect\.(Fade|None)|\.enableScrollInteraction\(false\)/)
})

test('timeline rebound keeps fixed headers, course geometry and initial positioning', () => {
  const fixedHeader = builder.slice(0, scrollStart)
  assert.match(fixedHeader, /this\.selectedDateSummary\(/)
  assert.match(fixedHeader, /this\.selectedDateCourses\(/)
  assert.match(fixedHeader, /this\.allDayItems\(renderMode, renderDate, interactive\)/)
  assert.doesNotMatch(scroll, /this\.selectedDateSummary\(|this\.selectedDateCourses\(|this\.allDayItems\(/)
  assert.match(scroll, /placements: MobileCalendarTimelineView\.placementsFor\(/)
  assert.match(scroll, /this\.scrollTimelineToInitialHour\(renderMode, renderDate, this\.timelineScroller\)/)
  assert.match(scroll, /PanGesture\(\{ fingers: 1, direction: PanDirection\.Horizontal, distance: 18 \}\)/)
  assert.match(read('view/calendar/MobileCalendarTimelineView.ets'), /static readonly hourHeight: number = 72;/)
  assert.match(read('common/ControlMetrics.ets'), /static readonly height: number = 32;/)
})
