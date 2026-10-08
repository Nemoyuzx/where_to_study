import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import vm from 'node:vm'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replace(/\r\n/g,'\n')
const source=read('src-tauri/src/qmplus.rs')
const observer=read('src-tauri/src/qmplus_qa_auth_observer.rs')
const raw=name=>observer.match(new RegExp(`const ${name}: &str = r#"([\\s\\S]*?)"#;`))[1]
const prefix=raw('PREFIX'),reader=raw('READ_SCRIPT')
const suffix=JSON.parse(observer.match(/const SUFFIX: &str = ("(?:[^"\\]|\\.)*");/)[1])
const replacements=[...observer.slice(observer.indexOf('const REPLACEMENTS'),observer.indexOf('const PREFIX')).matchAll(/\(\s*r#"([\s\S]*?)"#,\s*r#"([\s\S]*?)"#,?\s*\)/g)].map(([,a,b])=>[a,b])
const template=source.match(/let script = Zeroizing::new\(format!\(r#"(\(\(\)=>\{\{const install=\{AUTH_SCRIPT\};[\s\S]*?)"#,/)[1]
const render=auth=>template.replaceAll('{AUTH_SCRIPT}',auth).replaceAll('{revision}','7').replaceAll('{nonce}','"fixture-nonce"').replaceAll('{url}','"https://fixture.invalid/"').replaceAll('{account}','"fixture-account"').replaceAll('{identity_acknowledged}','false').replaceAll('{{','{').replaceAll('}}','}')
const script=render('fixtureInstall()')
const transform=value=>{
  if(replacements.some(([needle])=>value.split(needle).length!==2))return null
  for(const [needle,replacement] of replacements)value=value.replace(needle,replacement)
  return prefix+value+suffix
}
const flush=async()=>{for(let i=0;i<4;i++)await new Promise(resolve=>setImmediate(resolve))}
function fixture(options={}) {
  const calls=[],timers=[],events=new Map()
  const context=vm.createContext({
    fixtureInstall:()=>options.install??'AUTH_INSTALLED',
    location:{href:'https://fixture.invalid/'},
    WTSQmAuth:{inspect:()=>{if(options.inspectThrow)throw new Error('fixture private error');return {v:1,stage:options.stage??'challenge',reason:options.reason??'',document:'fixture-nonce'}}},
    setTimeout:(fn,delay)=>{timers.push({fn,delay});return timers.length},clearTimeout:()=>{},
    window:{addEventListener:(name,fn)=>events.set(name,fn),removeEventListener:name=>events.delete(name),__TAURI_INTERNALS__:{invoke:(command,args)=>{calls.push({command,args});return options.invoke?options.invoke(command,args):Promise.resolve(false)}}},
  })
  if(options.conflict)vm.runInContext("Object.defineProperty(globalThis,'WTSQmAuthPollActive',{value:()=>false})",context)
  if(options.mismatch)context.location.href='https://mismatch.invalid/'
  return {context,calls,timers,events,tag:()=>vm.runInContext(reader,context),run:(value=transform(script))=>vm.runInContext(value,context)}
}

test('all ten exact needles must occur once; a missing or duplicated needle rejects the entire transform',()=>{
  assert.equal(replacements.length,10)
  assert.ok(transform(script))
  for(const [needle] of replacements) {
    assert.equal(transform(script.replace(needle,'')),null)
    assert.equal(transform(script+needle),null)
  }
  assert.match(observer,/script\.matches\(\*needle\)\.count\(\) != 1/)
  assert.match(observer,/Zeroizing::new\(observed\.replacen/)
})

test('transformed production template remains valid and has only Linux Debug exact-namespace runtime wiring',()=>{
  assert.doesNotThrow(()=>new vm.Script(transform(script)))
  const canonical=transform(render(read('contracts/qmplus/qmplus-auth.js')))
  assert.ok(canonical)
  assert.doesNotThrow(()=>new vm.Script(canonical))
  const beforeModule=source.slice(0,source.indexOf('mod qa_auth_observer;')).slice(-240).replace(/\s/g,'')
  assert.ok(beforeModule.includes('#[cfg(all(target_os="linux",debug_assertions,feature="qa-qmplus-diagnostics"))]'))
  const helper=source.slice(source.indexOf('fn eval_qmplus_auth_qa('),source.indexOf('struct QaAuthProbe'))
  assert.ok(helper.indexOf('if !qa_diagnostics::enabled()')<helper.indexOf('qa_auth_observer::transform(script)'))
  assert.match(helper,/let Some\(observed\) = qa_auth_observer::transform\(script\) else \{\s*qm_qa_mark!\(state, AuthObserverTransformUnavailable\);\s*return window\.eval\(script\);/)
})

test('success keeps one original invoke, returned outcome and polling delay',async()=>{
  const f=fixture();f.run();await flush()
  assert.equal(f.calls.length,1)
  assert.equal(f.calls[0].command,'accept_qmplus_auth')
  assert.equal(f.tag(),'IPC_RESOLVED')
  assert.deepEqual(f.timers.map(x=>x.delay),[750])
  const descriptor=vm.runInContext("Object.getOwnPropertyDescriptor(globalThis,'__WTS_QA_AUTH_OBSERVER_V1')",f.context)
  assert.equal(descriptor.enumerable,false)
  assert.equal(descriptor.writable,false)
})

test('install conflict and poll conflict remain terminal even after finish',async()=>{
  for(const [options,tag] of [[{install:'AUTH_CONFLICT'},'INSTALL_CONFLICT'],[{conflict:true},'POLL_CONFLICT']]) {
    const f=fixture(options);f.run();await flush()
    assert.equal(f.tag(),tag)
    assert.equal(f.calls.length,1)
    assert.equal(f.timers.length,0)
  }
})

test('the original location comparison alone produces mismatch, before or after IPC',async()=>{
  const early=fixture({mismatch:true});early.run();await flush()
  assert.equal(early.tag(),'LOCATION_MISMATCH');assert.equal(early.calls.length,0)
  let resolve
  const late=fixture({invoke:()=>new Promise(r=>{resolve=r})});late.run()
  assert.equal(late.tag(),'IPC_REQUESTED')
  late.context.location.href='https://mismatch.invalid/';resolve(false);await flush()
  assert.equal(late.tag(),'LOCATION_MISMATCH');assert.equal(late.calls.length,1)
})

test('a rejected IPC retains the rejection tag through original catch cancellation with no unhandled rejection',async()=>{
  const f=fixture({invoke:()=>Promise.reject(new Error('fixture private error'))})
  f.run();await flush()
  assert.equal(f.tag(),'IPC_REJECTED');assert.equal(f.calls.length,1);assert.equal(f.timers.length,0)
})

test('inspection is marked before and after it returns; pagehide cancellation is terminal',async()=>{
  const f=fixture({stage:'manual',reason:'FORM_UNTRUSTED'});f.run()
  assert.equal(f.tag(),'INSPECT_RETURNED');assert.equal(f.calls.length,0)
  f.events.get('pagehide')();assert.equal(f.tag(),'CANCELLED')
  f.timers[0].fn();await flush();assert.equal(f.tag(),'CANCELLED')
})

test('inspection failure keeps ENTERED without reading the thrown value',async()=>{
  const f=fixture({inspectThrow:true})
  // Capture the existing discarded poll Promise in this fixture only, so its
  // rejection can be asserted without altering production rejection behavior.
  f.run(transform(script).replace(';poll();})()',';globalThis.fixturePollResult=poll();})()'))
  await assert.rejects(f.context.fixturePollResult)
  assert.equal(f.tag(),'INSPECT_ENTERED');assert.equal(f.calls.length,0)
})

test('normal transformed paths retain baseline reports, attempts, cancellation and scheduling',async()=>{
  for(const options of [{},{stage:'manual',reason:'FORM_UNTRUSTED'},{stage:'manual',reason:'ALREADY_ATTEMPTED'},{stage:'manual',reason:'ACCOUNT_CHOOSER',invoke:()=>Promise.resolve(true)},{stage:'username',invoke:()=>Promise.resolve(true)}]) {
    const baseline=fixture(options),observed=fixture(options)
    baseline.run(script);observed.run();await flush()
    assert.equal(JSON.stringify(observed.calls),JSON.stringify(baseline.calls))
    assert.deepEqual(observed.timers.map(x=>x.delay),baseline.timers.map(x=>x.delay))
    assert.deepEqual([...observed.events.keys()],[...baseline.events.keys()])
  }
})

test('readback accepts only fixed tags, avoids accessors and discloses no arbitrary value',()=>{
  for(const value of ['private text',{account:'private'},null,42]) {
    const context=vm.createContext({})
    context.__WTS_QA_AUTH_OBSERVER_V1=value
    assert.equal(vm.runInContext(reader,context),'OBSERVER_UNAVAILABLE')
  }
  const context=vm.createContext({})
  vm.runInContext("Object.defineProperty(globalThis,'__WTS_QA_AUTH_OBSERVER_V1',{get(){throw new Error('private')}})",context)
  assert.equal(vm.runInContext(reader,context),'OBSERVER_UNAVAILABLE')
  assert.doesNotMatch(reader,/document|location|storage|cookie|account|console|invoke|fetch/)
  assert.match(reader,/typeof tag!=='string'/)
  assert.match(reader,/switch\(tag\)/)
  assert.doesNotMatch(reader,/return tag|includes/)
  const tags=[...reader.matchAll(/case '(\w+)':return '(\w+)'/g)]
  assert.equal(tags.length,11)
  const rustMap=observer.slice(observer.indexOf('fn milestone('),observer.indexOf('fn transform('))
  for(const [,tag,result] of tags){assert.equal(tag,result);assert.ok(rustMap.includes(`\\"${tag}\\"`))}
  assert.match(rustMap,/_ => Milestone::AuthObserverUnavailable/)
})

test('one bounded native read is fenced before read and on callback by document and owner generations',()=>{
  const guard=source.slice(source.indexOf('fn qa_auth_probe_is_current('),source.indexOf('fn arm_qa_auth_probe('))
  for(const token of ['qa_diagnostics::enabled()','!state.feature_blocked.load','state.owner_active.load','!state.auth_suspended.load','== probe.revision','== probe.window_revision','== probe.document_generation','== probe.credential_revision','auth.ledger.accepts(probe.credential_revision)','state.auth.try_lock()'])assert.ok(guard.replace(/\s/g,'').includes(token.replace(/\s/g,'')),token)
  const arm=source.slice(source.indexOf('fn arm_qa_auth_probe('),source.indexOf('pub const SCRIPT'))
  assert.equal((arm.match(/Duration::from_secs\(8\)/g)||[]).length,1)
  assert.equal((arm.match(/eval_with_callback\(/g)||[]).length,1)
  assert.ok((arm.match(/qa_auth_probe_is_current\(&state, probe\)/g)||[]).length>=3)
  assert.match(arm,/scheduled != probe.document_generation/)
  assert.doesNotMatch(arm,/loop |while |record_connection_status|require_manual|\.invoke\(|\.navigate\(|\.show\(|\.store\(|\.url\(|AUTH_SCRIPT|PAGE_SCRIPT/)
  const callback=arm.slice(arm.indexOf('move |result|'),arm.indexOf('}).is_err()',arm.indexOf('move |result|')))
  assert.match(callback,/Zeroizing::new\(result\)/)
  assert.match(callback,/qa_auth_observer::milestone\(result.as_str\(\)\)/)
  assert.doesNotMatch(callback,/\.emit\(|println|eprintln|std::fs|format!|serde_json/)
  assert.match(source,/PageLoadEvent::Started \{\s*if qa_diagnostics::enabled\(\) \{\s*state.qa_document_generation.fetch_add\(1, Ordering::SeqCst\);/)
})
