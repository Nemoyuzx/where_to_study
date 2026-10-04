import test from 'node:test'
import assert from 'node:assert/strict'
import {assignmentsForCourse, isEbuCourse, submissionCounts, courseTimestamp, courseActivityKey, CourseRequestOwner} from '../src/course-domain.js'

test('QM EBU scope is anchored on the full name, not a substring or short-name guess',()=>{
  assert.equal(isEbuCourse({name:'  ebu1234 - Fixture'}),true)
  assert.equal(isEbuCourse({name:'Training EBU1234',short_name:'EBU1234'}),false)
  assert.equal(isEbuCourse({name:null}),false)
})
test('course association uses official ID and rejects ambiguous same-name old cache',()=>{
  const a={id:'a',name:'Same'},b={id:'b',name:'Same'}
  const items=[{id:1,course_id:'a',course_name:'Renamed'},{id:2,course_id:'b',course_name:'Same'},{id:3,course_name:'Same'}]
  assert.deepEqual(assignmentsForCourse(items,a,[a,b]).map(i=>i.id),[1])
  assert.deepEqual(assignmentsForCourse(items,a,[a]).map(i=>i.id),[1,3])
  assert.equal(assignmentsForCourse(null,a,[a]),null)
})
test('course chips count only explicit Assignment submission states, not Quiz completion',()=>{
  const counts=submissionCounts([{status:' 未提交 '},{status:'NOT SUBMITTED'},{status:'Nothing submitted'},
    {status:'No submissions have been made yet'},{status:'已提交'},{status:'Submitted'},{status:'Submitted for grading'},
    {status:'已批改'},{status:'已驳回'},{status:'已完成'},{status:'complete'},
    {kind:'quiz',status:'submitted'},{status:'unknown'}])
  assert.deepEqual(counts,{pending:4,submitted:3})
  assert.deepEqual(submissionCounts(null),{pending:0,submitted:0})
})
test('Teaching Cloud wall-clock deadlines use Shanghai independently of system timezone',()=>{
  assert.equal(courseTimestamp('2026-10-09 12:00:00'),Date.parse('2026-10-09T04:00:00Z'))
  assert.equal(courseTimestamp('2026-10-09T09:00:00.000Z'),Date.parse('2026-10-09T09:00:00Z'))
  assert.ok(Number.isNaN(courseTimestamp(null)))
})
test('course activity keys preserve the backend id-plus-deadline distinction',()=>{
  const a={id:'same',course_id:'course',deadline:'2026-10-09 12:00:00'}
  assert.notEqual(courseActivityKey(a),courseActivityKey({...a,deadline:'2026-10-10 12:00:00'}))
})
test('closing or changing a detail rejects its late errors while retaining independent catalogue ownership',()=>{
  const owner=new CourseRequestOwner()
  const a=owner.next('detail'),catalogue=owner.next('assignments')
  owner.next('detail') // close A
  owner.next('detail') // open B
  assert.equal(owner.accepts('detail',a),false)
  assert.equal(owner.accepts('assignments',catalogue),true)
  owner.next('assignments') // newer explicit query refresh
  assert.equal(owner.accepts('assignments',catalogue),false)
})
test('independent QM and directory loads cannot revive older snapshots after replacement or disposal',()=>{
  const owner=new CourseRequestOwner(),qm=owner.next('qm'),directory=owner.next('directory')
  owner.next('qm') // disconnect/change event's subsequent local read
  assert.equal(owner.accepts('qm',qm),false)
  assert.equal(owner.accepts('directory',directory),true)
  const lifecycle=owner.next('lifecycle')
  owner.dispose();owner.live=true;owner.next('lifecycle') // React strict-mode remount
  assert.equal(owner.accepts('lifecycle',lifecycle),false)
  assert.equal(owner.accepts('directory',directory),false)
})
