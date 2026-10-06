import assert from 'node:assert/strict'
import {readFileSync,readdirSync} from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'
import {transformSync} from 'esbuild'

// Regression specification only. NOT executed for this change: the user has
// prohibited local automated tests. Synthetic SDK doubles are not ArkWeb proof.
const root=new URL('../native/harmony/entry/src/main/ets/',import.meta.url)
const read=path=>readFileSync(new URL(path,root),'utf8')
const source=read('store/QMPlusWebProfileStore.ets')
function processFixture(persisted=new Map(),{usage=0,clearFails=false,flushFails=false}={}){
  const events=[]
  const prefs={hasSync:key=>persisted.has(key),getSync:(key,fallback)=>persisted.get(key)??fallback,
    putSync:(key,value)=>persisted.set(key,value),flushSync:()=>{if(flushFails)throw Error('synthetic fence failure')}}
  const module={exports:{}}
  const code=transformSync(source.replace(/^import[^\n]+\n/gm,''),{loader:'ts',format:'cjs',target:'es2022'}).code
  vm.runInNewContext(code,{module,exports:module.exports,preferences:{getPreferencesSync:()=>prefs},AppContext:{get:()=>({})},
    newQMPlusRecordID:()=> 'a'.repeat(32),
    webview:{WebCookieManager:{clearAllCookies:async()=>{events.push('cookie-clear-ack');if(clearFails)throw Error('synthetic clear failure')},
      saveCookieAsync:async()=>events.push('cookie-save-ack'),existCookie:()=>false},
    WebStorage:{deleteAllData:()=>events.push('storage-request'),getOrigins:async()=>[{usage}]}}})
  return {policy:new module.exports.QMPlusWebProfileStore(),persisted,events}
}
test('only the QMplus Web may use the app-owned persistent profile and it first mounts a network-free blank page',()=>{
  function files(directory){return readdirSync(directory,{withFileTypes:true}).flatMap(entry=>
    entry.isDirectory()?files(new URL(entry.name+'/',directory)):entry.name.endsWith('.ets')?[new URL(entry.name,directory)]:[])}
  const webFiles=files(root).filter(path=>/\bWeb\(\{/.test(readFileSync(path,'utf8')))
  assert.equal(webFiles.length,1)
  assert.ok(webFiles[0].pathname.endsWith('/QMPlusConnectionView.ets'))
  const web=read('view/QMPlusConnectionView.ets')
  assert.match(web,/Web\(\{ src: 'about:blank', controller: this\.controller, incognitoMode: QMPlusWebProfileStore\.incognitoMode \}\)/)
  assert.match(source,/static readonly incognitoMode: boolean = false/)
  assert.match(web,/await this\.session\.prepareOfficialWeb\(ticket\)[\s\S]*this\.controller\.loadUrl\(this\.session\.targetURL\)/)
  assert.doesNotMatch(source,/fetchCookie|fetchAllCookies|document\.cookie|JSON\.(?:parse|stringify)|console\./)
})
test('an unused normal profile can complete the initial clear without initializing a browser or fetching secrets',async()=>{
  const f=processFixture()
  assert.equal(f.policy.markClearPending(),true)
  assert.equal(await f.policy.clear(),true)
  assert.equal(f.policy.isReady(),true)
  assert.deepEqual(f.events,[])
})
test('retiring a used profile persists pending and refuses all same-process mount/clear attempts',async()=>{
  const f=processFixture()
  assert.equal(f.policy.reserveWebMount(),true)
  f.policy.noteWebLoaded()
  assert.equal(f.policy.markClearPending(),true)
  assert.equal(f.persisted.get('profileState'),'v1:clear-used')
  assert.equal(f.policy.requiresRestart(),true)
  assert.equal(f.policy.reserveWebMount(),false)
  assert.equal(await f.policy.clear(),false)
  assert.equal(f.policy.isReady(),false)
  assert.deepEqual(f.events,[])
})
test('a fresh process preserves pending until blank initialization, cookie ACK, zero usage and cookie-save ACK complete',async()=>{
  const f=processFixture(new Map([['profileState','v1:clear-used']]))
  assert.equal(await f.policy.prepare(),false)
  assert.equal(f.policy.reserveWebMount(),true)
  assert.equal(f.persisted.get('profileState'),'v1:clear-used')
  f.policy.noteWebLoaded()
  assert.equal(await f.policy.prepare(),true)
  assert.equal(f.persisted.get('profileState'),'v1:ready')
  assert.deepEqual(f.events,['cookie-clear-ack','storage-request','cookie-save-ack'])
})
test('delete failure, nonzero storage usage, corrupt fence or fence write failure cannot enable the old identity',async()=>{
  for(const options of [{clearFails:true},{usage:8}]){
    const f=processFixture(new Map([['profileState','v1:clear-used']]),options)
    f.policy.noteWebLoaded()
    assert.equal(await f.policy.prepare(),false)
    assert.equal(f.policy.isReady(),false)
    assert.equal(f.persisted.get('profileState'),'v1:clear-used')
  }
  const corrupt=processFixture(new Map([['profileState','invalid']]))
  assert.equal(corrupt.policy.reserveWebMount(),false)
  assert.equal(corrupt.policy.isReady(),false)
  const unwritable=processFixture(new Map(),{flushFails:true})
  assert.equal(unwritable.policy.markClearPending(),false)
  assert.equal(unwritable.policy.isReady(),false)
  assert.deepEqual(unwritable.events,[])
})
test('feature Off retains cookies and the same authorized record is saved as a no-op instead of clearing identity',()=>{
  const session=read('view/QMPlusSession.ets')
  const off=session.slice(session.indexOf('  setFeatureEnabled('),session.indexOf('  logout()'))
  assert.match(off,/this\.closeLogin\(\)/)
  assert.doesNotMatch(off,/markClearPending|clearOwnedWebSession|deleteSavedLogin/)
  const save=session.slice(session.indexOf('  async saveSavedLogin('),session.indexOf('  async setAutoFillEnabled('))
  assert.match(save,/marker === previous\.recordID/)
  assert.match(save,/previous\.password === password/)
  assert.ok(save.indexOf('return true;')<save.indexOf('this.clearConnection()'))
  assert.match(session,/isOfficialWebReady\(authorization\.owner\)/)
})
test('new credentials may be saved behind a confirmed durable fence but cannot enable the old profile',()=>{
  const session=read('view/QMPlusSession.ets')
  const save=session.slice(session.indexOf('  async saveSavedLogin('),session.indexOf('  async setAutoFillEnabled('))
  assert.match(save,/clearAccepted && this\.webProfile !== null && this\.webProfile\.hasDurableClearPending\(\)/)
  assert.ok(save.indexOf('revokeBeforeRecordChange()')<save.indexOf('savedLoginStore.save(login)'))
  assert.ok(save.indexOf('hasDurableClearPending()')<save.indexOf('savedLoginStore.save(login)'))
  assert.match(save,/if \(!webCleared && !fencedForRestart\)[\s\S]*?return false/)
  assert.match(save,/if \(!webCleared\)[\s\S]*?QMplus 网页会话需要清理，请重新启动应用。/)
  assert.match(source,/hasDurableClearPending\(\): boolean[\s\S]*?this\.write\(state\)/)
  const deletion=source.slice(source.indexOf('  private async clearOnce('),source.indexOf('  async flush('))
  assert.ok(deletion.indexOf('this.write(state)')<deletion.indexOf('WebCookieManager.clearAllCookies()'))
})
test('recreated sessions share the mutation queue and disposal retires old write/status completions',()=>{
  const session=read('view/QMPlusSession.ets')
  assert.match(session,/private static savedLoginMutationInProcess: Promise<boolean>/)
  assert.match(session,/QMPlusSession\.savedLoginMutationInProcess\.catch/)
  const disposal=session.slice(session.indexOf('  dispose(): void'),session.indexOf('  presentLogin(): void'))
  assert.match(disposal,/this\.loginSettingsRevision\+\+/)
  assert.match(disposal,/this\.autoFillEnabled = false/)
  assert.match(source,/revision === QMPlusWebProfileStore\.clearRevision && this\.isReady\(\)/)
})
