import assert from 'node:assert/strict'
import test from 'node:test'
import {readFileSync} from 'node:fs'
import {transformSync} from 'esbuild'
import React from 'react'
import * as runtime from 'react/jsx-runtime'
import * as domain from '../src/course-domain.js'
import * as text from '../src/ui-text.js'

const task=(id,deadline)=>({id,title:`Task ${id}`,course_id:'cloud',course_name:'Course',deadline})
const snapshot=assignments=>({assignments,qm:null})
test('only explicit valid deadline timestamps project; UTC dates convert independently of old date-prefix buckets',()=>{
  for(const value of ['2026-10-06','unknown','2026-02-30 12:00:00','2026-10-06 24:00:00','2026-10-06 12:60:00','2026-10-06 12:30:60'])assert.equal(domain.deadlineMoment(value),null,value)
  const midnight=domain.deadlineMoment('2026-10-06T16:00:00Z')
  assert.equal(midnight.date,'2026-10-07');assert.equal(midnight.minute,0);assert.equal(midnight.clock,'00:00')
  assert.equal(domain.deadlineMoment('2026-10-07 23:59:00').minute,1439)
  assert.equal(domain.deadlineMoment('2026-10-07 07:15:30').minute,435.5)
  assert.equal(domain.deadlineMoment('2026-10-07T07:15:00.500').minute,435+0.5/60)
  assert.equal(domain.deadlineMoment('2026-10-07 12:00:00','qmplus'),null,'QM time must already have an official zone')
  const raw=task('cross-day','2026-10-06T16:00:00Z')
  const groups=domain.courseDeadlineMomentGroups(snapshot([raw]))
  assert.equal(groups.filter(group=>group.date==='2026-10-06').length,0)
  assert.equal(groups.filter(group=>group.date==='2026-10-07')[0].items[0].assignmentItem.id,raw.id)
  assert.equal(raw.source,undefined,'the full owner record is not mutated')
})

test('QM points use due or quiz close only, current EBU policy and exact source-specific click payloads',()=>{
  const courses=[{id:'ebu',name:'EBU Course',current_term_status:'current'},{id:'other',name:'Other',current_term_status:'current'},{id:'unknown',name:'EBU Unknown',current_term_status:'unknown'}]
  const activities=[
    {id:'assignment',course_id:'ebu',kind:'assignment',title:'Assignment',due_at:'2026-10-07T04:00:00Z'},
    {id:'quiz',course_id:'ebu',kind:'quiz',title:'Quiz',closes_at:'2026-10-07T04:00:00Z',due_at:'2026-10-07T05:00:00Z'},
    {id:'cutoff-only',course_id:'ebu',kind:'assignment',title:'No due time',cutoff_at:'2026-10-07T04:00:00Z'},
    {id:'admin',course_id:'ebu',kind:'assignment',title:'Coursework Mark Review Request',due_at:'2026-10-07T04:00:00Z'},
    {id:'other',course_id:'other',kind:'assignment',title:'Other',due_at:'2026-10-07T04:00:00Z'},
    {id:'unknown',course_id:'unknown',kind:'assignment',title:'Unknown',due_at:'2026-10-07T04:00:00Z'},
  ]
  const groups=domain.courseDeadlineMomentGroups({assignments:[task('cloud','2026-10-07 12:00:00')],qm:{courses,activities}})
  assert.equal(groups.length,1)
  assert.deepEqual(groups[0].items.map(item=>item.source),['ucloud','qmplus','qmplus'])
  assert.deepEqual(groups[0].items.map(item=>item.assignmentItem.id),['cloud','assignment','quiz'])
  assert.equal(groups[0].items[2].assignmentItem.source,'qmplus')
  assert.equal(groups[0].items[2].clock,'12:00')
  assert(!Object.hasOwn(groups[0],'duration'));assert(!Object.hasOwn(groups[0],'endMinutes'))
})

test('bounds expose midnight, pre-eight and 23:59 without compressing the original lesson pixel scale',()=>{
  const base={start:8,end:22},groups=domain.courseDeadlineMomentGroups(snapshot([task('midnight','2026-10-07 00:00:00'),task('early','2026-10-07 07:15:00'),task('late','2026-10-07 23:59:00')]))
  const axis=domain.timelineForDeadlineMoments(base,groups)
  assert.equal(axis.start,0);assert.equal(axis.end,24)
  for(const height of [896,900,1200])assert(Math.abs(90/((axis.end-axis.start)*60)*height*axis.scale-90/((base.end-base.start)*60)*height)<1e-9)
  assert.deepEqual(domain.timelineForDeadlineMoments(base,[]),{...base,scale:1})
})

test('dense tail badges merge after clamping while all exact deadline anchors survive',()=>{
  const groups=domain.courseDeadlineMomentGroups(snapshot([task('a','2026-10-07 23:40:00'),task('b','2026-10-07 23:58:00'),task('c','2026-10-07 23:59:00')]))
  const badges=domain.deadlineMomentBadges(groups,[],0,1440,896/840)
  assert.deepEqual(groups.map(group=>group.minute),[1420,1438,1439])
  assert(badges.length<=2);assert.equal(badges.flatMap(badge=>badge.items).length,3)
  for(let index=1;index<badges.length;index++)assert(badges[index].labelTop>=badges[index-1].labelTop+20)
  assert(Math.abs(badges.at(-1).labelTop+9-groups.at(-1).minute*896/840)<1e-9,'the late bar centres on 23:59 rather than pretending it is an earlier deadline')
  const dot=720,pixels=896/840,offset=domain.deadlineMomentLabelOffset(dot,[{timed:true,startMinutes:dot}],0,1440,pixels)
  assert(offset>=28,'only the clock label is displaced beyond the course-title band')
  for(const pixels of [896/840,900/840,1200/840]){
    const busy=domain.courseDeadlineMomentGroups(snapshot(Array.from({length:60},(_,index)=>task(`${index}`,`2026-10-07 23:${String(index).padStart(2,'0')}:00`))))
    const laidOut=domain.deadlineMomentBadges(busy,[{timed:true,startMinutes:1380}],0,1440,pixels)
    for(let index=1;index<laidOut.length;index++)assert(laidOut[index].labelTop>=laidOut[index-1].labelTop+20)
    assert.equal(laidOut.flatMap(badge=>badge.items).length,60)
    assert.deepEqual(busy.map(group=>group.minute),Array.from({length:60},(_,i)=>1380+i))
  }
})

