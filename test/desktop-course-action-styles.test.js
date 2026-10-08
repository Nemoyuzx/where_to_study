import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replace(/\r\n/g,'\n')
const course=read('src/CourseHub.jsx'),queries=read('src/PrivateQueriesPanel.jsx'),css=read('src/App.css')
const rules=[...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)]
const rule=selector=>rules.find(match=>match[1].split(',').map(value=>value.trim()).includes(selector))?.[2]

function themed(scope) {
  const selector=`${scope} > .query-action-button`
  const base=rule(selector)
  assert.ok(base, `${selector} must match the shared action style`)
  assert.match(base,/background:\s*var\(--primary-surface\)/)
  assert.match(base,/border-radius:\s*8px/)
  assert.match(base,/display:\s*inline-flex/)
  assert.match(rule(`${selector}:hover`)||'',/background:\s*var\(--primary-fill\)/)
  assert.match(rule(`${selector}:focus-visible`)||'',/outline:\s*2px solid var\(--primary\)/)
  assert.equal(rule('.query-action-button'),undefined,'do not broaden these scoped actions to every button in the app')
}

test('course account entry has a themed scoped action and an existing Lucide settings icon',()=>{
  assert.match(course,/!hasAcademicAccount&&<button className="query-action-button" onClick=\{onOpenAccount\}><Settings2 size=\{16\}\/>/)
  assert.match(course,/import \{[^}]*\bSettings2\b[^}]*\} from 'lucide-react'/)
  themed('.course-hub')
})

test('existing assignment refresh action matches styles in both inline and detail bodies',()=>{
  assert.match(course,/<button type="button" className="query-action-button" disabled=\{busy\} onClick=\{onRefresh\}><RefreshCw size=\{16\}\/>/)
  assert.match(course,/<div className="course-inline-body">\s*<CourseActivityBody/)
  assert.match(course,/<div className="course-detail-body">\s*<CourseActivityBody/)
  themed('.course-inline-body')
  themed('.course-detail-body')
})

test('course assignment pagination reuses the scoped action and existing ChevronDown SVG entry',()=>{
  assert.match(course,/items\?\.length>limit&&<button type="button" className="query-action-button" onClick=\{\(\)=>setLimit\(value=>value\+30\)\}><ChevronDown size=\{16\}\/>/)
  assert.match(course,/import \{[^}]*\bChevronDown\b[^}]*\} from 'lucide-react'/)
  themed('.course-inline-body')
  themed('.course-detail-body')
})

test('private-query pagination has a themed direct-child action and Lucide ChevronDown entry',()=>{
  assert.match(queries,/limit < filtered\.length && <button type="button" className="query-action-button" onClick=\{\(\) => setLimit\(v => v \+ 30\)\}><ChevronDown size=\{16\}\/>/)
  assert.match(queries,/import \{[^}]*\bChevronDown\b[^}]*\} from 'lucide-react'/)
  themed('.query-grades')
})
