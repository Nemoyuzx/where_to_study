import assert from 'node:assert/strict'
import test from 'node:test'
import {CourseDataOwner} from '../src/course-data-owner.js'

const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no});return {promise,resolve,reject}}
const flush=async()=>{for(let index=0;index<6;index++)await Promise.resolve()}
const snapshot=id=>({courses:[{id,name:`Fixture ${id}`}],assignments:[{id:`task-${id}`,course_id:id,title:'Fixture task',deadline:'2026-10-06 12:00:00'}],fetched_at:'2026-10-05T00:00:00Z',cache_warning:false})
function fixture(options) {
  const calls=[]
  const owner=new CourseDataOwner((name,payload)=>{const call={name,payload,...deferred()};calls.push(call);return call.promise},options)
  return {owner,calls,configure:(key='a',qm=false)=>owner.configure({cloudKey:key,cloudEnabled:true,qmKey:key,qmEnabled:qm})}
}

test('cache appears before a shared silent refresh; calendar and detail refresh join the same owner',async()=>{
  const f=fixture();f.configure()
  assert.equal(f.calls.length,1);assert.equal(f.calls[0].payload.cache_only,true)
  f.calls[0].resolve(snapshot('a'));await flush()
  assert.equal(f.owner.state.courses[0].id,'a')
  assert.equal(f.calls.length,2);assert.equal(f.calls[1].payload.force,true)
  const first=f.owner.refresh(true),second=f.owner.refresh(true)
  assert.equal(first,second);assert.equal(f.calls.length,2)
  const calendar=await f.owner.assignmentsForDates('2026-10-06')
  assert.equal(calendar.items.length,1);assert.equal(f.calls.length,2)
  f.calls[1].reject(new Error('fixture unavailable'));await assert.rejects(first);await flush()
  assert.equal(f.owner.state.courses[0].id,'a');assert.equal(f.owner.state.fetchedAt,'2026-10-05T00:00:00Z')
  assert.equal(f.owner.state.cloudBusy,false)
})

test('late hydration cannot publish or start work for a newer account owner',async()=>{
  const f=fixture();f.configure('a');const old=f.calls[0]
  const pending=f.owner.assignmentsForDates('2026-10-06')
  f.configure('b');const current=f.calls[1]
  old.resolve(snapshot('a'));await assert.rejects(pending);await flush()
  assert.equal(f.calls.length,2);assert.equal(f.owner.state.courses,null)
  current.resolve(snapshot('b'));await flush()
  assert.equal(f.owner.state.courses[0].id,'b');assert.equal(f.calls.length,3)
  f.calls[2].resolve(snapshot('b'));await flush()
})

test('Feature Off hides QM and ignores late callbacks without issuing a logout or secret request',async()=>{
  const f=fixture();f.configure('a',true)
  const read=f.calls.find(call=>call.name==='load_qmplus')
  f.owner.configure({cloudKey:'a',cloudEnabled:true,qmKey:'a',qmEnabled:false})
  read.resolve({courses:[{id:'qm-fixture'}]});await flush()
  assert.equal(f.owner.state.qm,null)
  assert.equal(f.calls.some(call=>['disconnect_qmplus','clear_qmplus_login','connect_qmplus'].includes(call.name)),false)
  assert.equal(f.calls.some(call=>call.payload&&('password' in call.payload||'account' in call.payload)),false)
  f.calls[0].resolve(snapshot('a'));await flush();f.calls.at(-1).resolve(snapshot('a'));await flush()
})

test('clear disables both domains before old hydration can restart either connection',async()=>{
  const f=fixture();f.configure('a',true);f.owner.clear()
  for(const call of f.calls)call.resolve(call.name==='load_qmplus'?{courses:[]}:snapshot('a'))
  await flush()
  assert.equal(f.calls.length,2);assert.equal(f.owner.state.courses,null);assert.equal(f.owner.state.qm,null)
  assert.equal(f.owner.cloudEnabled,false);assert.equal(f.owner.qmEnabled,false)
})

