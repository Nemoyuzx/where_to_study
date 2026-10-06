import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8')
const root = '../native/harmony/entry/src/'
const timeline = read(`${root}main/ets/view/calendar/MobileCalendarTimelineView.ets`)
const projection = read(`${root}main/ets/view/calendar/CalendarCourseworkProjection.ets`)
const markerStart = timeline.indexOf('ForEach(this.moments(day)')
const marker = timeline.slice(markerStart, timeline.indexOf('if (this.isNowVisible())', markerStart))

test('Harmony deadline anchors and full-width 18vp strips use live primary/onPrimary, not fixed orange', () => {
  assert(marker.length > 0)
  assert.match(marker, /\.backgroundColor\(AppTheme\.primary\(\)\)/)
  assert.match(marker, /\.fontColor\(AppTheme\.onPrimary\(\)\)/)
  assert.match(marker, /\.fill\(AppTheme\.onPrimary\(\)\)/)
  assert.doesNotMatch(marker, /#[0-9a-f]{3,8}|orange/i)
  assert.match(marker, /\.height\(18\)\.width\(CalendarDeadlineMoments\.barWidth\(this\.dayWidthValue\(\)\)\)/)
  assert.match(projection, /barWidth\(dayWidth: number\): number \{ return Math\.max\(dayWidth - 8, 0\); \}/)
  assert.match(projection, /barX\(dayWidth: number, index: number\): number \{ return dayWidth \* index \+ 4; \}/)
  assert.match(marker, /moment\.clock\(\) \+ ' · ' \+ moment\.items\[0\]\.title/)
  assert.match(marker, /TextOverflow\.Ellipsis/)
  assert.match(marker, /y: this\.yPos\(moment\.minute\)/)
  assert.match(marker, /y: moment\.top/)
})

test('Harmony shows a six-vp red pending dot only through existing evidence, without intercepting clicks or clipping at midnight', () => {
  assert.match(marker, /if \(CalendarDeadlineMoments\.showsPending\(moment\.items\)\) \{\s*Circle\(\)\.width\(6\)\.height\(6\)\.fill\(AppTheme\.danger\(\)\)/)
  assert.match(marker, /y: Math\.max\(0, moment\.top - 3\)/)
  assert.match(marker, /\.hitTestBehavior\(HitTestMode\.None\)\.zIndex\(5\)/)
  assert.match(projection, /CourseCloudScope\.submissionCounts\(\[item\]\)\.pending > 0/)
  assert.match(projection, /item\.kind === 'assignment' && CourseCloudScope\.submissionCounts/)
  assert.match(projection, /item\.kind === 'assignment' && item\.pending/)
  assert.match(marker, /this\.onOpenCoursework\(moment\.items\[0\], day\.date\)/)
  assert.match(marker, /this\.onMoreCoursework\(moment\.items, day\.date\)/)
})

test('both Harmony day/week consumers project the fenced full catalog independently of old all-day buckets and register all eight pure cases', () => {
  for (const name of ['MobileTeachingCalendarView', 'ExpandedTeachingCalendarView']) {
    const source = read(`${root}main/ets/view/calendar/${name}.ets`)
    const start = source.indexOf('private timelineCoursework(')
    const consumer = source.slice(start, source.indexOf('private timelineDays(', start))
    assert.match(consumer, /CalendarDeadlineMoments\.cloudOn\(date, this\.model\.assignmentMomentCatalog, this\.model\.cloudCourses\)/)
    assert.match(consumer, /CalendarCourseworkProjection\.qm\(date, this\.qmPlusSession\.snapshot\)/)
    assert.doesNotMatch(consumer, /assignmentDeadlinesByDate/)
  }
  const owner = read(`${root}main/ets/model/AppModel.ets`)
  assert.match(owner, /if \(!current\(\)\) \{ return; \}\s*this\.assignmentMomentCatalog = items;/)
  assert.match(owner, /this\.assignmentMomentCatalog = \[\];/)
  const registry = read(`${root}test/List.test.ets`)
  assert.match(registry, /import calendarDeadlineMomentsTest from '\.\/CalendarDeadlineMoments\.test';/)
  assert.match(registry, /calendarDeadlineMomentsTest\(\);/)
  assert.equal([...read(`${root}test/CalendarDeadlineMoments.test.ets`).matchAll(/\bit\('/g)].length, 8)
})
