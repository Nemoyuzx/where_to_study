import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import vm from 'node:vm'

const read=name=>readFileSync(new URL(`../contracts/qmplus/${name}`,import.meta.url),'utf8')
const pageScript=read('qmplus-page.js'),syncScript=read('qmplus-sync.js'),authScript=read('qmplus-auth.js')
const fatalSelector='[data-rel="fatalerror"], #region-main .errorbox .errorcode, main .errorbox .errorcode'
const titleSelector='.moodle-dialogue-exception h5, .modal.show .modal-title, .modal[aria-hidden="false"] .modal-title, [role="dialog"][aria-modal="true"] .modal-title'

function documentFixture(options={}) {
  const state={bodyID:'',classes:[],menuCount:1,fatal:false,errorCode:false,title:'',loading:false,loginForm:false,linkHrefs:[],...options}
  const queries=[]
  const region={querySelectorAll:()=>[]}
  const doc={readyState:state.loading?'loading':'complete',queries,state,
    body:{get id(){return state.bodyID},classList:{contains:name=>state.classes.includes(name)}},
    querySelector(selector){queries.push(selector)
      if(selector===fatalSelector)return state.fatal||state.errorCode?{}:null
      if(selector.split(',').some(part=>['.alert','.alert-danger','.alert.alert-danger','[role="alert"]','#user-notifications'].includes(part.trim())))
        return state.ordinaryAlert?{textContent:state.ordinaryAlert}:null
      if(selector==='#region-main'||selector==='main')return region
      if(selector==='form[action*="login"]')return state.loginForm?{}:null
      return null
    },
    querySelectorAll(selector){queries.push(selector)
      if(selector==='a[href]')return state.linkHrefs.map(href=>({getAttribute:name=>name==='href'?href:null}))
      if(selector.split(',').some(part=>['.alert','.alert-danger','.alert.alert-danger','[role="alert"]','#user-notifications'].includes(part.trim())))
        return state.ordinaryAlert?[{textContent:state.ordinaryAlert}]:[]
      if(selector==='.usermenu .userbutton')return Array.from({length:state.menuCount},()=>({}))
      if(selector===titleSelector)return state.title?[{textContent:state.title}]:[]
      return []
    }}
  return doc
}
function contextFor(doc,extras={}) {
  const window={};window.top=window;doc.defaultView=window
  const context=vm.createContext({window,document:doc,
    location:{origin:'https://qmplus.qmul.ac.uk',href:'https://qmplus.qmul.ac.uk/my/'},
    URL,URLSearchParams,TextEncoder,TextDecoder,Intl,Date,AbortController,setTimeout,clearTimeout,
    M:{cfg:{sesskey:'synthetic-session-only'}},...extras})
  return context
}
function response(data,raw=false) {
  const bytes=new TextEncoder().encode(raw?data:JSON.stringify([{data}]))
  let delivered=false
  return {ok:true,status:200,headers:{get:()=>null},body:{getReader:()=>({read:async()=>{
    if(delivered)return {done:true};delivered=true;return {value:bytes,done:false}
  },releaseLock(){},cancel:async()=>{}}),cancel:async()=>{}}}
}

