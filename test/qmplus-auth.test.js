import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import vm from 'node:vm'

const source = readFileSync(new URL('../contracts/qmplus/qmplus-auth.js', import.meta.url), 'utf8')
const tenant = '569df091-b013-40e3-86ee-bd9cb9e25814'
const msURL = `https://login.microsoftonline.com/${tenant}/saml2?synthetic=1`
const formURL = `https://login.microsoftonline.com/${tenant}/login`
const nonce = 'nonceA123'
const account = 'student@example.org'
const secret = 'synthetic-password-not-real'

class FakeEvent { constructor(type) { this.type = type } }
class FakeElement {
  constructor({id='',name='',type='',tagName='DIV',classes=[],rect={left:0,top:0,width:100,height:30},opacity='1',textContent=''}={}) {
    Object.assign(this,{id,name,type,rect,textContent,parentElement:null,hidden:false,inert:false,
      disabled:false,readOnly:false,style:{display:'block',visibility:'visible',opacity},events:[],clicked:0})
    this.attrs={}
    this.tagName=tagName
    this.classList={contains:token=>classes.includes(token)}
  }
  getAttribute(name) { return this.attrs[name] ?? null }
  hasAttribute(name) { return Object.hasOwn(this.attrs,name) }
  closest() { for(let n=this;n;n=n.parentElement)if(n.attrs.role==='button'||['BUTTON','A'].includes(n.tagName))return n;return null }
  getBoundingClientRect() { return this.rect }
  getClientRects() { return this.rect.width && this.rect.height ? [this.rect] : [] }
  contains(other) { for(let node=other;node;node=node.parentElement)if(node===this)return true;return false }
  dispatchEvent(event) { this.events.push(event.type) }
  click() { this.clicked++;this.onClick?.() }
}
class FakeInput extends FakeElement {
  constructor(options) { super(options);this._value='' }
  set value(value) { this._value=value }
  get value() { return this._value }
  focus() { this.focused=(this.focused??0)+1;this.onFocus?.() }
}

function fixture(overrides={}) {
  const state={stage:'username',occluder:null,extra:[],chooser:null,alert:null,menu:null,
    url:new URL(msURL),readyState:'complete',...overrides}
  const body=new FakeElement({rect:{left:0,top:0,width:900,height:700}})
  body.classList={contains:name=>state.guest?.includes(name)??false}
  const form=new FakeElement({id:'i0281',rect:{left:80,top:80,width:500,height:240}})
  form.action=formURL;form.parentElement=body
  const user=new FakeInput({id:'i0116',name:'loginfmt',type:'email',rect:{left:100,top:100,width:348,height:36}})
  const pass=new FakeInput({id:'i0118',name:'passwd',type:'password',rect:{left:100,top:100,width:10,height:13},opacity:'0'})
  const submit=new FakeInput({id:'idSIButton9',type:'submit',rect:{left:100,top:160,width:108,height:32}})
  for(const item of [user,pass,submit])item.parentElement=form
  const displayName=new FakeElement({id:'displayName',rect:{left:100,top:45,width:348,height:28},textContent:account})
  displayName.parentElement=form
  submit.onClick=()=>{
    if(state.stage==='username'){
      state.stage='password';pass.rect={left:100,top:100,width:348,height:36};pass.style.opacity='1'
    } else state.stage='submitted'
  }
  const listeners=new Map()
  const window={
    addEventListener(name,callback){listeners.set(name,callback)},
    removeEventListener(name,callback){if(listeners.get(name)===callback)listeners.delete(name)},
    dispatchEvent(event){listeners.get(event.type)?.(event)}
  };window.top=window;window.getComputedStyle=node=>node.style
  const document={body,readyState:state.readyState,defaultView:window,
    querySelectorAll(selector) {
      const inputs=state.stage==='username'?[user,pass,submit]:[pass,submit]
      if(selector==='form#i0281')return [form]
      if(selector==='input#idSIButton9[type="submit"]')return [submit]
      if(selector==='input#i0116[name="loginfmt"][type="email"]')return inputs.filter(n=>n===user)
      if(selector==='input#i0118[name="passwd"][type="password"]')return inputs.filter(n=>n===pass)
      if(selector==='#i0116')return inputs.filter(n=>n===user)
      if(selector==='#displayName')return state.stage==='username'?[]:[displayName]
      if(selector==='#tilesHolder')return state.chooser?[state.chooser]:[]
      if(selector==='.usermenu .userbutton')return state.menu?[state.menu]:[]
      if(selector.startsWith('input, textarea,'))return [...inputs,...state.extra,...(state.alert?[state.alert]:[])]
      throw new Error(`unhandled fake selector: ${selector}`)
    },
    elementFromPoint(x,y) {
      if(state.occluder)return state.occluder
      if(state.stage==='chooser')return state.chooserRows?.find(n=>n.style.opacity!=='0'&&x>=n.rect.left&&x<=n.rect.left+n.rect.width&&y>=n.rect.top&&y<=n.rect.top+n.rect.height) ?? state.chooser
      const inputs=state.stage==='username'?[user,pass,submit]:[pass,submit]
      const nodes=[...inputs,displayName,...state.extra]
      return nodes.find(node=>node.style.opacity!=='0'&&x>=node.rect.left&&x<=node.rect.left+node.rect.width&&
        y>=node.rect.top&&y<=node.rect.top+node.rect.height)??form
    }}
  const location={href:state.url.href,origin:state.url.origin}
  const context=vm.createContext({URL,window,document,location,HTMLInputElement:FakeInput,Event:FakeEvent,clearTimeout:()=>{}})
  if(!overrides.skipInstall){const installCode=vm.runInContext(source,context);assert.equal(installCode,'AUTH_INSTALLED')}
  return {auth:context.WTSQmAuth,context,state,form,user,pass,submit,displayName,document,window,location,
    setURL(url){const parsed=new URL(url);location.href=parsed.href;location.origin=parsed.origin}}
}

