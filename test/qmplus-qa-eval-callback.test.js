import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createHash} from 'node:crypto'
import vm from 'node:vm'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replace(/\r\n/g,'\n')
const source=read('src-tauri/src/qmplus.rs')
const compact=value=>value.replace(/\s+/g,'')
const gate='all(target_os = "linux", debug_assertions, feature = "qa-qmplus-diagnostics")'
const prefix=JSON.parse(source.match(/const QA_AUTH_EVAL_PREFIX:\s*&str\s*=\s*("(?:[^"\\]|\\.)*");/)[1])
const suffix=JSON.parse(source.match(/const QA_AUTH_EVAL_SUFFIX:\s*&str\s*=\s*("(?:[^"\\]|\\.)*");/)[1])
const helper=source.slice(source.indexOf('fn eval_qmplus_auth_qa('),source.indexOf('pub const SCRIPT'))
const macro=source.slice(source.indexOf('macro_rules! qm_qa_auth_eval'),source.indexOf('const QA_AUTH_EVAL_PREFIX'))
const digest=value=>createHash('sha256').update(value).digest('hex')

test('native callback wrapper is gated twice, while non-QA expansion is the unchanged eval',()=>{
  assert.ok(compact(macro).includes(compact(`#[cfg(${gate})]`)))
  assert.ok(compact(macro).includes(compact(`#[cfg(not(${gate}))]`)))
  assert.match(macro,/if qa_diagnostics::enabled\(\) \{\s*eval_qmplus_auth_qa[\s\S]*?else \{\s*\$window\.eval\(\$script\)/)
  assert.match(macro,/\{\s*\$window\.eval\(\$script\)\s*\}/)
  assert.match(helper,/if !qa_diagnostics::enabled\(\) \{\s*return window\.eval\(script\);/)
  assert.ok(helper.indexOf('if !qa_diagnostics::enabled()')<helper.indexOf('Zeroizing::new(format!'))
  for(const token of ['const QA_AUTH_EVAL_PREFIX','const QA_AUTH_EVAL_SUFFIX','fn eval_qmplus_auth_qa']) {
    const preceding=source.slice(0,source.indexOf(token)).slice(-180)
    assert.ok(compact(preceding).includes(compact(`#[cfg(${gate})]`)),token)
  }
})

test('callback receives only fixed native metadata and never writes authentication state or retains raw output',()=>{
  assert.match(helper,/window: &tauri::WebviewWindow/)
  assert.match(helper,/wrapped = Zeroizing::new\(format!/)
  assert.match(helper,/eval_with_callback\(wrapped\.as_str\(\), move \|result\|/)
  const callback=helper.slice(helper.indexOf('move |result|'),helper.indexOf('\n    });',helper.indexOf('move |result|')))
  assert.match(callback,/let result = Zeroizing::new\(result\)/)
  assert.match(callback,/state\.revision\.load\(Ordering::SeqCst\) != revision/)
  for(const stage of ['AuthEvalCallbackReceived','AuthEvalReturned','AuthEvalSyncThrown','AuthEvalResultUnavailable'])assert.ok(callback.includes(stage))
  assert.doesNotMatch(callback,/script|wrapped|window|document|\.url\(|account|nonce|\.store\(|\.fetch_add\(|record_connection_status|require_manual|\.emit\(|println!|eprintln!|format!|std::fs|invoke|spawn|sleep/)
  assert.doesNotMatch(prefix+suffix,/document|location|globalThis|__TAURI|console|fetch|storage|cookie/)
  assert.match(callback,/_ => qm_qa_mark!\(state, AuthEvalResultUnavailable\)/)
})

test('synchronous return, throw and malformed script remain distinct without exposing exception text',()=>{
  assert.equal(vm.runInNewContext(prefix+'(()=>{})()'+suffix),'WTS_QA_AUTH_RETURNED')
  assert.equal(vm.runInNewContext(prefix+'(()=>{throw 0})()'+suffix),'WTS_QA_AUTH_SYNC_THROWN')
  assert.throws(()=>new vm.Script(prefix+'(()=>{'+suffix),SyntaxError)
  assert.doesNotMatch(suffix,/catch\s*\([^)]/)
})

test('RETURNED proves synchronous eval only, not Promise resolution or authentication',async()=>{
  assert.equal(vm.runInNewContext(prefix+'Promise.resolve(false)'+suffix),'WTS_QA_AUTH_RETURNED')
  assert.equal(vm.runInNewContext(prefix+'Promise.reject(0).catch(()=>{})'+suffix),'WTS_QA_AUTH_RETURNED')
  await new Promise(resolve=>setImmediate(resolve))
  assert.match(helper,/RETURNED[\s\S]*?does not mean a Promise resolved, an IPC report arrived or login succeeded/)
})

test('original authentication template, helper and remote ACL are byte-for-byte unchanged',()=>{
  const start=source.indexOf('let script = Zeroizing::new(format!(r#"(()=>{{const install={AUTH_SCRIPT};')
  const end=source.indexOf('"#,',start)
  assert.ok(start>=0&&end>start)
  assert.equal(digest(source.slice(start,end+3)),'b802991815a619573460d5b7980ccbaf9d880bfdb5fbc263f82c1fea80158521')
  assert.equal(digest(read('contracts/qmplus/qmplus-auth.js')),'bfa7a15b4fe93d92285cd0f88599f06a00b1befdf6c94793867c9c15f8f37cdc')
  assert.equal(digest(read('src-tauri/capabilities/qmplus.json')),'63a0fda640a612bd8f59472c1a300acf5ad75511898deb82bfda813c01a6d8b6')
  assert.equal(digest(read('src-tauri/capabilities/qmplus-verification.json')),'1a9e7665d0f653e11ce4dab73967778f295f462190d6d3d16d67244356a58824')
})
