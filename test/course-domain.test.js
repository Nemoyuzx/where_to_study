import test from 'node:test'
import assert from 'node:assert/strict'
import {assignmentsForCourse, groupTeachingCloudCourses, teachingCloudCourseIDs, isEbuCourse, submissionCounts, courseTimestamp, courseActivityKey, CourseRequestOwner} from '../src/course-domain.js'

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
test('current Teaching Cloud presentation groups exact trimmed names and retains all original records and teachers',()=>{
  const courses=[
    {id:'class-a',name:'  通信原理 ',teacher_names:[' 张老师 ','李老师'],url:'https://ucloud.bupt.edu.cn/'},
    {id:'other',name:'通信原理实验',teacher_names:['实验老师']},
    {id:'class-b',name:'通信原理',teacher_names:['张老师','王老师','李老师','']},
    {id:'missing-a',name:null,teacher_names:[]},{id:'missing-b',name:' ',teacher_names:[]},
    {id:'case-a',name:'English Course',teacher_names:[]},{id:'case-b',name:'english Course',teacher_names:[]},
    {id:'spacing',name:'English  Course',teacher_names:[]}
  ]
  const snapshot=structuredClone(courses)
  const groups=groupTeachingCloudCourses(courses)
  assert.equal(groups.length,7)
  assert.equal(groups[0].name,'通信原理')
  assert.deepEqual(groups[0].teacher_names,['张老师','李老师','王老师'])
  assert.deepEqual(teachingCloudCourseIDs(groups[0]),['class-a','class-b'])
  assert.equal(groups[0].source_courses[0],courses[0])
  assert.equal(groups[0].source_courses[1],courses[2])
  assert.notEqual(groups[2].presentation_key,groups[3].presentation_key)
  assert.deepEqual(courses,snapshot)
  const reversed=groupTeachingCloudCourses([...courses].reverse()).find(course=>course.name==='通信原理')
  assert.equal(reversed.presentation_key,groups[0].presentation_key)
})
test('merged course activities include every teaching class without losing colliding assignment IDs or inferring a foreign ID',()=>{
  const directory=[{id:'a',name:'Course',teacher_names:['One']},{id:'b',name:' Course ',teacher_names:['Two']},
    {id:'c',name:'Course lab',teacher_names:[]}]
  const [course]=groupTeachingCloudCourses(directory)
  const items=[
    {id:'same',course_id:'a',title:'Class A task',deadline:'2026-10-09 12:00:00',status:'未提交'},
    {id:'same',course_id:'b',title:'Class B task',deadline:'2026-10-09 12:00:00',status:'已提交'},
    {id:'later',course_id:'b',title:'Second class task',status:'not submitted'},
    {id:'legacy',course_name:' Course ',title:'Older name-only task',status:'Submitted'},
    {id:'foreign',course_id:'not-in-directory',course_name:'Course',status:'未提交'},
    {id:'lab',course_id:'c',course_name:'Course lab',status:'未提交'}
  ]
  const selected=assignmentsForCourse(items,course,directory)
  assert.deepEqual(selected,items.slice(0,4))
  assert.equal(selected[1],items[1])
  assert.deepEqual(submissionCounts(selected),{pending:2,submitted:2})
  assert.notEqual(courseActivityKey(selected[0]),courseActivityKey(selected[1]))
  assert.equal(assignmentsForCourse(null,course,directory),null)
  assert.deepEqual(assignmentsForCourse([],course,directory),[])
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
