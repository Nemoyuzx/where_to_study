import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
test('course directory refresh uses the shared command payload envelope exactly once',()=>{
  const hub=readFileSync(new URL('../src/course-data-owner.js',import.meta.url),'utf8')
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8')
  assert.match(app,/return await invoke\(name, \{ payload \}\)/)
  assert.match(hub,/command\('fetch_course_list',\{catalogue:true,cache_only:false,force\}\)/)
  assert.doesNotMatch(hub,/command\('fetch_course_list',\{payload:/)
})