test('pure page, sync protocol and auth inspection agree on explicit Moodle errors and guest denial',()=>{
  const cases=[
    [{},'authenticated'],[{menuCount:0},'unknown'],[{menuCount:2},'authenticated'],
    [{bodyID:'page-site-index',menuCount:0,linkHrefs:['/auth/saml2/login.php']},'guest'],
    // Regression specifications only; not executed during this change.
    [{bodyID:'page-site-index',menuCount:0,linkHrefs:['/login/index.php']},'guest'],
    [{bodyID:'page-site-index',menuCount:0,linkHrefs:['https://foreign.invalid/login/index.php']},'unknown'],
    [{bodyID:'page-site-index',menuCount:0,linkHrefs:['/login/index.php?target=foreign']},'unknown'],
    [{bodyID:'page-site-index',menuCount:1,linkHrefs:['/login/index.php']},'authenticated'],
    [{bodyID:'page-site-index',menuCount:0,linkHrefs:['https://qmplus.qmul.ac.uk/auth/saml2/login.php']},'guest'],
    [{bodyID:'page-site-index',menuCount:0,linkHrefs:[]},'unknown'],
    [{bodyID:'page-course-view-topics',menuCount:0,linkHrefs:['/auth/saml2/login.php']},'unknown'],
    [{bodyID:'page-site-index',menuCount:1,linkHrefs:['/auth/saml2/login.php']},'authenticated'],
    [{classes:['notloggedin']},'guest'],[{classes:['guestuser']},'guest'],[{bodyID:'page-login-index'},'guest'],
    [{bodyID:'page-error'},'error'],[{fatal:true},'error'],[{errorCode:true},'error'],
    [{title:' generalexceptionmessage '},'error'],[{title:'generalexceptionmessage is mentioned'},'authenticated'],
    [{ordinaryAlert:'Your coursework is due soon'},'authenticated'],
    [{ordinaryAlert:'generalexceptionmessage'},'authenticated'],[{loading:true},'loading'],
    [{loading:true,classes:['notloggedin'],menuCount:0},'guest'],
    [{loading:true,bodyID:'page-login-index',menuCount:0},'guest'],
    [{loading:true,bodyID:'page-error'},'error'],
  ]
  for(const [options,expected] of cases){
    const doc=documentFixture(options),context=contextFor(doc)
    assert.equal(vm.runInContext(pageScript,context),expected)
    vm.runInContext(syncScript,context)
    assert.equal(context.WTSQmProtocol.classifyQMplusPage(),expected)
    assert.equal(vm.runInContext(authScript,context),'AUTH_INSTALLED')
    const report=context.WTSQmAuth.inspect('nonceA123','')
    assert.equal(report.stage,expected==='authenticated'?'authenticated':expected==='loading'?'loading':'manual')
    assert.equal(report.reason,expected==='authenticated'?'AUTHENTICATED':expected==='loading'?'LOADING':'UNSUPPORTED_PAGE')
    assert.equal(report.accountMatch,false)
    assert.doesNotMatch(JSON.stringify(report),/generalexceptionmessage|synthetic-session/)
  }
})