test('shared refresh consumes native new IDs once; edits and repeated reads cannot reopen dismissed alerts',async()=>{
  const f=fixture();f.configure();f.calls[0].resolve({...snapshot('a'),new_assignment_ids:[]});await flush()
  const first=f.owner.refresh(true),second=f.owner.refresh(true)
  assert.equal(first,second)
  f.calls[1].resolve({...snapshot('b'),new_assignment_ids:['task-b']});await first
  assert.equal(f.owner.state.newAssignments.length,1)
  f.owner.dismissNewAssignments()
  const next=f.owner.refresh(true);f.calls[2].resolve({...snapshot('b'),new_assignment_ids:['task-b']});await next
  assert.equal(f.owner.state.newAssignments.length,0)
  const late=f.owner.refresh(true);f.owner.clear();f.calls[3].resolve({...snapshot('c'),new_assignment_ids:['task-c']});await late
  assert.equal(f.owner.state.newAssignments.length,0)
})

test('QM changed during an existing read queues one local reread and consumes complete results once',async()=>{
  const f=fixture();f.configure('a',true)
  const first=f.calls.find(call=>call.name==='load_qmplus')
  f.owner.reloadQM(true);f.owner.reloadQM(true)
  first.resolve(null);await flush()
  const reads=f.calls.filter(call=>call.name==='load_qmplus')
  assert.equal(reads.length,2)
  const qm={ok:true,partial:false,fetched_at:'2026-10-06T10:00:00Z',courses:[{id:'course',name:'EBU Course',current_term_status:'current'}],activities:[{id:'task',course_id:'course',kind:'assignment',title:'New task',due_at:'2026-10-07T12:00:00Z'}],new_assignment_ids:['course:assignment:task']}
  reads[1].resolve(qm);await flush()
  assert.equal(f.owner.state.newAssignments.length,1)
  f.owner.dismissNewAssignments()
  const repeat=f.owner.reloadQM();f.calls.filter(call=>call.name==='load_qmplus').at(-1).resolve(qm);await repeat
  assert.equal(f.owner.state.newAssignments.length,0)
  const stale=f.owner.reloadQM();f.owner.configure({cloudKey:'a',cloudEnabled:true,qmKey:'new',qmEnabled:true})
  f.calls.filter(call=>call.name==='load_qmplus').at(-2).resolve({...qm,new_assignment_ids:['course:late']});await stale
  assert.equal(f.owner.state.newAssignments.length,0)
  f.owner.clear()
  for(const call of f.calls)call.resolve(null)
  await flush()
})

test('QM notices include assignments and quizzes only from current EBU courses, excluding admin mark review',()=>{
  const {owner}=fixture()
  const activities=[
    {id:'assign',course_id:'ebu',kind:'assignment',title:'Coursework'},
    {id:'quiz',course_id:'ebu',kind:'quiz',title:'Quiz',closes_at:'2026-10-08T12:00:00Z'},
    {id:'review',course_id:'ebu',kind:'assignment',title:'Coursework Mark Review Request'},
    {id:'other',course_id:'other',kind:'quiz',title:'Other course'},
  ]
  owner.acceptNewAssignments('qmplus',{fetched_at:'2026-10-06T10:00:00Z',courses:[{id:'ebu',name:'EBU Fixture',current_term_status:'current'},{id:'other',name:'Other fixture',current_term_status:'current'}],activities,
    new_assignment_ids:activities.map(item=>`${item.course_id}:${item.kind}:${item.id}`)})
  assert.deepEqual(owner.state.newAssignments.map(item=>item.id),['assign','quiz'])
  assert.equal(owner.state.newAssignments[1].deadline,'2026-10-08T12:00:00Z')
})

test('calendar-first cache restoration is quiet; explicit date and range refresh join one flight and alert once',async()=>{
  const f=fixture();f.configure()
  const firstDate=f.owner.assignmentsForDates('2026-10-06')
  f.calls[0].resolve(snapshot('baseline'))
  assert.equal((await firstDate).items[0].id,'task-baseline')
  assert.equal(f.owner.state.newAssignments.length,0)
  assert.equal(f.calls.length,2,'cache hydration starts only its existing owner refresh')
  f.calls[1].resolve(snapshot('baseline'));await flush()
  const local=await f.owner.assignmentsForDates('2026-10-06','2026-10-20')
  assert.equal(local.items.length,1);assert.equal(f.calls.length,2,'ordinary date/range reads use the cached catalogue')
  const forcedDate=f.owner.assignmentsForDates('2026-10-06','2026-10-06',{force:true})
  const forcedRange=f.owner.assignmentsForDates('2026-10-01','2026-10-31',{force:true})
  const detail=f.owner.refresh(true)
  await flush()
  assert.equal(f.calls.length,3,'date, whole-month and course-detail force calls share one network command')
  assert.deepEqual(f.calls[2].payload,{catalogue:true,cache_only:false,force:true})
  f.calls[2].resolve(snapshot('new'))
  const [date,range]=await Promise.all([forcedDate,forcedRange,detail])
  assert.equal(date.items[0].id,'task-new');assert.equal(range.items[0].id,'task-new')
  assert.deepEqual(f.owner.state.newAssignments.map(item=>item.id),['task-new'])
  assert.equal(f.calls.filter(call=>call.payload?.cache_only===false).length,2,'one startup fetch plus one explicit shared force')
})

