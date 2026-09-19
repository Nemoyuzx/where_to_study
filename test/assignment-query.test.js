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
  const hub = readFileSync(new URL('../src/QueryHub.jsx', import.meta.url), 'utf8')
  const panel = readFileSync(new URL('../src/PrivateQueriesPanel.jsx', import.meta.url), 'utf8')
  const capabilities = JSON.parse(readFileSync(new URL('../src-tauri/capabilities/default.json', import.meta.url)))
  for (const kind of ['shuttle', 'events', 'grades', 'exams', 'assignments']) assert.ok(hub.includes(`setTab('${kind}')`))
  for (const command of ['fetch_assignment_list', 'fetch_exams']) {
    assert.ok(panel.includes(`command('${command}'`))
    assert.ok(capabilities.permissions.includes(`allow-${command.replaceAll('_', '-')}`))
  }
  assert.ok(panel.includes('revision.current !== id'))
  assert.ok(panel.includes('slice(0, limit)'))
})
