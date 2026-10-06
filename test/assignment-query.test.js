import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { filterAssignmentQueries } from '../src/query-domain.js'

const items = [
  { id: 'b', title: 'Essay', course_name: 'English', deadline: '2026-09-20 12:00:00', status: '未提交' },
  { id: 'a', title: 'Math assignment', course_name: 'Math', deadline: '2026-09-19T12:00:00+08:00', status: '已提交' },
  { id: 'c', title: 'Pending', course_name: 'Math', deadline: 'unknown' },
]
test('assignment catalogue keeps completed work and filters locally in Shanghai time', () => {
  const now = new Date('2026-09-20T04:00:00Z')
  assert.deepEqual(filterAssignmentQueries(items).map(x => x.id), ['a', 'b', 'c'])
  assert.deepEqual(filterAssignmentQueries(items, { range: 'upcoming', now }).map(x => x.id), ['b'])
  assert.deepEqual(filterAssignmentQueries(items, { range: 'past', now }).map(x => x.id), ['a'])
  assert.deepEqual(filterAssignmentQueries(items, { course: 'Math', query: 'ASSIGNMENT' }).map(x => x.id), ['a'])
  assert.equal(items[0].id, 'b')
})
test('query panels are independently addressable and use native private commands', () => {
  const hub = readFileSync(new URL('../src/CourseHub.jsx', import.meta.url), 'utf8')
  const publicHub = readFileSync(new URL('../src/QueryHub.jsx', import.meta.url), 'utf8')
  const panel = readFileSync(new URL('../src/PrivateQueriesPanel.jsx', import.meta.url), 'utf8')
  const capabilities = JSON.parse(readFileSync(new URL('../src-tauri/capabilities/default.json', import.meta.url)))
  for (const kind of ['shuttle', 'events']) assert.ok(publicHub.includes(`setTab('${kind}')`))
  for (const kind of ['grades', 'exams', 'assignments']) assert.ok(hub.includes(`'${kind}'`))
  assert.doesNotMatch(publicHub, /<GradesPanel|<PrivateQueriesPanel/)
  assert.ok(panel.includes('await courseDataOwner?.refresh(true)'))
  assert.ok(panel.includes('useCourseData(courseDataOwner)'))
  assert.doesNotMatch(panel, /command\('fetch_assignment_(?:list|calendar)'/)
  assert.ok(panel.includes("command('fetch_exams'"))
  const owner = readFileSync(new URL('../src/course-data-owner.js', import.meta.url), 'utf8')
  assert.equal((owner.match(/this\.command\('fetch_course_list'/g) || []).length, 2, 'only cache hydration and the shared refresh may issue course commands')
  assert.ok(owner.includes('if(this.cloudFlight)return this.cloudFlight'))
  for (const command of ['fetch_assignment_list', 'fetch_exams']) {
    assert.ok(capabilities.permissions.includes(`allow-${command.replaceAll('_', '-')}`))
  }
  assert.ok(panel.includes('revision.current !== id'))
  assert.ok(panel.includes('slice(0, limit)'))
  const app = readFileSync(new URL('../src/App.jsx', import.meta.url), 'utf8')
  const dateLoader = app.slice(app.indexOf('  async function loadAssignments('),app.indexOf('  async function loadCalendarSupplements('))
  assert.match(dateLoader,/assignmentsForDates\(date,date,\{force\}\)/,'calendar retry must pass force to the shared owner')
  const rangeLoader = app.slice(app.indexOf('  async function loadCalendarSupplements('),app.indexOf('  async function importSystemCalendar('))
  assert.equal((rangeLoader.match(/assignmentsForDates\(/g)||[]).length,1,'one range command precedes local per-date distribution')
  assert.doesNotMatch(rangeLoader,/rangeDates\.forEach\([^)]*assignmentsForDates|assignmentsForDates\([^\n]*force:true/)
  const notice = app.slice(app.indexOf('      {newAssignmentCount>0 ? ('),app.indexOf('      {courseEditDialog ? ('))
  assert.match(notice,/setActivePage\('courses'\)/,'the shared course destination includes UCloud and QMplus')
  assert.match(notice,/newAssignments\.slice\(0,8\)\.map/,'a large batch renders no more than eight preview rows')
  assert.match(notice,/uiFormat\(uiLanguage,'发现 %1\$d 项新作业',\[newAssignmentCount\]\)/,'the title uses the full unconfirmed batch count')
  assert.match(notice,/newAssignmentCount>newAssignments\.length[\s\S]*?newAssignmentCount-newAssignments\.length/,'the summary exposes the remaining count rather than discarding it')
  assert.doesNotMatch(notice,/newAssignments\.map\(/,'the popup never expands every queued notice into DOM nodes')
  assert.doesNotMatch(notice,/setActivePage\('query'\)|refresh\(|assignmentsForDates\(/,'opening notices cannot issue another data request or route QM tasks to the cloud-only query')
})