test('page IIFE rejects foreign frames and origins and never reads identity, configuration or storage',()=>{
  const doc=documentFixture(),context=contextFor(doc)
  for(const object of [context,doc]){
    for(const key of object===doc?['cookie']:['M','localStorage','sessionStorage']){
      Object.defineProperty(object,key,{get(){throw new Error('private read is forbidden')},configurable:true})
    }
  }
  Object.defineProperty(context.location,'href',{get(){throw new Error('URL query read is forbidden')},configurable:true})
  const before=Object.keys(context)
  assert.equal(vm.runInContext(pageScript,context),'authenticated')
  assert.deepEqual(Object.keys(context),before)
  context.window.top={}
  assert.equal(vm.runInContext(pageScript,context),'unknown')
  context.window.top=context.window;context.location.origin='https://login.microsoftonline.com'
  assert.equal(vm.runInContext(pageScript,context),'unknown')
  context.location.origin='https://qmplus.qmul.ac.uk';doc.defaultView={}
  assert.equal(vm.runInContext(pageScript,context),'unknown')
  assert.doesNotMatch(pageScript,/document\.cookie|\bM\.|localStorage|sessionStorage|\bfetch\s*\(|console\.|location\.(?:href|search)|WTSQmSync/)
})

test('classless QM home needs a safe fixed SAML anchor and does not classify arbitrary course pages as guests',()=>{
  for(const href of ['https://other.invalid/auth/saml2/login.php','https://qmplus.qmul.ac.uk.evil.invalid/auth/saml2/login.php',
    'http://qmplus.qmul.ac.uk/auth/saml2/login.php','https://user@qmplus.qmul.ac.uk/auth/saml2/login.php',
    'https://qmplus.qmul.ac.uk:9443/auth/saml2/login.php','/auth/saml2/login.php?next=other',
    '/auth/saml2/login.php?','/auth/saml2/login.php#','/auth/saml2/login.php#other','javascript:void(0)']){
    const doc=documentFixture({bodyID:'page-site-index',menuCount:0,linkHrefs:[href]}),context=contextFor(doc)
    assert.equal(vm.runInContext(pageScript,context),'unknown',href)
    vm.runInContext(syncScript,context)
    assert.equal(context.WTSQmProtocol.classifyQMplusPage(),'unknown',href)
    assert.equal(vm.runInContext(authScript,context),'AUTH_INSTALLED')
    assert.equal(context.WTSQmAuth.inspect('nonceA123','').stage,'manual',href)
  }
})

test('guest, error, loading and unknown pages issue no RPC and do not read a stale session key',async()=>{
  for(const options of [{classes:['guestuser']},{bodyID:'page-error'},{fatal:true},{title:'generalexceptionmessage'},
    {menuCount:0},{loading:true},{bodyID:'page-site-index',menuCount:0,linkHrefs:['/auth/saml2/login.php']}]){
    let requests=0,privateReads=0
    const doc=documentFixture(options),context=contextFor(doc,{fetch:async()=>{requests++;throw new Error('unexpected RPC')}})
    Object.defineProperty(context,'M',{get(){privateReads++;throw new Error('stale configuration read')},configurable:true})
    vm.runInContext(syncScript,context)
    const snapshot=await context.WTSQmSync()
    assert.equal(snapshot.ok,false)
    const kind=context.WTSQmProtocol.classifyQMplusPage(doc)
    assert.equal(snapshot.error_code,kind==='error'?'QM_ERROR_PAGE':kind==='guest'?'QM_LOGIN_REQUIRED':'QM_PAGE_NOT_READY')
    assert.equal(requests,0);assert.equal(privateReads,0)
    assert.equal(context.__wtsQmFlight,undefined)
  }
})

test('a page becoming an error during RPC stops further reads and cannot publish a success snapshot',async()=>{
  for(const errorAfterRequest of [1,2]){
    const doc=documentFixture();let requests=0
    const context=contextFor(doc,{fetch:async(_url,options)=>{
      requests++
      const method=JSON.parse(options.body)[0].methodname
      if(requests===errorAfterRequest)doc.state.fatal=true
      return response(method.includes('enrolled_courses')?{courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'}],nextoffset:0}
        :JSON.stringify({cm:[]}))
    }})
    vm.runInContext(syncScript,context)
    const snapshot=await context.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
    assert.equal(snapshot.ok,false);assert.equal(snapshot.error_code,'QM_ERROR_PAGE')
    assert.equal(requests,errorAfterRequest)
    assert.equal(context.__wtsQmFlight,undefined)
  }
})

test('HTTP 200 error and guest detail documents remain unavailable while normal alerts are allowed',async()=>{
  for(const detailOptions of [{bodyID:'page-error'},{fatal:true},{errorCode:true},{title:'generalexceptionmessage'},
    {classes:['guestuser']},{bodyID:'page-login-index'},
    {bodyID:'page-site-index',menuCount:0,linkHrefs:['/auth/saml2/login.php']},{ordinaryAlert:'Your coursework is due soon'}]){
    const detail=documentFixture(detailOptions),blocked=!detailOptions.ordinaryAlert
    const calls=[]
    class DetailDOMParser {parseFromString(){return detail}}
    const context=contextFor(documentFixture(),{DOMParser:DetailDOMParser,fetch:async(url,options)=>{
      calls.push({url,method:options.method})
      if(options.method==='GET')return response('synthetic HTTP 200 document',true)
      const method=JSON.parse(options.body)[0].methodname
      return response(method.includes('enrolled_courses')?{courses:[{id:12,fullname:'EBU1000 - Fixture - 2026/27'}],nextoffset:0}
        :JSON.stringify({cm:[{id:16,module:'assign',name:'Coursework 1'}]}))
    }})
    vm.runInContext(syncScript,context)
    const snapshot=await context.WTSQmSync({now:Date.parse('2026-10-03T10:00:00Z')})
    assert.equal(snapshot.ok,true);assert.equal(snapshot.partial,blocked)
    assert.equal(snapshot.activities[0].detail_status,blocked?'unavailable':'available')
    assert.equal(snapshot.activities[0].due_at,null)
    assert.equal(snapshot.activities[0].status,'unknown')
    assert.equal(snapshot.warnings.includes('QM_DETAIL_PARTIAL'),blocked)
    assert.equal(calls.length,3)
    assert.doesNotMatch(JSON.stringify(snapshot),/generalexceptionmessage|synthetic HTTP|synthetic-session/)
  }
})
