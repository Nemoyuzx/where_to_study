import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const script = fs.readFileSync(new URL('../contracts/qmplus/qmplus-sync.js', import.meta.url), 'utf8')
function page(extras={}) {
  const context = vm.createContext({URL,URLSearchParams,TextEncoder,TextDecoder,Intl,Date,AbortController,setTimeout,clearTimeout,
    location:{origin:'https://qmplus.qmul.ac.uk'},document:{body:{classList:{contains:()=>false}}},M:{cfg:{sesskey:'synthetic-session-only'}},...extras})
  vm.runInContext(script,context)
  return context
}
function response(data, extras={}, raw=false) {
  const bytes=new TextEncoder().encode(raw?data:JSON.stringify([{data}]))
  let delivered=false
  return {ok:true,headers:{get:()=>null},body:{getReader:()=>({read:async()=>{if(delivered)return {done:true};delivered=true;return {value:bytes,done:false}},releaseLock(){},cancel:async()=>{}}),cancel:async()=>{}},...extras}
}
test('QM dates use London daylight saving, reject gaps and ambiguous folds',()=>{
  const p=page().WTSQmProtocol
  assert.equal(p.londonDate('Friday, 5 December 2025, 10:00 AM'),'2025-12-05T10:00:00.000Z')
  assert.equal(p.londonDate('Wednesday, 30 September 2026, 4:59 PM'),'2026-09-30T15:59:00.000Z')
  assert.equal(p.londonDate('Sunday, 29 March 2026, 1:30 AM'),null)
  assert.equal(p.londonDate('Sunday, 25 October 2026, 1:30 AM'),null)
  assert.equal(p.londonDate('31 February 2026, 12:00 PM'),null)
  assert.equal(p.londonDate('5 December 2025, 25:00 AM'),null)
  assert.equal(p.londonDate('5 December 2025, 0:00 PM'),null)
})
test('QM current term does not call historical or unclassified courses current',()=>{
  const p=page().WTSQmProtocol, now=Date.parse('2026-10-03T10:00:00Z')
  assert.equal(p.currentTermStatus({fullname:'Fixture Course - 2026/27'},now),'current')
  assert.equal(p.currentTermStatus({fullname:'Fixture Course - 2025/26',enddate:2000000000},now),'other')
  assert.equal(p.currentTermStatus({fullname:'General information',startdate:1300000000},now),'unknown')
  assert.equal(p.currentTermStatus({fullname:'Future Course - 2026/27',startdate:1900000000},now),'other')
  assert.equal(p.currentTermStatus({fullname:'Fixture Course - 2026/27',hidden:true},now),'current')
})
test('QM Quiz Closed dates and abbreviated limits retain separate opening and closing instants',()=>{
  const p=page().WTSQmProtocol
  const timings=p.timingTexts(['Opened: Monday, 7 September 2026, 10:00 AM Closed: Monday, 7 September 2026, 11:00 AM','Time limit: 25 mins'])
  assert.equal(timings.opens_at,'2026-09-07T09:00:00.000Z')
  assert.equal(timings.closes_at,'2026-09-07T10:00:00.000Z')
  assert.equal(timings.time_limit_seconds,1500)
  assert.equal(timings.due_at,null)
  assert.equal(p.timingTexts(['This quiz closed on Friday, 5 December 2025, 10:00 AM','Time limit: 2 hrs']).closes_at,'2025-12-05T10:00:00.000Z')
  assert.equal(p.timingTexts(['Time limit: 2 hrs']).time_limit_seconds,7200)
  assert.equal(p.timingTexts(['Time limit: 45 secs']).time_limit_seconds,45)
  assert.equal(p.timingTexts(['This quiz is not yet available']).closes_at,null)
  const prose=p.timingTexts(['This quiz opened on Friday, 5 December 2025, 10:00 AM This quiz will close on Friday, 5 December 2025, 11:00 AM'])
  assert.equal(prose.opens_at,'2025-12-05T10:00:00.000Z')
  assert.equal(prose.closes_at,'2025-12-05T11:00:00.000Z')
})
test('QM Assignment due, cutoff and extension dates are not confused with a Quiz window',()=>{
  const values=page().WTSQmProtocol.timingTexts(['Due: Friday, 5 December 2025, 10:00 AM','Cut-off date: Friday, 5 December 2025, 11:00 AM','Extension due date: Friday, 5 December 2025, 10:30 AM'])
  assert.equal(values.due_at,'2025-12-05T10:30:00.000Z')
  assert.equal(values.cutoff_at,'2025-12-05T11:00:00.000Z')
  assert.equal(values.closes_at,null)
})
test('QM URL projections strip session query strings and reject other hosts',()=>{
  const p=page().WTSQmProtocol
  assert.equal(p.safeURL('/mod/quiz/view.php?id=12&sesskey=secret'),'https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=12')
  assert.equal(p.safeURL('https://qmplus.qmul.ac.uk.evil.test/mod/quiz/view.php?id=12'),null)
  assert.equal(p.safeURL('https://other.test/course/view.php?id=12'),null)
  assert.equal(p.safeURL('/mod/quiz/startattempt.php?id=12'),null)
  assert.equal(p.safeURL('/course/view.php?id=9999999999999999'),null)
})
test('QM foreign/anonymous origin cannot synchronize or expose session material',async()=>{
  const foreign=await page({location:{origin:'https://login.microsoftonline.com'}}).WTSQmSync()
  assert.equal(foreign.error_code,'QM_ORIGIN_REQUIRED')
  const anonymous=await page({M:{cfg:{}}}).WTSQmSync()
  assert.equal(anonymous.error_code,'QM_LOGIN_REQUIRED')
  assert.doesNotMatch(JSON.stringify(anonymous),/sesskey|cookie|synthetic-session/)
})
test('QM catalogue AJAX remains read-only, bounded and discovers no private identity fields',async()=>{
  const requests=[]
  const ctx=page({fetch:async(url,options)=>{
    requests.push({url,options})
    const method=JSON.parse(options.body)[0].methodname
    const data=method.includes('enrolled_courses')?{courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27',userid:123,password:'not-exported'}],nextoffset:0}
      :method==='core_courseformat_get_state'?JSON.stringify({cm:{15:{id:15,module:'quiz',name:'Fixture quiz',uservisible:false}}}):{weeks:[]}
    const bytes=new TextEncoder().encode(JSON.stringify([{data}]))
    let delivered=false
    return {ok:true,headers:{get:()=>null},body:{getReader:()=>({read:async()=>{if(delivered)return {done:true}; delivered=true;return {value:bytes,done:false}},releaseLock(){},cancel:async()=>{}})}}
  }})
  const snapshot=await ctx.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
  assert.equal(snapshot.ok,true)
  assert.equal(snapshot.courses.length,1)
  assert.equal(snapshot.activities[0].detail_status,'restricted')
  assert.equal(requests.length,2)
  assert.ok(requests.every(r=>r.options.method==='POST'&&new URL(r.url).pathname==='/lib/ajax/service.php'))
  assert.doesNotMatch(JSON.stringify(snapshot),/sesskey|cookie|password|userid|synthetic-session|not-exported/)
  assert.equal(ctx.__wtsQmFlight,undefined)
  assert.doesNotMatch(script,/startattempt\.php|submit\.php|document\.cookie|console\.(log|info)/)
  assert.match(script,/120000/)
  assert.match(script,/512 \* 1024/)
  assert.match(script,/core_courseformat_get_state/)
  assert.doesNotMatch(script,/core_calendar_|\/calendar\//)
})
test('QM malformed module catalogue is partial, never an authoritative empty replacement',async()=>{
  const calls=[]
  const ctx=page({fetch:async(url,options)=>{
    const method=JSON.parse(options.body)[0].methodname; calls.push(method)
    return response(method.includes('enrolled_courses')?{courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'}],nextoffset:0}:JSON.stringify({}))
  }})
  const snapshot=await ctx.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
  assert.equal(snapshot.ok,true)
  assert.equal(snapshot.partial,true)
  assert.ok(snapshot.warnings.includes('QM_MODULE_PARTIAL'))
  assert.equal(snapshot.courses.length,1)
  assert.equal(calls.length,2)
})
test('QM details directly provide completed assignments and Quiz windows without any calendar call',async()=>{
  const calls=[]
  class DetailDOMParser {
    parseFromString(html) {
      const quiz=html==='synthetic-quiz'
      const paragraphs=quiz?['Opened: Friday, 9 October 2026, 10:00 AM','Closed: Friday, 9 October 2026, 11:00 AM','Time limit: 25 mins','Grade to pass: 2']:[]
      const element={textContent:quiz?paragraphs.join(''):'Due: Friday, 9 October 2026, 12:00 PM',matches:()=>quiz,querySelectorAll:()=>paragraphs.map(textContent=>({textContent}))}
      const row={querySelectorAll:()=>[{textContent:'Submission status'},{textContent:'Submitted for grading'}]}
      const region={querySelectorAll:selector=>selector.includes('submissionstatustable')?(quiz?[]:[row]):[element]}
      return {querySelector:selector=>selector==='#region-main'?region:null}
    }
  }
  const ctx=page({DOMParser:DetailDOMParser,fetch:async(url,options)=>{
    calls.push({url,options})
    if(options.method==='GET')return response(url.includes('/quiz/')?'synthetic-quiz':'synthetic-assignment',{},true)
    const method=JSON.parse(options.body)[0].methodname
    if(method.includes('enrolled_courses'))return response({courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'},{id:99,fullname:'General Training - 2026/27'}],nextoffset:0})
    assert.equal(method,'core_courseformat_get_state')
    assert.equal(JSON.parse(options.body)[0].args.courseid,12)
    return response(JSON.stringify({cm:[{id:15,module:'quiz',name:'Quiz fixture'},{id:16,module:'assign',name:'Submitted assignment fixture'}]}))
  }})
  const snapshot=await ctx.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
  assert.equal(snapshot.partial,false,JSON.stringify(snapshot.warnings))
  assert.equal(snapshot.courses.length,1)
  assert.equal(snapshot.courses[0].id,'12')
  assert.ok(snapshot.activities.every(a=>a.course_id==='12'))
  const [quiz,assignment]=snapshot.activities
  assert.equal(quiz.opens_at,'2026-10-09T09:00:00.000Z')
  assert.equal(quiz.closes_at,'2026-10-09T10:00:00.000Z')
  assert.equal(quiz.time_limit_seconds,1500)
  assert.equal(assignment.status,'Submitted for grading')
  assert.equal(assignment.due_at,'2026-10-09T11:00:00.000Z')
  assert.equal(calls.length,4)
  assert.equal(calls.filter(c=>c.options.method==='GET').length,2)
  assert.ok(calls.every(c=>!new URL(c.url).pathname.includes('calendar')))
  assert.ok(calls.filter(c=>c.options.method==='POST').every(c=>['core_course_get_enrolled_courses_by_timeline_classification','core_courseformat_get_state'].includes(JSON.parse(c.options.body)[0].methodname)))
})
test('QM rejected response aborts transfer and cancels its body before releasing the flight',async()=>{
  let aborted=false,cancelled=false
  const ctx=page({fetch:async(url,options)=>{
    options.signal.addEventListener('abort',()=>{aborted=true})
    return response(null,{headers:{get:()=>String(4*1024*1024+1)},body:{cancel:async()=>{cancelled=true}}})
  }})
  const snapshot=await ctx.WTSQmSync()
  assert.equal(snapshot.error_code,'QM_RESPONSE_TOO_LARGE')
  assert.equal(aborted,true); assert.equal(cancelled,true)
  assert.equal(ctx.__wtsQmFlight,undefined)
})
test('QM large snapshots stay within 512 KiB without linear reencoding or split emoji',async()=>{
  let passes=0
  class CountingEncoder extends TextEncoder {encode(value){passes++;return super.encode(value)}}
  const ctx=page({TextEncoder:CountingEncoder,fetch:async(url,options)=>{
    const method=JSON.parse(options.body)[0].methodname
    return response(method.includes('enrolled_courses')?{courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'}],nextoffset:0}
      :JSON.stringify({cm:Array.from({length:500},(_,i)=>({id:100+i,module:'quiz',name:'汉'.repeat(511)+'😀',uservisible:false}))}))
  }})
  const snapshot=await ctx.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
  assert.equal(snapshot.ok,true);assert.equal(snapshot.partial,true)
  assert.ok(snapshot.warnings.includes('QM_SNAPSHOT_LIMIT'))
  assert.ok(snapshot.activities.length>0&&snapshot.activities.length<500)
  assert.ok(new TextEncoder().encode(JSON.stringify(snapshot)).byteLength<=512*1024)
  assert.ok(passes<20,`Unexpected repeated allocations: ${passes}`)
  assert.ok(snapshot.activities.every(item=>!/[\uD800-\uDBFF]$/.test(item.title)))
})
test('all shells bundle the same read-only QM protocol instead of frozen assessment data',()=>{
  assert.equal(fs.readFileSync(new URL('../native/harmony/entry/src/main/resources/rawfile/qmplus-sync.js',import.meta.url),'utf8'),script)
  assert.match(fs.readFileSync(new URL('../native/apple/project.yml',import.meta.url),'utf8'),/contracts\/qmplus\/qmplus-sync\.js/)
  assert.match(fs.readFileSync(new URL('../native/android/app/build.gradle.kts',import.meta.url),'utf8'),/contracts\/qmplus/)
  assert.match(fs.readFileSync(new URL('../src-tauri/src/qmplus.rs',import.meta.url),'utf8'),/contracts\/qmplus\/qmplus-sync\.js/)
})