test('forced calendar result from a retired source cannot alert, replace cache or contaminate the new source baseline',async()=>{
  const f=fixture();f.configure('old')
  f.calls[0].resolve(snapshot('old'));await flush();f.calls[1].resolve(snapshot('old'));await flush()
  const stale=f.owner.assignmentsForDates('2026-10-06','2026-10-06',{force:true});await flush()
  assert.equal(f.calls.length,3)
  f.configure('new')
  f.calls[2].resolve(snapshot('late'))
  await assert.rejects(stale,/账户已更改/)
  assert.equal(f.owner.state.assignments,null);assert.equal(f.owner.state.newAssignments.length,0)
  f.calls[3].resolve(snapshot('late'));await flush()
  assert.equal(f.owner.state.newAssignments.length,0,'restoring the new owner establishes its own silent baseline')
  f.calls[4].resolve(snapshot('late'));await flush()
  assert.equal(f.owner.state.assignments[0].id,'task-late')
  assert.equal(f.owner.state.newAssignments.length,0)
})

test('cold calendar force and startup refresh share the first complete baseline without historical alerts',async()=>{
  const f=fixture();f.configure()
  const first=f.owner.assignmentsForDates('2026-10-06','2026-10-06',{force:true})
  const second=f.owner.assignmentsForDates('2026-10-01','2026-10-31',{force:true})
  f.calls[0].resolve(null);await flush()
  assert.equal(f.calls.length,2,'both calendar forces join the startup network owner after one cache read')
  assert.equal(f.calls[1].payload.force,true)
  f.calls[1].resolve(snapshot('initial'))
  const results=await Promise.all([first,second])
  assert.equal(results[0].items[0].id,'task-initial');assert.equal(results[1].items[0].id,'task-initial')
  assert.equal(f.owner.state.newAssignments.length,0,'the first complete result is a silent baseline')
  assert.equal(f.calls.filter(call=>call.payload?.cache_only===false).length,1)
})

test('preview truncation cannot lose unconfirmed counts; replacing one source clears only that source',()=>{
  const f=fixture();f.configure('account',true)
  const cloudItems=Array.from({length:17},(_,index)=>({...snapshot(`cloud-${index}`).assignments[0]}))
  f.owner.acceptNewAssignments('ucloud',{fetched_at:'2026-10-06T10:00:00Z',courses:[],assignments:cloudItems,new_assignment_ids:cloudItems.map(item=>item.id)})
  const qmItems=Array.from({length:2},(_,index)=>({id:`qm-${index}`,course_id:'ebu',kind:'quiz',title:`Quiz ${index}`}))
  f.owner.acceptNewAssignments('qmplus',{fetched_at:'2026-10-06T10:00:00Z',courses:[{id:'ebu',name:'EBU Fixture',current_term_status:'current'}],activities:qmItems,new_assignment_ids:qmItems.map(item=>`ebu:quiz:${item.id}`)})
  assert.equal(f.owner.state.newAssignmentCount,19)
  assert.equal(f.owner.state.newAssignments.length,8)
  assert.equal(f.owner.state.newAssignmentCount-f.owner.state.newAssignments.length,11)
  f.owner.configure({cloudKey:'replacement',cloudEnabled:true,qmKey:'account',qmEnabled:true})
  assert.deepEqual(f.owner.state.newAssignments.map(item=>item.id),['qm-0','qm-1'])
  assert.deepEqual(f.owner.state.newAssignmentCounts,{ucloud:0,qmplus:2})
  assert.equal([...f.owner.notified].some(key=>key.startsWith('ucloud:')),false)
  f.owner.clear()
  assert.equal(f.owner.state.newAssignments.length,0);assert.equal(f.owner.state.newAssignmentCount,0);assert.equal(f.owner.notified.size,0)
})