test('point consumer retains exact position and source click state, grouping badges without fetching',()=>{
  const source=readFileSync(new URL('../src/CalendarDeadlineMarkers.jsx',import.meta.url),'utf8'),module={exports:{}}
  const dependencies={'react/jsx-runtime':runtime,'./course-domain.js':domain,'./ui-text.js':text}
  new Function('require','module','exports',transformSync(source,{loader:'jsx',jsx:'automatic',format:'cjs'}).code)(name=>dependencies[name],module,module.exports)
  const groups=domain.courseDeadlineMomentGroups(snapshot([task('a','2026-10-07 23:40:00'),task('b','2026-10-07 23:58:00'),task('c','2026-10-07 23:59:00')]))
  const opened=[],tree=module.exports.default({groups,start:0,end:1440,pixelsPerMinute:896/840,courses:[],language:'en',onOpen:value=>opened.push(value)})
  const nodes=node=>Array.isArray(node)?node.flatMap(nodes):React.isValidElement(node)?[node,...nodes(node.props.children)]:[]
  const points=nodes(tree).filter(node=>node.props.className==='time-deadline-marker'),badges=nodes(tree).filter(node=>node.props.className==='time-deadline-badge')
  assert.equal(points.length,3);assert(badges.length<=2)
  points.forEach((point,index)=>{assert.equal(point.props.style.top,`${groups[index].minute/1440*100}%`);assert(!Object.hasOwn(point.props.style,'height'))})
  let stops=0;points[2].props.onClick({stopPropagation:()=>stops++});badges[0].props.onClick({stopPropagation:()=>stops++})
  assert.equal(stops,2);assert.equal(opened[0].items[0].assignmentItem.id,'c');assert(opened[1].items.length>=1)
  assert.doesNotMatch(source,/fetch\(|command\(|refresh\(|duration\s*:/)
})

test('thin bars use the existing theme and red six-pixel indicators require explicit unsubmitted assignments',()=>{
  const source=readFileSync(new URL('../src/CalendarDeadlineMarkers.jsx',import.meta.url),'utf8'),css=readFileSync(new URL('../src/App.css',import.meta.url),'utf8'),module={exports:{}}
  const dependencies={'react/jsx-runtime':runtime,'./course-domain.js':domain,'./ui-text.js':text}
  new Function('require','module','exports',transformSync(source,{loader:'jsx',jsx:'automatic',format:'cjs'}).code)(name=>dependencies[name],module,module.exports)
  const nodes=node=>Array.isArray(node)?node.flatMap(nodes):React.isValidElement(node)?[node,...nodes(node.props.children)]:[]
  for(const [kind,status,pending] of [['assignment','未提交',true],['assignment','not submitted',true],['assignment','已提交',false],['assignment','submitted',false],['assignment','unknown',false],['quiz','未提交',false],['quiz','not submitted',false]]){
    const group={key:'fixture',date:'2026-10-07',minute:720,clock:'12:00',items:[{label:'Fixture',assignmentItem:{id:'fixture',kind,status}}]}
    const tree=module.exports.default({groups:[group],start:480,end:1440,pixelsPerMinute:896/840,courses:[],language:'en',onOpen:()=>{}})
    assert.equal(nodes(tree).filter(node=>node.props.className==='time-deadline-pending').length,pending?1:0,`${kind} ${status}`)
  }
  assert.match(css,/\.time-deadline-badge\s*\{[^}]*background: var\(--primary-fill\);[^}]*color: var\(--on-primary\);/s)
  assert.match(css,/\.time-deadline-pending\s*\{[^}]*height: 6px;[^}]*top: -3px;[^}]*width: 6px;/s)
})

test('actual shared day/week wiring preserves old all-day data and never routes QM point details through cloud refresh',()=>{
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8'),css=readFileSync(new URL('../src/App.css',import.meta.url),'utf8'),details=readFileSync(new URL('../src/CourseHub.jsx',import.meta.url),'utf8')
  assert.match(app,/courseDeadlineMomentGroups\(sharedCourseData\)/)
  assert.match(app,/visibleDeadlineMoments\.filter\(group=>group.date===dateString\)/)
  assert.match(app,/calendarView === 'day' \|\| calendarView === 'week'/)
  assert.match(app,/summary = summarizeMonthEntries\(allDayEntriesFor\(dateString\), 2\)/)
  assert.doesNotMatch(css,/\.time-all-day-cell > \.time-all-day-item\.assignment\s*\{/)
  assert.match(css,/grid-template-rows: auto calc\(896px \* var\(--deadline-timeline-scale, 1\)\)/)
  assert.match(css,/\.time-deadline-badge\s*\{[^}]*height: 18px;[^}]*left: 4px;[^}]*right: 4px;/s)
  assert.match(details,/source=item\.source==='qmplus'\?'qmplus':'ucloud'/)
  assert.match(details,/onRefresh=\{source==='ucloud'\?refresh:undefined\}/)
})
