import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'
import {transformSync} from 'esbuild'

// Actual Harmony Session/View methods; synthetic DOM, ArkWeb and ASSET only.
// This is not device/SSO/MFA verification and never reads real credentials.
const sourceRoot=new URL('../native/harmony/entry/src/main/ets/',import.meta.url)
const pageScript=readFileSync(new URL('../contracts/qmplus/qmplus-page.js',import.meta.url),'utf8')
function load(path,injected={},component=false){
  let source=readFileSync(new URL(path,sourceRoot),'utf8').replace(/^import[\s\S]*?;\r?\n/gm,'')
  if(component)source=source.slice(0,source.indexOf('  build() {'))+'}\n'
  source=source.replace(/@(?:ObservedV2|ComponentV2)\s*/g,'').replace(/@Monitor\([^\n]*\)\s*/g,'')
    .replace(/@(?:Trace|Local)\s+/g,'').replace(/@(?:Consumer|Param)\([^\n]*?\)\s*/g,'').replace(/@Param\s+/g,'')
    .replace('export struct QMPlusConnectionView','export class QMPlusConnectionView')
  const module={exports:{}}
  vm.runInNewContext(transformSync(source,{loader:'ts',format:'cjs',target:'es2022'}).code,
    {...injected,module,exports:module.exports,setTimeout,clearTimeout})
  return module.exports
}
const pure={...load('common/JsonUtil.ets'),...load('common/Utf8.ets')}
const snapshots=load('net/QMPlusSnapshot.ets',pure),records=load('store/QMPlusSavedLoginStore.ets')
const sessions=load('view/QMPlusSession.ets',{...snapshots,...records,PreferencesStore:class{}})
const views=load('view/QMPlusConnectionView.ets',{...snapshots,...records,...sessions,
  AppModel:class{},webview:{WebviewController:class{}}},true)
async function fixture(url,{links=[],kind='guest'}={}){
  const trace={gets:[],stops:0,cookieClears:0,syncs:0,scripts:0}
  const store={login:null,async load(){return this.login},async save(value){this.login=value},async clear(){throw Error('unexpected secret deletion')}}
  const journal={value:null,async getString(){return this.value},async setString(_key,value){this.value=value},async remove(){this.value=null}}
  const session=new sessions.QMPlusSession(()=>{trace.cookieClears++},store,journal,()=>'a'.repeat(32))
  await session.saveSavedLogin('synthetic@example.invalid','synthetic-only')
  await session.setAutoFillEnabled(true)
  session.openLogin()
  const window={};window.top=window
  const doc={readyState:'complete',defaultView:window,body:{id:kind==='error'?'page-error':kind==='guest'?'page-site-index':'page-course-view',classList:{contains:()=>false}},
    querySelector:()=>null,querySelectorAll:selector=>selector==='a[href]'?links.map(href=>({getAttribute:()=>href})):
      selector==='.usermenu .userbutton'&&kind!=='guest'?[{},{}]:[]}
  const context=vm.createContext({window,document:doc,location:{origin:'https://qmplus.qmul.ac.uk',href:url},URL})
  const renderer={url,getUrl(){return this.url},stop(){trace.stops++},loadUrl(value){trace.gets.push(value);this.url=value},
    async runJavaScript(script){trace.scripts++;const value=vm.runInContext(script,context);return typeof value==='string'?value:JSON.stringify(value)}}
  const view=new views.QMPlusConnectionView()
  Object.assign(view,{session,model:{isSampleMode:()=>false},controller:renderer,mounted:true,authForeground:true,
    loginOwner:session.loginOwner(),documentReadyURL:url,pageScript})
  view.authLedger.begin()
  session.bindLoginWeb(view.loginOwner,()=>view.retireOfficialWeb(),()=>view.restartOfficialWeb())
  const close=()=>{view.aboutToDisappear();session.dispose()}
  return {view,session,store,trace,renderer,close}
}

test('Harmony production guest handler accepts relative/absolute duplicate safe destinations once',async()=>{
  for(const links of [['/auth/saml2/login.php'],['https://qmplus.qmul.ac.uk/auth/saml2/login.php'],
    ['/auth/saml2/login.php','https://qmplus.qmul.ac.uk/auth/saml2/login.php']]){
    const f=await fixture('https://qmplus.qmul.ac.uk/',{links})
    try{
      await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
      assert.deepEqual(f.trace.gets,['https://qmplus.qmul.ac.uk/auth/saml2/login.php'])
      f.renderer.url='https://qmplus.qmul.ac.uk/'
      await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
      assert.equal(f.trace.gets.length,1)
    }finally{f.close()}
  }
})
test('Harmony production guest handler rejects unsafe destinations and post-credential fallback',async()=>{
  for(const link of ['https://evil.invalid/auth/saml2/login.php','/auth/saml2/login.php?next=1','/auth/saml2/login.php#retry']){
    const f=await fixture('https://qmplus.qmul.ac.uk/',{links:[link]})
    try{await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url);assert.equal(f.trace.gets.length,0)}finally{f.close()}
  }
  const f=await fixture('https://qmplus.qmul.ac.uk/',{links:['/auth/saml2/login.php']})
  try{
    assert.equal(f.view.authLedger.claimUsername('document_1'),true)
    f.view.authLedger.beginDocument()
    await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
    assert.equal(f.trace.gets.length,0)
    assert.equal(f.session.loginPresented,true)
  }finally{f.close()}
})
test('Harmony production error classification defeats a stale menu and prevents sync before begin',async()=>{
  const f=await fixture('https://qmplus.qmul.ac.uk/my/',{kind:'error'})
  try{
    await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
    assert.equal(f.view.officialPageAuthenticated,false)
    assert.equal(f.session.errorCode,'QM_ERROR_PAGE')
    await f.view.runSync()
    assert.equal(f.session.syncing,false)
    assert.equal(f.trace.gets.length,0)
    assert.equal(f.session.snapshot,null)
  }finally{f.close()}
})
test('Harmony production authenticated dashboard starts business handoff once without SSO',async()=>{
  const f=await fixture('https://qmplus.qmul.ac.uk/my/',{kind:'authenticated'})
  try{
    f.view.runSync=async()=>{f.trace.syncs++}
    await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
    await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
    assert.equal(f.trace.syncs,1)
    assert.equal(f.view.officialPageAuthenticated,true)
    assert.equal(f.trace.gets.length,0)
  }finally{f.close()}
})
test('Harmony explicit error reconnect adopts a fresh owner and fixed GET without clearing saved state',async()=>{
  const f=await fixture('https://qmplus.qmul.ac.uk/my/',{kind:'error'})
  try{
    const previous=f.view.loginOwner,saved=f.store.login,clears=f.trace.cookieClears
    await f.view.handleQMPage(f.view.authPresentationRevision,f.view.pageRevision,f.renderer.url)
    f.session.openLogin()
    assert.equal(f.session.isLoginOwnerCurrent(previous),false)
    assert.equal(f.session.isLoginOwnerCurrent(f.view.loginOwner),true)
    assert.deepEqual(f.trace.gets,['https://qmplus.qmul.ac.uk/my/'])
    assert.equal(f.trace.stops,1)
    assert.equal(f.trace.cookieClears,clears)
    assert.equal(f.store.login,saved)
  }finally{f.close()}
})
