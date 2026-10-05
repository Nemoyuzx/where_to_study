import assert from 'node:assert/strict'
import test from 'node:test'
import {CourseDataOwner} from '../src/course-data-owner.js'

const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no});return {promise,resolve,reject}}
const flush=async()=>{for(let index=0;index<6;index++)await Promise.resolve()}
const snapshot=id=>({courses:[{id,name:`Fixture ${id}`}],assignments:[{id:`task-${id}`,course_id:id,title:'Fixture task',deadline:'2026-10-06 12:00:00'}],fetched_at:'2026-10-05T00:00:00Z',cache_warning:false})
function fixture() {
  const calls=[]
  const owner=new CourseDataOwner((name,payload)=>{const call={name,payload,...deferred()};calls.push(call);return call.promise})
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
