import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8')
const native=read('src-tauri/src/qmplus.rs')
const bridgeBody=native.slice(native.indexOf('fn sync_bridge('),native.indexOf('pub fn begin_qmplus_sync('))
const template=bridgeBody.match(/r#"([\s\S]*?)"#/)[1]
const guard=native.match(/const DOCUMENT_GUARD: &str = "([^\n]+)";/)[1]
const script=template.replaceAll('{{','{').replaceAll('}}','}')
  .replaceAll('{DOCUMENT_GUARD}',guard)
  .replaceAll('{PAGE_SCRIPT}',read('contracts/qmplus/qmplus-page.js'))
  .replaceAll('{revision}','7')

function fixture({origin='https://qmplus.qmul.ac.uk',path='/my/',kind='authenticated',rejectBegin=false}={}) {
  const calls=[]
  let syncs=0
  const window={__TAURI_INTERNALS__:{invoke:async(command,args)=>{
    calls.push({command,args})
    if(rejectBegin&&command==='begin_qmplus_sync')throw Error('synthetic retired owner')
  }}}
  window.top=window
  const document={defaultView:window,readyState:kind==='loading'?'loading':'complete',
    body:{id:kind==='error'?'page-error':kind==='guest'?'page-login-index':'page-my-index',
      classList:{contains:()=>false},appendChild:()=>{throw Error('no injected controls allowed')}},
    querySelector:()=>null,
    querySelectorAll:selector=>selector==='.usermenu .userbutton'&&kind==='authenticated'?[{}]:[],
    createElement:()=>{throw Error('no injected controls allowed')}}
  Object.defineProperty(document,'cookie',{get(){throw Error('cookie reads forbidden')}})
  const context=vm.createContext({window,document,location:{origin,pathname:path},
    WTSQmSync:async()=>{syncs++;return {source:'qmplus',ok:true,courses:[],activities:[]}}})
  return {calls,get syncs(){return syncs},run:()=>vm.runInContext(script,context)}
}

test('official dashboard automatically syncs once without adding a login-window sync button',async()=>{
  const f=fixture()
  await f.run();await f.run()
  assert.equal(f.syncs,1)
  assert.deepEqual(f.calls.map(call=>call.command),['begin_qmplus_sync','accept_qmplus_snapshot'])
  assert.equal(f.calls[0].args.revision,7)
  assert.equal(JSON.parse(f.calls[1].args.payload).ok,true)
})

test('automatic sync does not run on login, error, loading, foreign or non-dashboard pages',async()=>{
  for(const options of [{kind:'guest'},{kind:'error'},{kind:'loading'},
    {origin:'https://login.microsoftonline.com'},{path:'/course/view.php'}]) {
    const f=fixture(options)
    await f.run()
    assert.equal(f.syncs,0)
    assert.equal(f.calls.length,0)
  }
})

test('a retired native sync owner never fetches or publishes a new snapshot',async()=>{
  const f=fixture({rejectBegin:true})
  await f.run();await f.run()
  assert.equal(f.syncs,0)
  assert.deepEqual(f.calls.map(call=>call.command),['begin_qmplus_sync'])
})

test('background Connect recovers cleanup first and never prepares an absent profile',()=>{
  const connect=native.slice(native.indexOf('pub async fn connect_qmplus('),native.indexOf('pub struct ConnectRequest'))
  const prefix=connect.slice(0,connect.indexOf('let (sent, received)'))
  assert.match(prefix,/recover_pending\(&app\)\.await\?;\s*(?:\/\/[^\r\n]*\r?\n\s*)*if request\.background && !crate::qmplus_profile::active_profile_ready\(&app\)\s*\{\s*return Ok\(\(\)\);\s*\}/)
  assert.doesNotMatch(prefix,/prepare\(|qmplus_login::|credential_store|authorize\(/)
  assert.match(connect,/run_on_main_thread[\s\S]*connect_qmplus_on_main\([\s\S]*request\.background,[\s\S]*request\.manual,/)
  const condition=prefix.match(/if (request\.background[^\{]+)\{/)[1]
    .replace('crate::qmplus_profile::active_profile_ready(&app)','activeProfileReady()')
  const skips=new Function('request','activeProfileReady',`return ${condition}`)
  for(const background of [false,true])for(const active of [false,true])for(const manual of [false,true]){
    let reads=0
    assert.equal(skips({background,manual},()=>{reads++;return active}),background&&!active)
    assert.equal(reads,background?1:0)
  }
})