function inspect(f, hint=account, doc=nonce) { return JSON.parse(JSON.stringify(f.auth.inspect(doc,hint))) }

function chooserFixture(options={}) {
  const f=fixture({stage:'chooser'})
  const holder=new FakeElement({id:'tilesHolder',rect:{left:0,top:0,width:500,height:400}})
  holder.parentElement=f.document.body
  const row=new FakeElement({classes:['table'],rect:{left:50,top:50,width:400,height:80}})
  row.attrs={role:'button','data-test-id':account};row.parentElement=holder
  const content=new FakeElement({classes:['table-cell','text-left','content'],textContent:account,
    rect:{left:100,top:60,width:280,height:30}});content.parentElement=row
  row.querySelectorAll=selector=>selector==='div.table-cell.text-left.content'?[content]:[]
  f.submit.style.opacity='0';f.submit.rect.width=0
  f.state.chooser=holder;f.state.chooserRows=[row]
  holder.querySelectorAll=selector=>selector==='div.table[role="button"][data-test-id]'?f.state.chooserRows:[]
  row.onClick=()=>{
    if(options.remainChooser)return
    holder.style.opacity='0'
    f.state.stage='password';f.pass.rect={left:100,top:100,width:348,height:36};f.pass.style.opacity='1'
    f.submit.style.opacity='1';f.submit.rect.width=108
  }
  return {...f,holder,row,content}
}

test('exact official cached-account tile is selected without a password, then independently confirms the same-document password identity',()=>{
  const f=chooserFixture()
  const step=inspect(f);assertFixed(step);assert.equal(step.stage,'account');assert.equal(step.accountMatch,true)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account,password:secret}),'REJECTED')
  assert.equal(f.row.clicked,0)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
  assert.equal(f.row.clicked,1);assert.equal(f.user.value,'');assert.equal(f.pass.value,'')
  const password=inspect(f);assert.equal(password.stage,'password');assert.equal(password.reason,'READY')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'PASSWORD_SUBMITTED')
  assert.equal(f.pass.value,secret);assert.equal(f.submit.clicked,1)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  assert.equal(f.submit.clicked,1)
})