test('1000 publications keep eight previews and current directory replay keys while retaining every unconfirmed count',()=>{
  const {owner}=fixture({nativeNotices:true})
  for(let index=0;index<1000;index++){
    const value={...snapshot(`${index}`),fetched_at:new Date(Date.UTC(2026,9,6,0,0,index)).toISOString(),new_assignment_ids:[`task-${index}`]}
    owner.acceptNewAssignments('ucloud',value)
    owner.acceptNewAssignments('ucloud',value)
    assert(owner.state.newAssignments.length<=8)
    assert(owner.noticeSummaries.ucloud.preview.length<=8)
    assert.equal(owner.notified.size,1,'only the current catalogue identity can still be replayed')
    assert.equal(owner.state.newAssignmentCount,index+1,'duplicate metadata never doubles the count')
  }
  assert.equal(owner.state.newAssignmentCount,1000)
  assert.deepEqual(owner.state.newAssignments.map(item=>item.id),Array.from({length:8},(_,i)=>`task-${i}`))
  owner.dismissNewAssignments()
  assert.equal(owner.state.newAssignmentCount,0);assert.equal(owner.state.newAssignments.length,0)
})

test('native replay stamps prevent old cached DTO replays after notified pruning and deletion/reappearance',()=>{
  const {owner}=fixture({nativeNotices:true})
  const first={...snapshot('a'),fetched_at:'2026-10-06T10:00:00.000000001Z',new_assignment_ids:['task-a']}
  const second={...snapshot('b'),fetched_at:'2026-10-06T10:00:00.000000002Z',new_assignment_ids:['task-b']}
  owner.acceptNewAssignments('ucloud',first);owner.acceptNewAssignments('ucloud',second)
  assert.equal(owner.state.newAssignmentCount,2,'nanosecond-different native fetches remain distinct')
  assert.deepEqual([...owner.notified],['ucloud:task-b'])
  owner.acceptNewAssignments('ucloud',first)
  assert.equal(owner.state.newAssignmentCount,2);assert.deepEqual([...owner.notified],['ucloud:task-b'])
  // Native serde omits empty fresh-ID lists. This is an authoritative empty
  // notice result, never permission to fall back to browser discovery.
  owner.acceptNewAssignments('ucloud',{courses:[],assignments:[],fetched_at:'2026-10-06T10:00:00.000000003Z'})
  assert.equal(owner.notified.size,0)
  owner.acceptNewAssignments('ucloud',second)
  owner.acceptNewAssignments('ucloud',{...snapshot('b'),fetched_at:'2026-10-06T10:00:00.000000004Z'})
  assert.equal(owner.state.newAssignmentCount,2,'persistent native seen IDs suppress deleted tasks when they return')
  owner.dismissNewAssignments();owner.acceptNewAssignments('ucloud',second)
  assert.equal(owner.state.newAssignmentCount,0)
})

test('browser persistent seen IDs survive directory-key pruning and cached publication replay',()=>{
  const {owner}=fixture()
  owner.acceptNewAssignments('ucloud',snapshot('base'),true)
  owner.acceptNewAssignments('ucloud',snapshot('new'))
  assert.equal(owner.state.newAssignmentCount,1)
  owner.acceptNewAssignments('ucloud',{...snapshot('empty'),assignments:[]})
  assert.equal(owner.notified.size,0)
  owner.acceptNewAssignments('ucloud',snapshot('new'))
  assert.equal(owner.state.newAssignmentCount,1)
})

test('cached native restore, partial and malformed metadata cannot alert or disturb source pending counts',()=>{
  const {owner}=fixture({nativeNotices:true})
  owner.acceptNewAssignments('ucloud',{...snapshot('cache'),new_assignment_ids:['task-cache']},true)
  owner.acceptNewAssignments('ucloud',{...snapshot('cache'),new_assignment_ids:['task-cache']})
  assert.equal(owner.state.newAssignmentCount,0)
  owner.acceptNewAssignments('ucloud',{...snapshot('fresh'),fetched_at:'2026-10-06T10:00:00Z',new_assignment_ids:['task-fresh']})
  const before=[...owner.notified]
  owner.acceptNewAssignments('ucloud',{...snapshot('partial'),fetched_at:'2026-10-07T10:00:00Z',partial:true,new_assignment_ids:['task-partial']})
  owner.acceptNewAssignments('ucloud',{...snapshot('invalid'),fetched_at:'unknown',new_assignment_ids:['task-invalid']})
  assert.equal(owner.state.newAssignmentCount,1);assert.deepEqual([...owner.notified],before)
})
