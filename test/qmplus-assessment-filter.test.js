import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'
import {isQmplusAssessmentActivity, qmplusActivitiesForCourse, submissionCounts} from '../src/course-domain.js'

const script=fs.readFileSync(new URL('../contracts/qmplus/qmplus-sync.js',import.meta.url),'utf8')
function page(extras={}) {
  const document={readyState:'complete',body:{classList:{contains:()=>false}},querySelector:()=>null,
    querySelectorAll:selector=>selector==='.usermenu .userbutton'?[{}]:[]}
  const context=vm.createContext({URL,URLSearchParams,TextEncoder,TextDecoder,Intl,Date,AbortController,setTimeout,clearTimeout,
    location:{origin:'https://qmplus.qmul.ac.uk'},document,
    M:{cfg:{sesskey:'synthetic-session-only'}},...extras})
  vm.runInContext(script,context)
  return context
}
function response(data,raw=false) {
  const bytes=new TextEncoder().encode(raw?data:JSON.stringify([{data}]))
  let delivered=false
  return {ok:true,headers:{get:()=>null},body:{getReader:()=>({read:async()=>{
    if(delivered)return {done:true};delivered=true;return {value:bytes,done:false}
  },releaseLock(){},cancel:async()=>{}}),cancel:async()=>{}}}
}

test('QM administrative filter has identical conservative fetch and cached-display policies',()=>{
  const predicate=page().WTSQmProtocol.includesAssessmentActivity
  const excluded=['COURSEWORK MARK REVIEW REQUEST','  coursework\tmark\u00A0review request  ',
    'ＣＯＵＲＳＥＷＯＲＫ　ＭＡＲＫ　ＲＥＶＩＥＷ　ＲＥＱＵＥＳＴ',
    'COURSEWORK-MARK/REVIEW:REQUEST', 'COURSEWORK\u2011MARK\u2212REVIEW\u2014REQUEST FORM',
    '\uFEFFCoursework\u0085Mark\u202FReview\u205FRequest\uFEFF']
  const retained=['Coursework 1','Coursework mark review essay','Peer review assignment',
    'COURSEWORK MARK REVIEW REQUEST analysis','COURSEWORK MARK REVIEW REQUEST?',
    '(COURSEWORK MARK REVIEW REQUEST)','COURSEWORK|MARK REVIEW REQUEST','ℂOURSEWORK MARK REVIEW REQUEST']
  for(const title of [...excluded,...retained]) {
    const expected=!excluded.includes(title)
    assert.equal(predicate('assignment',title),expected,title)
    assert.equal(isQmplusAssessmentActivity({kind:'assignment',title,due_at:null}),expected,title)
    assert.equal(predicate('quiz',title),true,title)
    assert.equal(isQmplusAssessmentActivity({kind:'quiz',title}),true,title)
  }
})

test('old QM cache details and count inputs exclude review requests but keep actual undated work',()=>{
  const course={id:'1',name:'EBU1000 - Fixture',current_term_status:'current'}
  const cached={activities:[
    {id:'1',course_id:'1',kind:'assignment',title:'COURSEWORK MARK REVIEW REQUEST',due_at:null,status:'No submissions have been made yet'},
    {id:'2',course_id:'1',kind:'assignment',title:'Coursework 1',due_at:null,status:'Nothing submitted'},
    {id:'3',course_id:'1',kind:'assignment',title:'Peer review essay',due_at:null,status:'Submitted'},
    {id:'4',course_id:'1',kind:'quiz',title:'COURSEWORK MARK REVIEW REQUEST',due_at:null,status:'Submitted'},
    {id:'5',course_id:'other',kind:'assignment',title:'Coursework 2',status:'Nothing submitted'}]}
  const visible=qmplusActivitiesForCourse(cached,course)
  assert.deepEqual(visible.map(i=>i.id),['2','3','4'])
  assert.deepEqual(submissionCounts(visible),{pending:1,submitted:1})
  assert.equal(cached.activities.length,5,'Display must not rewrite old source evidence')
  assert.deepEqual(qmplusActivitiesForCourse(cached,{...course,current_term_status:'other'}),[])
})

test('QM catalogue excludes administrative forms before fetching details; undated assignments and Quiz survive',async()=>{
  const calls=[]
  class DetailDOMParser {
    parseFromString() {
      const row={querySelectorAll:()=>[{textContent:'Submission status'},{textContent:'No submissions have been made yet'}]}
      const region={querySelectorAll:selector=>selector.includes('submissionstatustable')?[row]:[]}
      return {querySelector:selector=>selector==='#region-main'?region:null}
    }
  }
  const ctx=page({DOMParser:DetailDOMParser,fetch:async(url,options)=>{
    calls.push({url,method:options.method})
    if(options.method==='GET')return response('synthetic detail without dates',true)
    const method=JSON.parse(options.body)[0].methodname
    if(method.includes('enrolled_courses'))return response({courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'}],nextoffset:0})
    return response(JSON.stringify({cm:[{id:15,module:'assign',name:'COURSEWORK MARK REVIEW REQUEST'},
      {id:16,module:'assign',name:'Coursework 1'},{id:17,module:'quiz',name:'COURSEWORK MARK REVIEW REQUEST'},
      {id:18,module:'assign',name:'Peer review essay'}]}))
  }})
  const snapshot=await ctx.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
  assert.equal(snapshot.ok,true)
  assert.equal(snapshot.partial,false)
  assert.deepEqual(Array.from(snapshot.activities,a=>a.id),['16','17','18'])
  assert.ok(snapshot.activities.every(a=>a.due_at===null))
  assert.ok(!calls.some(c=>c.url.endsWith('/mod/assign/view.php?id=15')))
  assert.equal(calls.filter(c=>c.method==='GET').length,3)
  assert.equal(ctx.__wtsQmFlight,undefined)
})

test('ignored administrative modules cannot consume the 500-assessment budget or create partial warnings',async()=>{
  const ctx=page({fetch:async(url,options)=>{
    const method=JSON.parse(options.body)[0].methodname
    if(method.includes('enrolled_courses'))return response({courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'}],nextoffset:0})
    return response(JSON.stringify({cm:[...Array.from({length:500},(_,i)=>({id:100+i,module:'assign',name:`Coursework ${i}`,uservisible:false})),
      {id:600,module:'assign',name:'COURSEWORK MARK REVIEW REQUEST'}]}))
  }})
  const snapshot=await ctx.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
  assert.equal(snapshot.ok,true)
  assert.equal(snapshot.activities.length,500)
  assert.equal(snapshot.partial,false)
  assert.equal(snapshot.warnings.length,0)
})