test('account tile requires both exact identities and never accepts another account, duplicate, menu, MFA or missing authorization hint',()=>{
  const absent=chooserFixture();const prompt=inspect(absent,'');assertFixed(prompt)
  assert.equal(prompt.stage,'account');assert.equal(prompt.reason,'ACCOUNT_HINT_REQUIRED');assert.equal(prompt.accountMatch,false)
  for(const variant of ['attribute','display','duplicate','menu','disabled','mfa','alert','unknown-shape']) {
    const f=chooserFixture()
    if(variant==='attribute')f.row.attrs['data-test-id']='other@example.org'
    if(variant==='display')f.content.textContent='student@example.org.evil'
    if(variant==='duplicate'){
      const duplicate=new FakeElement({classes:['table'],rect:f.row.rect});duplicate.attrs={...f.row.attrs};
      duplicate.parentElement=f.holder;duplicate.querySelectorAll=f.row.querySelectorAll;f.state.chooserRows.push(duplicate)
    }
    if(variant==='menu'){const menu=new FakeElement();menu.attrs.role='button';menu.parentElement=f.row;f.state.occluder=menu}
    if(variant==='disabled')f.row.attrs['aria-disabled']='true'
    if(variant==='mfa')f.state.extra.push(new FakeInput({id:'otp',type:'text'}))
    if(variant==='alert')f.state.alert=new FakeElement()
    if(variant==='unknown-shape')f.row.classList={contains:()=>false}
    assert.equal(inspect(f).stage,'manual',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED',variant)
    assert.equal(f.row.clicked,0);assert.equal(f.pass.value,'')
  }
})

test('account selection is claimed once and a different document or identity cannot reuse its password proof',()=>{
  const pending=chooserFixture({remainChooser:true})
  assert.equal(inspect(pending).stage,'account')
  assert.equal(pending.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
  assert.equal(inspect(pending).reason,'ALREADY_ATTEMPTED')
  assert.equal(pending.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED')
  assert.equal(pending.row.clicked,1)
  const f=chooserFixture();inspect(f)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
  f.displayName.textContent='other@example.org'
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  f.displayName.textContent=account
  assert.equal(f.auth.fillAndSubmit({document:'otherNonce123',stage:'password',account,password:secret}),'STALE_DOCUMENT')
  f.setURL(`${formURL}?synthetic=changed`)
  assert.equal(inspect(f).reason,'STALE_DOCUMENT')
  assert.equal(f.pass.value,'')
})
function assertFixed(result) {
  assert.deepEqual(Object.keys(result).sort(),['accountMatch','document','reason','stage','v'])
  assert.equal(result.v,1)
  assert.equal(result.document,nonce)
  assert.doesNotMatch(JSON.stringify(result),/student@|synthetic-password|saml2|login\.microsoftonline/)
}

function desktopBootstrap(f,{invoke=()=>Promise.resolve(false),revision=1}={}) {
  const rust=readFileSync(new URL('../src-tauri/src/qmplus.rs',import.meta.url),'utf8')
  const start=rust.indexOf('(()=>{{const install={AUTH_SCRIPT};')
  assert.ok(start>=0)
  const template=rust.slice(start,rust.indexOf('"#,',start))
  const script=template.replaceAll('{AUTH_SCRIPT}',source).replaceAll('{revision}',String(revision))
    .replaceAll('{nonce}',JSON.stringify(nonce)).replaceAll('{url}',JSON.stringify(msURL))
    .replaceAll('{account}',JSON.stringify(account)).replaceAll('{{','{').replaceAll('}}','}')
  const reports=[],timers=new Map();let nextTimer=0
  f.window.__TAURI_INTERNALS__={invoke:(command,args)=>{reports.push({command,args});return invoke(command,args)}}
  f.context.setTimeout=(callback,delay)=>{timers.set(++nextTimer,{callback,delay});return nextTimer}
  f.context.clearTimeout=id=>timers.delete(id)
  vm.runInContext(script,f.context)
  async function settle(){for(let i=0;i<5;i++)await Promise.resolve()}
  return {reports,timers,
    settle,
    active:doc=>f.context.WTSQmAuthPollActive(doc),
    async next(){await settle();const [id,timer]=timers.entries().next().value??[];assert.ok(timer);timers.delete(id);await timer.callback();await settle();return timer.delay}}
}

test('desktop bootstrap propagates the canonical install return and inspects without sending a password',()=>{
  const f=fixture({skipInstall:true})
  const {reports}=desktopBootstrap(f)
  assert.equal(reports.length,1)
  assert.equal(reports[0].command,'accept_qmplus_auth')
  assert.equal(reports[0].args.report.stage,'username')
  assert.equal(reports[0].args.report.reason,'READY')
  assert.doesNotMatch(JSON.stringify(reports),/student@|password|SAMLRequest/)
})

test('desktop layout waits once while hidden and at most eight more times after asking to show the same window',async()=>{
  const f=fixture({skipInstall:true});f.submit.rect.width=0
  const bridge=desktopBootstrap(f)
  for(let i=0;i<7;i++)assert.equal(await bridge.next(),250)
  assert.equal(bridge.reports.length,1)
  assert.equal(bridge.reports[0].args.report.stage,'loading')
  assert.equal(bridge.reports[0].args.report.reason,'FORM_UNTRUSTED')
  assert.equal(f.submit.clicked,0)
  for(let i=0;i<9;i++)await bridge.next()
  assert.equal(bridge.reports.at(-1).args.report.stage,'manual')
  assert.equal(bridge.timers.size,0)
  assert.equal(bridge.active(nonce),false)
  assert.equal(f.user.value,'')
  const ready=fixture({skipInstall:true});ready.submit.rect.width=0
  const visible=desktopBootstrap(ready)
  for(let i=0;i<7;i++)await visible.next()
  ready.submit.rect.width=108
  await visible.next()
  assert.equal(visible.reports.at(-1).args.report.stage,'username')
  assert.equal(visible.reports.at(-1).args.report.reason,'READY')
})

test('desktop poll rejects a stale native owner and clears timers on background, pagehide or changed URL',async()=>{
  const stale=fixture({skipInstall:true})
  const rejected=desktopBootstrap(stale,{revision:7,invoke:(_command,args)=>
    args.revision===8?Promise.resolve(false):Promise.reject(new Error('fixed stale owner'))})
  await rejected.settle()
  assert.equal(rejected.active(nonce),false)
  assert.equal(rejected.active('nonceB456'),false)
  assert.equal(rejected.timers.size,0)
  for(const event of ['pagehide','wts-qm-auth-stop','changedURL']){
    const f=fixture({skipInstall:true}),bridge=desktopBootstrap(f)
    await bridge.settle()
    assert.equal(bridge.active(nonce),true)
    assert.equal(bridge.active('nonceB456'),false)
    if(event==='changedURL'){f.setURL(formURL);await bridge.next()}
    else f.window.dispatchEvent(new FakeEvent(event))
    assert.equal(bridge.active(nonce),false,event)
    assert.equal(bridge.timers.size,0,event)
    assert.equal(f.submit.clicked,0,event)
    assert.doesNotMatch(JSON.stringify(bridge.reports),/student@|synthetic-password|SAMLRequest/)
  }
})

test('desktop empty chooser waits only on native true and its finite budget never clicks or fills',async()=>{
  function emptyChooser(){
    const f=fixture({skipInstall:true,stage:'chooser'})
    f.submit.style.opacity='0';f.submit.rect.width=0
    const holder=new FakeElement({id:'tilesHolder',rect:{left:0,top:0,width:500,height:400}})
    holder.parentElement=f.document.body;holder.querySelectorAll=()=>[];f.state.chooser=holder
    return f
  }
  for(const approval of [false,undefined,'true',{settling:true}]){
    const f=emptyChooser(),bridge=desktopBootstrap(f,{invoke:()=>Promise.resolve(approval)})
    await bridge.settle()
    assert.equal(bridge.reports[0].args.report.reason,'ACCOUNT_CHOOSER')
    assert.equal(bridge.reports[0].args.report.stage,'manual')
    assert.equal(bridge.timers.size,0)
    assert.equal(bridge.active(nonce),false)
    assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(f.submit.clicked,0)
  }
  const f=emptyChooser();let polls=0
  const bridge=desktopBootstrap(f,{invoke:(_command,args)=>{
    assert.equal(args.report.stage,'manual');assert.equal(args.report.reason,'ACCOUNT_CHOOSER')
    return Promise.resolve(++polls<=12)
  }})
  await bridge.settle()
  for(let i=0;i<12;i++)assert.equal(await bridge.next(),250)
  assert.equal(polls,13)
  assert.equal(bridge.timers.size,0);assert.equal(bridge.active(nonce),false)
  assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(f.submit.clicked,0)
  assert.doesNotMatch(JSON.stringify(bridge.reports),/student@|synthetic-password|SAMLRequest/)
})

test('desktop pending native approval cannot resume after pagehide or a changed URL',async()=>{
  for(const event of ['pagehide','wts-qm-auth-stop','changedURL']){
    const f=fixture({skipInstall:true});let resolveNative
    const pending=new Promise(resolve=>{resolveNative=resolve})
    const bridge=desktopBootstrap(f,{invoke:()=>pending})
    assert.equal(bridge.timers.size,0)
    if(event==='changedURL')f.setURL(formURL)
    else f.window.dispatchEvent(new FakeEvent(event))
    resolveNative(true)
    await bridge.settle()
    assert.equal(bridge.active(nonce),false,event)
    assert.equal(bridge.timers.size,0,event)
    assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(f.submit.clicked,0,event)
  }
})

test('only the observed official sibling placeholder may be focused before strict hit revalidation',()=>{
  const f=fixture()
  const container=new FakeElement()
  container.classList={contains:name=>name==='placeholderContainer'};container.parentElement=f.form
  f.user.parentElement=container
  const hintParent=new FakeElement()
  hintParent.classList={contains:name=>name==='placeholderInnerContainer'};hintParent.parentElement=container
  const hint=new FakeElement()
  hint.classList={contains:name=>name==='placeholder'};hint.attrs['aria-hidden']='true';hint.parentElement=hintParent
  f.state.occluder=hint
  // Submit and input occupy different hit points; only the input has a hint.
  const hit=f.document.elementFromPoint.bind(f.document)
  f.document.elementFromPoint=(x,y)=>y>=160?f.submit:hit(x,y)
  f.user.onFocus=()=>{f.state.occluder=null}
  assert.equal(inspect(f).stage,'username')
  assert.equal(f.user.focused,1)
  assert.equal(f.user.value,'')
  assert.equal(f.submit.clicked,0)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  // Microsoft may keep a hint visible even after focus until text changes.
  const persistent=fixture()
  const pContainer=new FakeElement();pContainer.classList={contains:n=>n==='placeholderContainer'};pContainer.parentElement=persistent.form
  persistent.user.parentElement=pContainer
  const pParent=new FakeElement();pParent.classList={contains:n=>n==='placeholderInnerContainer'};pParent.parentElement=pContainer
  const pHint=new FakeElement();pHint.classList={contains:n=>n==='placeholder'};pHint.attrs['aria-hidden']='true';pHint.parentElement=pParent
  persistent.state.occluder=pHint
  const originalHit=persistent.document.elementFromPoint.bind(persistent.document)
  persistent.document.elementFromPoint=(x,y)=>y>=160?persistent.submit:originalHit(x,y)
  assert.equal(inspect(persistent).stage,'username')
  assert.equal(persistent.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  assert.equal(persistent.submit.clicked,1)
  const bad=fixture()
  bad.state.occluder=new FakeElement()
  const original=bad.document.elementFromPoint.bind(bad.document)
  bad.document.elementFromPoint=(x,y)=>y>=160?bad.submit:original(x,y)
  assert.equal(inspect(bad).stage,'manual')
  assert.equal(bad.user.focused,undefined)
  assert.equal(bad.user.value,'')
})

test('focusing an owned hint cannot authorize a field that becomes uneditable, invisible or changes form action',()=>{
  for(const change of ['disabled','readOnly','invisible','action']){
    const f=fixture()
    const container=new FakeElement();container.classList={contains:n=>n==='placeholderContainer'};container.parentElement=f.form
    f.user.parentElement=container
    const parent=new FakeElement();parent.classList={contains:n=>n==='placeholderInnerContainer'};parent.parentElement=container
    const hint=new FakeElement();hint.classList={contains:n=>n==='placeholder'};hint.attrs['aria-hidden']='true';hint.parentElement=parent
    const hit=f.document.elementFromPoint.bind(f.document)
    f.state.occluder=hint;f.document.elementFromPoint=(x,y)=>y>=160?f.submit:hit(x,y)
    f.user.onFocus=()=>{
      if(change==='invisible')f.user.style.opacity='0'
      else if(change==='action')f.form.action='https://evil.test/login'
      else f.user[change]=true
    }
    assert.equal(inspect(f).stage,'manual',change)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED',change)
    assert.equal(f.user.value,'',change)
    assert.equal(f.submit.clicked,0,change)
  }
})

test('confirmed username then matching password may submit once per stage without exporting secrets',()=>{
  const f=fixture()
  const first=inspect(f)
  assertFixed(first);assert.equal(first.stage,'username');assert.equal(first.accountMatch,false)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  assert.equal(f.user.value,account);assert.deepEqual(f.user.events,['input','change'])
  assert.equal(f.submit.clicked,1)
  const second=inspect(f)
  assertFixed(second);assert.equal(second.stage,'password');assert.equal(second.accountMatch,true)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'PASSWORD_SUBMITTED')
  assert.equal(f.pass.value,secret);assert.equal(f.submit.clicked,2)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  assert.equal(f.submit.clicked,2)
})

test('a stage never retries after the first click, including when the page does not advance',()=>{
  const f=fixture();f.submit.onClick=()=>{}
  assert.equal(inspect(f).stage,'username')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  assert.equal(inspect(f).reason,'ALREADY_ATTEMPTED')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  assert.equal(f.submit.clicked,1)
})

test('preloaded tiny transparent password never substitutes for visible username; honeypots stop fill',()=>{
  const f=fixture()
  assert.equal(inspect(f).stage,'username')
  assert.equal(f.pass.rect.width,10);assert.equal(f.pass.style.opacity,'0')
  const honeypot=new FakeInput({id:'other',type:'text',rect:{left:500,top:110,width:180,height:30},opacity:'0'})
  honeypot.parentElement=f.form;f.state.extra.push(honeypot)
  assert.equal(inspect(f).stage,'username')
  honeypot.style.opacity='1'
  assert.equal(inspect(f).stage,'manual')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  assert.equal(f.submit.clicked,0)
})

test('account chooser, MFA-like inputs, checkbox, alert, dialog and occlusion require manual action',()=>{
  for(const variant of ['chooser','otp','checkbox','alert','dialog','occluded']){
    const f=fixture()
    if(variant==='chooser')f.state.chooser=new FakeElement({id:'tilesHolder'})
    if(variant==='otp'||variant==='checkbox'){
      const item=new FakeInput({id:variant,type:variant==='otp'?'text':'checkbox',
        rect:{left:500,top:100,width:170,height:30}})
      item.parentElement=f.form;f.state.extra.push(item)
    }
    if(variant==='alert'||variant==='dialog'){
      f.state.alert=new FakeElement({rect:{left:500,top:100,width:170,height:30}})
      f.state.alert.attrs.role=variant
      f.state.alert.parentElement=f.form
    }
    if(variant==='occluded')f.state.occluder=new FakeElement()
    const state=inspect(f)
    assert.equal(state.stage,'manual',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED',variant)
    assert.equal(f.submit.clicked,0)
  }
})

test('read-only, disabled, hidden ancestors, duplicate forms and loading documents never submit',()=>{
  for(const state of ['readOnly','disabled','hidden','duplicate']){
    const f=fixture()
    if(state==='readOnly')f.user.readOnly=true
    if(state==='disabled')f.user.disabled=true
    if(state==='hidden')f.form.style.opacity='0'
    if(state==='duplicate'){
      const query=f.document.querySelectorAll.bind(f.document)
      f.document.querySelectorAll=selector=>selector==='form#i0281'?[f.form,f.form]:query(selector)
    }
    assert.equal(inspect(f).stage,'manual',state)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED',state)
    assert.equal(f.submit.clicked,0)
  }
  const loading=fixture({readyState:'loading'})
  assert.equal(inspect(loading).stage,'loading')
  assert.equal(loading.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
})

test('wrong form action, host, path, frame, document nonce and changed URL never fill',()=>{
  for(const formAction of ['https://evil.test/login',`https://login.microsoftonline.com/${tenant}/other`]){
    const f=fixture();f.form.action=formAction
    assert.equal(inspect(f).stage,'manual');assert.equal(f.submit.clicked,0)
  }
  for(const changed of ['https://login.microsoftonline.com.evil.test/'+tenant+'/saml2',
    `http://login.microsoftonline.com/${tenant}/saml2`,
    `https://login.microsoftonline.com/other/saml2`]){
    const f=fixture();f.setURL(changed)
    assert.equal(inspect(f).stage,'manual')
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  }
  const frame=fixture();frame.window.top={}
  assert.equal(inspect(frame).stage,'manual')
  const stale=fixture();assert.equal(inspect(stale).stage,'username')
  assert.equal(stale.auth.fillAndSubmit({document:'nonceB456',stage:'username',account}),'STALE_DOCUMENT')
  stale.setURL(`https://login.microsoftonline.com/${tenant}/login`)
  assert.equal(stale.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  stale.setURL('https://other.test/login')
  assert.equal(stale.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  assert.equal(stale.submit.clicked,0)
})

test('prefilled other account or an OS-managed password is never overwritten',()=>{
  const different=fixture();different.user.value='other@example.org'
  assert.equal(inspect(different).reason,'ACCOUNT_MISMATCH')
  assert.equal(different.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  const existing=fixture();inspect(existing)
  assert.equal(existing.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  existing.pass.value='system-managed-password'
  assert.equal(inspect(existing).stage,'manual')
  assert.equal(existing.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  assert.equal(existing.pass.value,'system-managed-password')
})

test('password stage refuses account mismatch and manual username entry',()=>{
  const manual=fixture({stage:'password'})
  manual.pass.rect={left:100,top:100,width:348,height:36};manual.pass.style.opacity='1'
  assert.equal(inspect(manual).stage,'password')
  assert.equal(inspect(manual).reason,'USERNAME_NOT_SUBMITTED')
  assert.equal(manual.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  const mismatch=fixture();inspect(mismatch)
  assert.equal(mismatch.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  mismatch.displayName.textContent='other@example.org'
  assert.equal(inspect(mismatch).stage,'manual')
  assert.equal(mismatch.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  assert.equal(mismatch.submit.clicked,1)
})

test('both visible known fields and an unverified password-stage leftover username are manual',()=>{
  const f=fixture()
  f.pass.rect={left:500,top:100,width:348,height:36};f.pass.style.opacity='1'
  assert.equal(inspect(f).stage,'manual')
  const leftover=fixture();inspect(leftover)
  assert.equal(leftover.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  leftover.document.querySelectorAll=(original=>selector=>selector==='#i0116'?[leftover.user]:original(selector))(
    leftover.document.querySelectorAll.bind(leftover.document))
  assert.equal(inspect(leftover).stage,'manual')
})

test('QMplus authenticated state needs exact origin, non-guest body and user menu',()=>{
  const f=fixture();f.setURL('https://qmplus.qmul.ac.uk/my/')
  f.state.menu=new FakeElement({rect:{left:100,top:30,width:100,height:30}})
  assert.equal(inspect(f).stage,'authenticated')
  f.state.guest=['guestuser'];assert.equal(inspect(f).stage,'manual')
  f.setURL('https://qmplus.qmul.ac.uk.evil.test/my/');assert.equal(inspect(f).stage,'manual')
})

test('shared auth script stays offline, immutable and separate from business sync',()=>{
  const f=fixture()
  assert.equal(Object.isFrozen(f.auth),true)
  assert.equal(vm.runInContext(source,vm.createContext({WTSQmAuth:{foreign:true}})),'AUTH_CONFLICT')
  assert.match(source,/Object\.defineProperty\(globalThis, 'WTSQmAuth'/)
  assert.doesNotMatch(source,/\bfetch\s*\(|XMLHttpRequest|localStorage|sessionStorage|document\.cookie|console\.(?:log|info)|WTSQmSync/)
  assert.doesNotMatch(source,/startattempt\.php|submit\.php|keepSignedIn|rememberMe/)
})
