import assert from 'node:assert/strict'
import test from 'node:test'
import {readFileSync} from 'node:fs'
const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8')
test('every registered desktop command has a generated permission and an explicit local or remote consumer',()=>{
  const lib=read('src-tauri/src/lib.rs')
  const handler=lib.slice(lib.indexOf('.invoke_handler(tauri::generate_handler!['))
    .split('])')[0]
  const registered=[...handler.matchAll(/^\s*(?:\w+::)?(\w+),\s*$/gm)].map(m=>m[1])
  const declared=[...read('src-tauri/build.rs').matchAll(/"([a-z_]+)"/g)].map(m=>m[1])
  assert.ok(registered.length>30)
  for(const command of registered)assert.ok(declared.includes(command),`Missing permission declaration: ${command}`)
  const main=JSON.parse(read('src-tauri/capabilities/default.json')).permissions
  const remote=JSON.parse(read('src-tauri/capabilities/qmplus.json')).permissions
  for(const command of registered)assert.ok([...main,...remote].includes(`allow-${command.replaceAll('_','-')}`),`Unassigned permission: ${command}`)
  for(const name of ['save_qmplus_login','load_qmplus_login','set_qmplus_autofill','clear_qmplus_login','set_qmplus_enabled']){
    assert.ok(main.includes(`allow-${name.replaceAll('_','-')}`))
    assert.ok(!remote.includes(`allow-${name.replaceAll('_','-')}`))
  }
  assert.deepEqual(remote.sort(),['allow-accept-qmplus-auth','allow-accept-qmplus-snapshot','allow-begin-qmplus-sync'])
  const qm=read('src-tauri/src/qmplus.rs')
  const sync=qm.slice(qm.indexOf('pub fn begin_qmplus_sync('),qm.indexOf('pub async fn connect_qmplus('))
  assert.match(sync,/feature_blocked/)
  assert.match(sync,/owner_active/)
  assert.match(sync,/revision != state\.revision/)
  assert.match(sync,/valid_source\(window\.label\(\), &u\)/)
  assert.doesNotMatch(sync,/qmplus_login|credential|password|account\s*:/)
})
test('QM credential requests use the existing payload envelope and metadata excludes account and password',()=>{
  const login=read('src-tauri/src/qmplus_login.rs')
  assert.match(login,/save_qmplus_login\([\s\S]*?payload: LoginRequest/)
  assert.match(login,/set_qmplus_autofill\([\s\S]*?payload: AutofillRequest/)
  assert.match(login,/deny_unknown_fields/)
  const metadata=login.slice(login.indexOf('pub struct LoginStatus'),login.indexOf('#[derive(Deserialize'))
  assert.doesNotMatch(metadata,/account|password/)
  assert.match(read('src/QmplusLoginSettings.jsx'),/autoComplete="new-password"/)
  assert.doesNotMatch(read('src/QmplusLoginSettings.jsx'),/localStorage\.|console\.|new URLSearchParams\(/)
})
