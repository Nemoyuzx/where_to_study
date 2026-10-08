import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replace(/\r\n/g,'\n')
const source=read('src-tauri/src/qmplus.rs')
const recorder=read('src-tauri/src/qmplus_qa_diagnostics.rs')
const gate='all(target_os = "linux", debug_assertions, feature = "qa-qmplus-diagnostics")'
const compact=value=>value.replace(/\s+/g,'')

test('diagnostics require non-default opt-in plus Linux Debug and the exact compile-time QA namespace',()=>{
  const cargo=read('src-tauri/Cargo.toml')
  assert.match(cargo,/^qa-qmplus-diagnostics = \[\]$/m)
  assert.doesNotMatch(cargo.match(/^default = .*$/m)[0],/qa-qmplus-diagnostics/)
  for(const token of ['mod qa_diagnostics;', 'qa_diagnostics: qa_diagnostics::Recorder,', 'qa_diagnostics: Option<qa_diagnostics::Snapshot>,']) {
    const preceding=source.slice(0,source.indexOf(token)).slice(-260)
    assert.ok(compact(preceding).includes(compact(`#[cfg(${gate})]`)),token)
  }
  const macro=source.slice(source.indexOf('macro_rules! qm_qa_mark'),source.indexOf('pub const SCRIPT'))
  assert.ok(compact(macro).includes(compact(`#[cfg(${gate})]`)))
  assert.match(recorder,/option_env!\("WTS_QA_CREDENTIAL_SERVICE"\)[\s\S]*?== Some\("com\.nemoyu\.wheretostudy\.qa\.linux\.de5e10b2c4a64155810262d7869ee74a"\)/)
  assert.doesNotMatch(recorder,/std::env::var|dotenv|set_var/)
})

test('diagnostic recorder accepts only bounded enums and never persists or waits for its mutex',()=>{
  assert.match(recorder,/fn mark\(&self, milestone: Milestone\)/)
  assert.match(recorder,/fn mark_enabled\(&self, milestone: Milestone\)/)
  assert.match(recorder,/state\.try_lock\(\)/)
  assert.match(recorder,/count\.saturating_add\(1\)/)
  assert.match(recorder,/value\.saturating_add\(1\)/)
  assert.match(recorder,/counts: \[u32; ALL\.len\(\)\]/)
  const implementation=recorder.slice(0,recorder.indexOf('#[cfg(test)]'))
  assert.doesNotMatch(implementation,/String|&str|PathBuf|Vec<u8>|std::fs|File::|println!|eprintln!|\.emit\(|\.invoke\(|\.eval\(|spawn|sleep|timeout|credential_store|qmplus_login|qmplus_profile/)
  assert.doesNotMatch(implementation,/\.lock\(\)/)
  const variants=recorder.match(/enum Milestone \{([\s\S]*?)\n\}/)[1].match(/\b[A-Z][A-Za-z]+\b/g)
  const catalog=recorder.match(/const ALL: \[Milestone; (\d+)\] = \[([\s\S]*?)\n\];/)
  assert.equal(variants.length,Number(catalog[1]))
  assert.deepEqual([...catalog[2].matchAll(/Milestone::(\w+)/g)].map(x=>x[1]),variants)
  for(const [,name] of source.matchAll(/qm_qa_mark!\([^;]*?,\s*(\w+)\);/g))assert.ok(variants.includes(name),name)
})

test('only existing main status reads expose a snapshot; operational events stay phase and reason only',()=>{
  const events=source.slice(source.indexOf('fn record_connection_status'),source.indexOf('#[tauri::command]',source.indexOf('fn record_connection_status')))
  assert.doesNotMatch(events,/qa_diagnostics\.snapshot|qa_diagnostics\.mark|qm_qa_mark!|qaDiagnostics/)
  assert.equal((events.match(/qa_diagnostics: None/g)||[]).length,2)
  assert.match(source,/serde\(rename = "qaDiagnostics", skip_serializing_if = "Option::is_none"\)/)
  const status=source.slice(source.indexOf('pub fn load_qmplus_connection_status'),source.indexOf('struct AuthDocument'))
  assert.ok(compact(status).includes(compact(`#[cfg(${gate})]`)))
  assert.match(status,/value\.qa_diagnostics = state\.qa_diagnostics\.snapshot\(\)/)
  assert.doesNotMatch(status,/qm_qa_mark!|\.eval\(|\.invoke\(|\.emit\(|qmplus_login|qmplus_profile/)
  for(const path of ['src-tauri/capabilities/qmplus.json','src-tauri/capabilities/qmplus-verification.json']) {
    assert.doesNotMatch(read(path),/load-qmplus-connection-status|qa-diagnostic/i)
  }
})

test('milestones surround existing native boundaries without changing document guards, scripts or time budgets',()=>{
  assert.match(source,/if state\.feature_blocked\.load\(Ordering::SeqCst\) \|\| !state\.owner_active\.load\(Ordering::SeqCst\) \|\| state\.window_revision\.load\(Ordering::SeqCst\) != window_revision \|\| require_current_profile\(handle, &state\)\.is_err\(\)/)
  assert.match(source,/let Some\(current\) = w\.url\(\)\.ok\(\)\.filter\(\|u\| u == p\.url\(\)\)/)
  assert.match(source,/qm_qa_mark!\(state, FinishedCallback\)[\s\S]*?qm_qa_mark!\(state, CallbackGuardRejected\)/)
  assert.match(source,/qm_qa_mark!\(state, PageEvalRequested\);\s*let _ = window\.eval\(/)
  assert.match(source,/qm_qa_mark!\(state, AuthEvalRequested\);\s*if qm_qa_auth_eval!\(w, &\*script, handle, revision\)\.is_err\(\)/)
  assert.match(source,/qm_qa_mark!\(handle\.state::<QmState>\(\), DeadlineExpired\);\s*require_manual\(&handle, &window, "QUIET_TIMEOUT"\)/)
  assert.match(source,/Duration::from_secs\(25\)/)
  assert.match(source,/Duration::from_secs\(130\)/)
  assert.match(source,/settling\+\+<16/)
  for(const [,body] of source.matchAll(/(?:format!\(r#"|format!\(")([\s\S]*?)(?:"#|"\))/g)) {
    assert.doesNotMatch(body,/qm_qa_mark!|qaDiagnostics|qa-diagnostics/)
  }
})
