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

test('Apple identity layout diagnostics remain DEBUG opt-in and never read secret or URL surfaces',()=>{
  const swift=readFileSync(new URL('../native/apple/Sources/Shared/QMplusAutofillPipeline.swift',import.meta.url),'utf8').replace(/\r\n/g,'\n')
  const debug=swift.slice(swift.indexOf('    #if DEBUG\n    private static let qaLayoutLogger'),swift.indexOf('    #endif\n    func submit'))
  assert.ok(debug.length>0)
  assert.match(debug,/environment\["WTS_QMPLUS_AUTH_TRACE"\] == "1"/)
  assert.match(debug,/isInspectableMicrosoftDocument\(browser.url\)/)
  assert.match(debug,/state.stage == \.manual && state.reason == \.mismatch/)
  assert.match(swift,/#if DEBUG\nimport OSLog\n#endif/)
  assert.match(debug,/Logger\(subsystem: "com\.nemoyu\.wheretostudy\.qa\.qm-auth", category: "layout"\)/)
  assert.match(debug,/qaLayoutLogger\.notice\("WTS_QM_IDENTITY_LAYOUT \\\(text, privacy: \.public\)/)
  const script=debug.match(/static let identityLayoutTraceScript = """\n([\s\S]*?)\n        """/)?.[1]
  assert.ok(script)
  assert.doesNotMatch(script,/\.value\b|\bcookies?\b|\blocation\b|\bURL\b|innerHTML|outerHTML|fetch\s*\(|XMLHttpRequest|localStorage|sessionStorage|\.click\s*\(|\.focus\s*\(|setAttribute\s*\(/)
  assert.doesNotMatch(script,/textContent\s*[,}]|[{,]\s*(?:identity|account|password|text|value|url|html)\s*:/i)
})

test('Apple mismatch diagnostics reduce synthetic noninteractive identity to bounded safe metadata',()=>{
  const swift=readFileSync(new URL('../native/apple/Sources/Shared/QMplusAutofillPipeline.swift',import.meta.url),'utf8').replace(/\r\n/g,'\n')
  const script=swift.match(/static let identityLayoutTraceScript = """\n([\s\S]*?)\n        """/)?.[1]
  const f=fixture({stage:'password'})
  f.displayName.style.pointerEvents='none'
  f.form.style.display='SYNTHETIC_PRIVATE_STYLE'
  const hit=f.document.elementFromPoint.bind(f.document)
  f.document.elementFromPoint=(x,y)=>y<80?f.form:hit(x,y)
  for(const node of [f.user,f.pass,f.submit])Object.defineProperty(node,'value',{get(){throw Error('secret read forbidden')}})
  Object.defineProperty(f.document,'cookie',{get(){throw Error('cookie read forbidden')}})
  const output=vm.runInNewContext(`(function(){${script}})()`,{
    document:f.document,window:f.window,accountHint:account,innerWidth:900,innerHeight:700,
  })
  const metadata=JSON.parse(output)
  assert.deepEqual(Object.keys(metadata).sort(),['ancestors','forms','identities','identityHit','identityMatches','passwords','ready','submitHit','submits','usernames','viewport'])
  assert.equal(metadata.identityMatches,true)
  assert.equal(metadata.identityHit,'parent')
  assert.equal(metadata.submitHit,'self')
  assert.equal(metadata.ancestors[0].style.pointerEvents,'none')
  assert.equal(metadata.ancestors[1].style.display,'other')
  assert.ok(metadata.ancestors.length<=12)
  assert.doesNotMatch(output,/student@|synthetic-password|SYNTHETIC_PRIVATE_STYLE|https?:|textContent|cookie/)
})

class FakeEvent { constructor(type) { this.type = type } }
class FakeElement {
  constructor({id='',name='',type='',tagName='DIV',classes=[],rect={left:0,top:0,width:100,height:30},opacity='1',textContent=''}={}) {
    Object.assign(this,{id,name,type,rect,textContent,parentElement:null,hidden:false,inert:false,
      disabled:false,readOnly:false,style:{display:'block',visibility:'visible',opacity},events:[],clicked:0})
    this.attrs={}
    this.tagName=tagName
    this.classList={contains:token=>classes.includes(token)}
  }
  get textContent() { return (this._text??'')+(this.children??[]).map(node=>node.textContent).join('') }
  set textContent(value) { this._text=value;this.children=[] }
  get childElementCount() { return this.children.length }
  appendChild(child) { this.children.push(child);child.parentElement=this;return child }
  querySelectorAll(selector) {
    if(selector==='*')return this.children.flatMap(node=>[node,...node.querySelectorAll('*')])
    throw new Error(`unhandled element selector: ${selector}`)
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
    querySelector(selector) {
      if(selector==='[data-rel="fatalerror"], #region-main .errorbox .errorcode, main .errorbox .errorcode')return state.fatalMarker??null
      return this.querySelectorAll(selector)[0]??null
    },
    querySelectorAll(selector) {
      const inputs=state.stage==='username'?[user,pass,submit]:state.stage==='continue'?[submit,...(state.continueInputs??[])]:[pass,submit]
      if(selector==='form#i0281')return [form]
      if(selector==='input#idSIButton9[type="submit"]')return [submit]
      if(selector==='input#i0116[name="loginfmt"][type="email"]')return inputs.filter(n=>n===user)
      if(selector==='input#i0118[name="passwd"][type="password"]')return inputs.filter(n=>n===pass)
      if(selector==='#i0116')return inputs.filter(n=>n===user)
      if(selector==='#i0116, #i0118')return inputs.filter(n=>n===user||n===pass)
      if(selector==='#displayName')return state.stage==='username'?[]:[displayName]
      if(selector==='#kmsiTitle')return state.kmsiTitle?[state.kmsiTitle]:[]
      if(selector==='input#idBtn_Back[type="button"]')return state.back?[state.back]:[]
      if(selector==='input#KmsiCheckboxField[type="checkbox"]')return state.kmsiCheckbox?[state.kmsiCheckbox]:[]
      if(selector==='label[for="KmsiCheckboxField"]')return state.kmsiLabel?[state.kmsiLabel]:[]
      if(selector==='iframe[title], input[aria-label], [role="group"][aria-label], img[alt]')return state.extra.filter(n=>
        (n.tagName==='IFRAME'&&n.attrs.title)||(n instanceof FakeInput&&n.attrs['aria-label'])||
        (n.attrs.role==='group'&&n.attrs['aria-label'])||(n.tagName==='IMG'&&n.attrs.alt))
      if(selector==='input[autocomplete="one-time-code"], input[name="otc"]')return state.extra.filter(n=>
        n instanceof FakeInput&&(n.attrs.autocomplete==='one-time-code'||n.name==='otc'))
      if(selector==='h1, h2, [role="heading"]')return state.extra.filter(n=>['H1','H2'].includes(n.tagName)||n.attrs.role==='heading')
      if(selector==='#idDiv_SAOTCS_Title')return state.extra.filter(n=>n.id==='idDiv_SAOTCS_Title')
      if(selector==='button, select, [role="button"]')return state.extra.filter(n=>['BUTTON','SELECT'].includes(n.tagName)||n.attrs.role==='button')
      if(selector==='#tilesHolder')return state.chooser?[state.chooser]:[]
      if(selector==='.usermenu .userbutton')return state.menu?[state.menu]:[]
      if(selector==='.moodle-dialogue-exception h5, .modal.show .modal-title, .modal[aria-hidden="false"] .modal-title, [role="dialog"][aria-modal="true"] .modal-title')return state.errorTitles??[]
      if(selector.startsWith('input, textarea,'))return [...inputs,...state.extra,...(state.alert?[state.alert]:[])]
      throw new Error(`unhandled fake selector: ${selector}`)
    },
    elementFromPoint(x,y) {
      if(state.occluder)return state.occluder
      if(state.stage==='chooser')return state.chooserRows?.find(n=>n.style.opacity!=='0'&&x>=n.rect.left&&x<=n.rect.left+n.rect.width&&y>=n.rect.top&&y<=n.rect.top+n.rect.height) ?? state.chooser
      const inputs=state.stage==='username'?[user,pass,submit]:state.stage==='continue'?[submit,...(state.continueInputs??[])]:[pass,submit]
      const nodes=[...inputs,displayName,...state.extra,...(state.kmsiTitle?[state.kmsiTitle]:[])]
      return nodes.find(node=>node.style.opacity!=='0'&&x>=node.rect.left&&x<=node.rect.left+node.rect.width&&
        y>=node.rect.top&&y<=node.rect.top+node.rect.height)??form
    }}
  const location={href:state.url.href,origin:state.url.origin}
  const context=vm.createContext({URL,window,document,location,HTMLInputElement:FakeInput,Event:FakeEvent,clearTimeout:()=>{}})
  if(!overrides.skipInstall){const installCode=vm.runInContext(source,context);assert.equal(installCode,'AUTH_INSTALLED')}
  return {auth:context.WTSQmAuth,context,state,form,user,pass,submit,displayName,document,window,location,
    setURL(url){const parsed=new URL(url);location.href=parsed.href;location.origin=parsed.origin}}
}

function inspect(f, hint=account, doc=nonce, identityAcknowledged=false) {
  return JSON.parse(JSON.stringify(f.auth.inspect(doc,hint,identityAcknowledged)))
}

function continuationFixture({checkbox=false,url=msURL}={}) {
  const f=fixture({stage:'continue',url:new URL(url)})
  f.form.action='https://login.microsoftonline.com/kmsi'
  const title=new FakeElement({id:'kmsiTitle',textContent:'Stay signed in?',rect:{left:100,top:85,width:280,height:32}})
  const back=new FakeInput({id:'idBtn_Back',type:'button',rect:{left:250,top:160,width:108,height:32}})
  for(const item of [title,back])item.parentElement=f.form
  f.state.kmsiTitle=title;f.state.back=back;f.state.continueInputs=[back]
  f.submit.onClick=()=>{}
  if(checkbox){
    const field=new FakeInput({id:'KmsiCheckboxField',type:'checkbox',rect:{left:100,top:130,width:20,height:20}})
    const label=new FakeElement({tagName:'LABEL',textContent:"Don't show this again",rect:{left:130,top:130,width:230,height:20}})
    field.parentElement=f.form;label.parentElement=f.form;field.checked=false
    f.state.kmsiCheckbox=field;f.state.kmsiLabel=label;f.state.continueInputs.push(field)
  }
  return {...f,title,back}
}

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

function mixedChooserFixture() {
  const f=chooserFixture()
  f.row.rect.height=112;f.content.rect.height=84;f.content.textContent=''
  const name=new FakeElement({textContent:'Synthetic Display Name',rect:{left:100,top:60,width:280,height:22}})
  const emailLine=new FakeElement({rect:{left:100,top:86,width:280,height:22}})
  const email=new FakeElement({tagName:'SMALL',textContent:account,rect:{left:100,top:86,width:280,height:22}})
  emailLine.appendChild(email)
  const statusLine=new FakeElement({rect:{left:100,top:112,width:280,height:20}})
  const status=new FakeElement({tagName:'SMALL',textContent:'Signed in',rect:{left:100,top:112,width:280,height:20}})
  statusLine.appendChild(status)
  for(const node of [name,emailLine,statusLine])f.content.appendChild(node)
  const menu=new FakeElement({rect:{left:410,top:82,width:24,height:24}})
  menu.attrs={role:'button','data-test-id':account+'-menu-dots'};menu.parentElement=f.holder
  const originalHit=f.document.elementFromPoint.bind(f.document)
  f.document.elementFromPoint=(x,y)=>{
    if(f.state.occluder)return f.state.occluder
    if(f.state.stage!=='chooser')return originalHit(x,y)
    if(f.state.menuAtRowCenter&&x===f.row.rect.left+f.row.rect.width/2&&y===f.row.rect.top+f.row.rect.height/2)return menu
    return [menu,email,name,status].find(node=>!node.hidden&&node.style.opacity!=='0'&&
      x>=node.rect.left&&x<=node.rect.left+node.rect.width&&y>=node.rect.top&&y<=node.rect.top+node.rect.height)??originalHit(x,y)
  }
  return {...f,name,emailLine,email,statusLine,status,menu}
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
  for(const variant of ['attribute','display','duplicate','disabled','mfa','alert','unknown-shape']) {
    const f=chooserFixture()
    if(variant==='attribute')f.row.attrs['data-test-id']='other@example.org'
    if(variant==='display')f.content.textContent='student@example.org.evil'
    if(variant==='duplicate'){
      const duplicate=new FakeElement({classes:['table'],rect:f.row.rect});duplicate.attrs={...f.row.attrs};
      duplicate.parentElement=f.holder;duplicate.querySelectorAll=f.row.querySelectorAll;f.state.chooserRows.push(duplicate)
    }
    if(variant==='disabled')f.row.attrs['aria-disabled']='true'
    if(variant==='mfa')f.state.extra.push(new FakeInput({id:'otp',type:'text'}))
    if(variant==='alert')f.state.alert=new FakeElement()
    if(variant==='unknown-shape')f.row.classList={contains:()=>false}
    assert.equal(inspect(f).stage,'manual',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED',variant)
    assert.equal(f.row.clicked,0);assert.equal(f.pass.value,'')
  }
})

test('an explicitly pending picker waits without selecting until its async tiles are available',()=>{
  const f=chooserFixture()
  f.holder.attrs['data-test-asynctilesloaded']='false'
  f.state.chooserRows=[]
  let state=inspect(f);assertFixed(state)
  assert.equal(state.stage,'loading');assert.equal(state.reason,'LOADING')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED')
  assert.equal(f.row.clicked,0);assert.equal(f.pass.value,'')
  f.holder.attrs['data-test-asynctilesloaded']='true';f.state.chooserRows=[f.row]
  state=inspect(f);assert.equal(state.stage,'account');assert.equal(state.reason,'READY')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
  assert.equal(f.row.clicked,1)
})

test('an initially empty ordinary picker changes from ACCOUNT_CHOOSER to READY when its exact saved-account tile arrives',()=>{
  for(const loaded of [undefined,'true']){
    const f=chooserFixture({remainChooser:true})
    if(loaded!==undefined)f.holder.attrs['data-test-asynctilesloaded']=loaded
    f.state.chooserRows=[]
    const initial=inspect(f);assertFixed(initial)
    assert.equal(initial.stage,'manual');assert.equal(initial.reason,'ACCOUNT_CHOOSER');assert.equal(initial.accountMatch,false)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED')
    assert.equal(f.row.clicked,0);assert.equal(f.user.value,'');assert.equal(f.pass.value,'')
    f.state.chooserRows=[f.row]
    const ready=inspect(f);assertFixed(ready)
    assert.equal(ready.stage,'account');assert.equal(ready.reason,'READY');assert.equal(ready.accountMatch,true)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
    assert.equal(f.row.clicked,1)
    const attempted=inspect(f)
    assert.equal(attempted.stage,'manual');assert.equal(attempted.reason,'ALREADY_ATTEMPTED')
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED')
    assert.equal(f.row.clicked,1,'Earlier read-only absence must not consume the first choice or allow a second one')
  }
})

test('a previously authorized identity can take the ordinary exact single-account picker without broadening account choice',()=>{
  const f=chooserFixture()
  const selected=inspect(f,account,nonce,true);assertFixed(selected)
  assert.equal(selected.stage,'account');assert.equal(selected.reason,'READY')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
  assert.equal(f.row.clicked,1);assert.equal(f.pass.value,'')
  const password=inspect(f,account,nonce,true)
  assert.equal(password.stage,'password');assert.equal(password.reason,'READY');assert.equal(password.accountMatch,true)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:true}),'PASSWORD_SUBMITTED')
  assert.equal(f.submit.clicked,1)
  const unknown=chooserFixture()
  unknown.row.attrs['data-test-id']='other@example.org';unknown.content.textContent='other@example.org'
  const mismatch=inspect(unknown,account,nonce,true)
  assert.equal(mismatch.stage,'manual');assert.equal(mismatch.reason,'ACCOUNT_CHOOSER')
  assert.equal(unknown.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED')
  assert.equal(unknown.row.clicked,0);assert.equal(unknown.pass.value,'')
})

test('only a unique exact account may wait for layout or hit readiness and a menu never receives a click',()=>{
  for(const variant of ['small','transparent','content-hidden','menu','occluded']){
    const f=chooserFixture()
    if(variant==='small')f.row.rect.width=1
    if(variant==='transparent')f.row.style.opacity='0'
    if(variant==='content-hidden')f.content.hidden=true
    if(variant==='menu'){
      const menu=new FakeElement();menu.attrs.role='button';menu.parentElement=f.row;f.state.occluder=menu
    }
    if(variant==='occluded')f.state.occluder=new FakeElement()
    const state=inspect(f);assertFixed(state)
    assert.equal(state.stage,'loading',variant);assert.equal(state.reason,'LOADING',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED',variant)
    assert.equal(f.row.clicked,0);assert.equal(f.state.occluder?.clicked??0,0);assert.equal(f.pass.value,'')
    f.row.rect.width=400;f.row.style.opacity='1';f.content.hidden=false;f.state.occluder=null
    assert.equal(inspect(f).stage,'account',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED',variant)
    assert.equal(f.row.clicked,1)
  }
  const unknown=chooserFixture();unknown.state.chooserRows=[]
  assert.equal(inspect(unknown).reason,'ACCOUNT_CHOOSER')
  const mismatch=chooserFixture();mismatch.row.attrs['data-test-id']='other@example.org';mismatch.row.style.opacity='0'
  assert.equal(inspect(mismatch).stage,'manual')
})

test('a mixed display-name, email and status tile uses the email region while a separate menu covers the row center',()=>{
  const f=mixedChooserFixture()
  assert.equal(f.content.textContent,'Synthetic Display Name'+account+'Signed in')
  f.state.menuAtRowCenter=true
  assert.equal(f.document.elementFromPoint(f.row.rect.left+f.row.rect.width/2,f.row.rect.top+f.row.rect.height/2),f.menu)
  const state=inspect(f);assertFixed(state)
  assert.equal(state.stage,'account');assert.equal(state.accountMatch,true)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED')
  assert.equal(f.row.clicked,1);assert.equal(f.email.clicked,0);assert.equal(f.menu.clicked,0)
  assert.equal(f.pass.value,'')
})

test('mixed account content still rejects wrong identities, partial addresses, duplicate visible leaves and duplicate rows',()=>{
  for(const variant of ['attribute','different-email','partial-email','no-email','two-emails','foreign-email','duplicate-row','duplicate-content','disabled']){
    const f=mixedChooserFixture()
    if(variant==='attribute')f.row.attrs['data-test-id']='other@example.org'
    if(variant==='different-email')f.email.textContent='other@example.org'
    if(variant==='partial-email')f.email.textContent=account+'.evil'
    if(variant==='no-email')f.email.textContent='Synthetic Student'
    if(variant==='two-emails'||variant==='foreign-email'){
      f.content.appendChild(new FakeElement({tagName:'SMALL',textContent:variant==='two-emails'?account:'other@example.org',
        rect:{left:100,top:136,width:280,height:20}}))
    }
    if(variant==='duplicate-row'){
      const row=new FakeElement({classes:['table'],rect:f.row.rect});row.attrs={...f.row.attrs};row.parentElement=f.holder
      row.querySelectorAll=f.row.querySelectorAll;f.state.chooserRows.push(row)
    }
    if(variant==='duplicate-content')f.row.querySelectorAll=selector=>selector==='div.table-cell.text-left.content'?[f.content,f.content]:[]
    if(variant==='disabled')f.row.attrs['aria-disabled']='true'
    assert.equal(inspect(f).stage,'manual',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED',variant)
    assert.equal(f.row.clicked,0);assert.equal(f.menu.clicked,0);assert.equal(f.pass.value,'')
  }
})

test('a matching mixed email waits for visibility or a safe hit and never clicks an overflow menu',()=>{
  for(const variant of ['hidden-email','zero-email','sibling-menu','nested-menu','foreign-overlay']){
    const f=mixedChooserFixture()
    if(variant==='hidden-email')f.email.hidden=true
    if(variant==='zero-email')f.email.rect.width=0
    if(variant==='sibling-menu'||variant==='nested-menu'){
      if(variant==='nested-menu')f.menu.parentElement=f.row
      f.state.occluder=f.menu
    }
    if(variant==='foreign-overlay')f.state.occluder=new FakeElement()
    assert.equal(inspect(f).stage,'loading',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED',variant)
    assert.equal(f.row.clicked,0);assert.equal(f.menu.clicked,0)
    f.email.hidden=false;f.email.rect.width=280;f.state.occluder=null
    assert.equal(inspect(f).stage,'account',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'account',account}),'ACCOUNT_SELECTED',variant)
    assert.equal(f.row.clicked,1);assert.equal(f.menu.clicked,0)
  }
  const changed=mixedChooserFixture();assert.equal(inspect(changed).stage,'account')
  changed.email.textContent='other@example.org'
  assert.equal(changed.auth.fillAndSubmit({document:nonce,stage:'account',account}),'MANUAL_REQUIRED')
  assert.equal(changed.row.clicked,0)
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
    .replaceAll('{identity_acknowledged}','false')
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

test('desktop layout reports bounded hidden settling and stops without treating layout failure as a challenge',async()=>{
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

function desktopAfterExhaustedLayout(reason,{approve=count=>Promise.resolve(count<=24)}={}) {
  const f=fixture({skipInstall:true})
  f.submit.rect.width=0
  let usernameAcknowledged=false,nativeWaits=0
  const clicked=f.submit.onClick
  f.submit.onClick=()=>{
    clicked()
    if(f.state.stage==='password') {
      f.pass.rect.width=0;f.pass.style.opacity='0'
      if(reason==='FORM_UNTRUSTED')f.submit.rect.width=0
    }
  }
  const bridge=desktopBootstrap(f,{invoke:async(command,args)=>{
    const report=args.report
    if(report.stage==='submitted') {
      assert.equal(report.reason,'USERNAME_SUBMITTED')
      assert.equal(report.document,nonce)
      usernameAcknowledged=true
    } else if(report.stage==='username'&&report.reason==='READY') {
      assert.equal(usernameAcknowledged,false)
      const code=f.context.WTSQmAuth.fillAndSubmit({document:nonce,stage:'username',account})
      assert.equal(code,'USERNAME_SUBMITTED')
      await f.window.__TAURI_INTERNALS__.invoke(command,{revision:args.revision,
        report:{v:1,stage:'submitted',document:nonce,accountMatch:false,reason:code}})
    } else if(report.stage==='manual'&&report.reason===reason&&usernameAcknowledged) {
      return approve(++nativeWaits)
    } else if(report.stage==='password'&&report.reason==='READY') {
      assert.equal(usernameAcknowledged,true)
      assert.equal(f.context.WTSQmAuth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),
        'PASSWORD_SUBMITTED')
    }
    return false
  }})
  return {f,bridge,get nativeWaits(){return nativeWaits},
    async submitAfterLayoutBudget() {
      // All 16 shared JS layout waits are consumed before a trusted username
      // form appears. The next hidden form must use the native ACK budget.
      for(let index=0;index<15;index++)assert.equal(await bridge.next(),250)
      assert.equal(f.submit.clicked,0)
      f.submit.rect.width=108
      assert.equal(await bridge.next(),250)
      assert.equal(usernameAcknowledged,true)
      assert.equal(f.submit.clicked,1)
      assert.equal(f.pass.value,'')
    },
    revealPassword() {
      f.pass.rect={left:100,top:100,width:348,height:36};f.pass.style.opacity='1';f.submit.rect.width=108
    }}
}

test('desktop username ACK can settle an exhausted initial layout budget and submit the matching password once',async()=>{
  for(const reason of ['FORM_UNTRUSTED','KNOWN_FORM_ABSENT']) {
    const transition=desktopAfterExhaustedLayout(reason)
    const {f,bridge}=transition
    await transition.submitAfterLayoutBudget()
    assert.equal(await bridge.next(),350)
    assert.equal(bridge.reports.at(-1).args.report.reason,reason)
    assert.equal(transition.nativeWaits,1)
    assert.equal(f.submit.clicked,1);assert.equal(f.pass.value,'')
    transition.revealPassword()
    assert.equal(await bridge.next(),750)
    assert.equal(bridge.reports.at(-1).args.report.stage,'password')
    assert.equal(f.submit.clicked,2)
    assert.equal(f.user.value,account);assert.equal(f.pass.value,secret)
    f.window.dispatchEvent(new FakeEvent('pagehide'))
    assert.equal(bridge.timers.size,0)
  }
})

test('desktop username layout settling reports MFA immediately without filling the challenge or password',async()=>{
  for(const reason of ['FORM_UNTRUSTED','KNOWN_FORM_ABSENT']) {
    const transition=desktopAfterExhaustedLayout(reason)
    const {f,bridge}=transition
    await transition.submitAfterLayoutBudget()
    await bridge.next()
    const code=new FakeInput({type:'text',name:'otc',rect:{left:500,top:100,width:170,height:30}})
    code.parentElement=f.form;f.state.extra.push(code)
    assert.equal(await bridge.next(),750)
    assert.equal(bridge.reports.at(-1).args.report.stage,'challenge')
    assert.equal(bridge.reports.at(-1).args.report.reason,'MFA_REQUIRED')
    assert.equal(f.submit.clicked,1);assert.equal(f.pass.value,'');assert.equal(code.value,'')
    f.window.dispatchEvent(new FakeEvent('pagehide'))
  }
})

test('desktop username ACK settling ends at the finite native limit without another input attempt',async()=>{
  for(const reason of ['FORM_UNTRUSTED','KNOWN_FORM_ABSENT']) {
    const transition=desktopAfterExhaustedLayout(reason)
    const {f,bridge}=transition
    await transition.submitAfterLayoutBudget()
    assert.equal(await bridge.next(),350)
    for(let index=1;index<=24;index++)assert.equal(await bridge.next(),750)
    assert.equal(transition.nativeWaits,25)
    assert.equal(bridge.timers.size,0);assert.equal(bridge.active(nonce),false)
    assert.equal(f.submit.clicked,1);assert.equal(f.pass.value,'')
  }
})

test('desktop username settling cannot revive a stopped owner or changed document after native approval',async()=>{
  for(const event of ['pagehide','wts-qm-auth-stop','changedURL']) {
    let resolveNative
    const approval=new Promise(resolve=>{resolveNative=resolve})
    const transition=desktopAfterExhaustedLayout('FORM_UNTRUSTED',{approve:()=>approval})
    const {f,bridge}=transition
    await transition.submitAfterLayoutBudget()
    const pending=bridge.next()
    await bridge.settle()
    if(event==='changedURL')f.setURL('https://example.invalid/')
    else f.window.dispatchEvent(new FakeEvent(event))
    resolveNative(true)
    await pending
    assert.equal(bridge.timers.size,0);assert.equal(bridge.active(nonce),false)
    assert.equal(f.submit.clicked,1);assert.equal(f.pass.value,'')
  }
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

test('desktop challenge polling stays read-only and can observe the next ordinary SSO step',async()=>{
  const f=fixture({skipInstall:true})
  const code=new FakeInput({type:'text',name:'otc',rect:{left:500,top:100,width:170,height:30}})
  code.parentElement=f.form;f.state.extra.push(code)
  const bridge=desktopBootstrap(f)
  await bridge.settle()
  assert.equal(bridge.reports[0].args.report.stage,'challenge')
  assert.equal(bridge.reports[0].args.report.reason,'MFA_REQUIRED')
  for(let i=0;i<72;i++)assert.equal(await bridge.next(),750)
  assert.equal(bridge.active(nonce),true)
  assert.equal(bridge.reports.every(item=>item.args.report.stage==='challenge'),true)
  assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(code.value,'');assert.equal(code.clicked,0)
  f.state.extra=[]
  assert.equal(await bridge.next(),750)
  assert.equal(bridge.reports.at(-1).args.report.stage,'username')
  assert.equal(f.submit.clicked,0)
  assert.doesNotMatch(JSON.stringify(bridge.reports),/student@|synthetic-password|SAMLRequest/)
})

test('only the observed official sibling placeholder permits quiet filling without focus',()=>{
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
  assert.equal(inspect(f).stage,'username')
  assert.equal(f.user.focused??0,0)
  assert.equal(f.user.value,'')
  assert.equal(f.submit.clicked,0)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  assert.equal(f.user.focused??0,0)
  assert.deepEqual(f.user.events,['input','change'])
  // Microsoft may keep its hint visible until its input binding updates.
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
  assert.equal(persistent.user.focused??0,0)
  const bad=fixture()
  bad.state.occluder=new FakeElement()
  const original=bad.document.elementFromPoint.bind(bad.document)
  bad.document.elementFromPoint=(x,y)=>y>=160?bad.submit:original(x,y)
  assert.equal(inspect(bad).stage,'manual')
  assert.equal(bad.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  assert.equal(bad.user.focused,undefined)
  assert.equal(bad.user.value,'')
  assert.equal(bad.submit.clicked,0)
})

test('quiet filling through an owned hint revalidates editability, visibility and form action before submit',()=>{
  for(const change of ['disabled','readOnly','invisible','action']){
    const f=fixture()
    const container=new FakeElement();container.classList={contains:n=>n==='placeholderContainer'};container.parentElement=f.form
    f.user.parentElement=container
    const parent=new FakeElement();parent.classList={contains:n=>n==='placeholderInnerContainer'};parent.parentElement=container
    const hint=new FakeElement();hint.classList={contains:n=>n==='placeholder'};hint.attrs['aria-hidden']='true';hint.parentElement=parent
    const hit=f.document.elementFromPoint.bind(f.document)
    f.state.occluder=hint;f.document.elementFromPoint=(x,y)=>y>=160?f.submit:hit(x,y)
    f.user.dispatchEvent=event=>{
      f.user.events.push(event.type)
      if(change==='invisible')f.user.style.opacity='0'
      else if(change==='action')f.form.action='https://evil.test/login'
      else f.user[change]=true
    }
    assert.equal(inspect(f).stage,'username',change)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED',change)
    assert.equal(f.user.focused??0,0,change)
    assert.equal(f.submit.clicked,0,change)
  }
})

test('an owned password placeholder permits native setter events and submission without focus',()=>{
  const f=fixture()
  assert.equal(inspect(f).stage,'username')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  const container=new FakeElement({classes:['placeholderContainer']});container.parentElement=f.form
  f.pass.parentElement=container
  const parent=new FakeElement({classes:['placeholderInnerContainer']});parent.parentElement=container
  const hint=new FakeElement({classes:['placeholder']});hint.attrs['aria-hidden']='true';hint.parentElement=parent
  const hit=f.document.elementFromPoint.bind(f.document)
  f.document.elementFromPoint=(x,y)=>y>=100&&y<136?hint:hit(x,y)
  assert.equal(inspect(f).stage,'password')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'PASSWORD_SUBMITTED')
  assert.deepEqual(f.pass.events,['input','change'])
  assert.equal(f.pass.value,secret)
  assert.equal(f.submit.clicked,2)
  assert.equal(f.user.focused??0,0);assert.equal(f.pass.focused??0,0)
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
  assert.equal(f.user.focused??0,0);assert.equal(f.pass.focused??0,0)
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

test('direct password page identifies the exact current account but still requires native acknowledgement before filling',()=>{
  const manual=fixture({stage:'password'})
  manual.pass.rect={left:100,top:100,width:348,height:36};manual.pass.style.opacity='1'
  assert.equal(inspect(manual).stage,'password')
  assert.equal(inspect(manual).reason,'CURRENT_ACCOUNT_VERIFIED')
  assert.equal(manual.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  const mismatch=fixture();inspect(mismatch)
  assert.equal(mismatch.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  mismatch.displayName.textContent='other@example.org'
  assert.equal(inspect(mismatch).stage,'manual')
  assert.equal(mismatch.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  assert.equal(mismatch.submit.clicked,1)
})

test('password identity layout or missing evidence never masquerades as a different account and retains the once-only username ACK',()=>{
  for(const variant of ['missing','duplicate','empty','name-only','hidden','transparent','tiny','occluded','noninteractive']){
    const f=fixture();inspect(f)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
    const query=f.document.querySelectorAll.bind(f.document)
    if(variant==='missing'||variant==='duplicate')f.document.querySelectorAll=selector=>selector==='#displayName'?(variant==='missing'?[]:[f.displayName,f.displayName]):query(selector)
    if(variant==='empty')f.displayName.textContent=''
    if(variant==='name-only')f.displayName.textContent='Synthetic Display Name'
    if(variant==='hidden')f.displayName.hidden=true
    if(variant==='transparent')f.displayName.style.opacity='0'
    if(variant==='tiny')f.displayName.rect.width=0
    if(variant==='occluded'||variant==='noninteractive'){
      const hit=f.document.elementFromPoint.bind(f.document)
      f.document.elementFromPoint=(x,y)=>y<80?(variant==='occluded'?new FakeElement():f.form):hit(x,y)
    }
    const state=inspect(f);assertFixed(state)
    assert.equal(state.stage,'manual',variant)
    assert.equal(state.reason,'KNOWN_FORM_ABSENT',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:true}),'MANUAL_REQUIRED',variant)
    assert.equal(f.pass.value,'',variant);assert.equal(f.submit.clicked,1,variant)
    f.document.querySelectorAll=query
    f.displayName.textContent=account;f.displayName.hidden=false;f.displayName.style.opacity='1';f.displayName.rect.width=348
    f.document.elementFromPoint=(x,y)=>y<80?f.displayName:y<150?f.pass:f.submit
    assert.equal(inspect(f).reason,'READY',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'PASSWORD_SUBMITTED',variant)
    assert.equal(f.submit.clicked,2,variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED',variant)
    assert.equal(f.submit.clicked,2,variant)
  }
})

test('only a unique hit-valid visible account header proves password identity mismatch',()=>{
  for(const variant of ['visible','hidden','occluded','duplicate']){
    const f=fixture({stage:'password'})
    f.pass.rect={left:100,top:100,width:348,height:36};f.pass.style.opacity='1'
    f.displayName.textContent='other@example.org'
    if(variant==='hidden')f.displayName.hidden=true
    if(variant==='occluded'){
      const hit=f.document.elementFromPoint.bind(f.document)
      f.document.elementFromPoint=(x,y)=>y<80?new FakeElement():hit(x,y)
    }
    if(variant==='duplicate'){
      const query=f.document.querySelectorAll.bind(f.document)
      f.document.querySelectorAll=selector=>selector==='#displayName'?[f.displayName,f.displayName]:query(selector)
    }
    assert.equal(inspect(f,account,nonce,true).reason,variant==='visible'?'ACCOUNT_MISMATCH':'KNOWN_FORM_ABSENT',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:true}),'MANUAL_REQUIRED',variant)
    assert.equal(f.pass.value,'');assert.equal(f.submit.clicked,0)
  }
})

test('native identity ACK may cross a real document but is not retained by inspect or inferred from truthy values',()=>{
  const previous=fixture();inspect(previous)
  assert.equal(previous.auth.fillAndSubmit({document:nonce,stage:'username',account}),'USERNAME_SUBMITTED')
  const f=fixture({stage:'password'})
  f.pass.rect={left:100,top:100,width:348,height:36};f.pass.style.opacity='1'
  assert.equal(inspect(f).reason,'CURRENT_ACCOUNT_VERIFIED')
  const approved=inspect(f,account,nonce,true)
  assertFixed(approved);assert.equal(approved.stage,'password');assert.equal(approved.reason,'READY')
  assert.equal(inspect(f).reason,'CURRENT_ACCOUNT_VERIFIED')
  for(const value of [false,'true',1,{},null])assert.equal(inspect(f,account,nonce,value).reason,'CURRENT_ACCOUNT_VERIFIED')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret}),'MANUAL_REQUIRED')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:'true'}),'REJECTED')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:true}),'PASSWORD_SUBMITTED')
  assert.equal(f.pass.value,secret);assert.equal(f.submit.clicked,1)
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:true}),'MANUAL_REQUIRED')
  assert.equal(f.submit.clicked,1)
})

test('cross-document identity ACK cannot weaken account, URL, control or nonce verification',()=>{
  for(const variant of ['account','hidden','leftover-user','prefilled','action','nonce','kmsi-path','challenge']){
    const f=fixture({stage:'password'})
    f.pass.rect={left:100,top:100,width:348,height:36};f.pass.style.opacity='1'
    inspect(f)
    if(variant==='account')f.displayName.textContent='other@example.org'
    if(variant==='hidden')f.displayName.hidden=true
    if(variant==='leftover-user'){
      const query=f.document.querySelectorAll.bind(f.document)
      f.document.querySelectorAll=selector=>selector==='#i0116'?[f.user]:query(selector)
    }
    if(variant==='prefilled')f.pass.value='existing-password'
    if(variant==='action')f.form.action='https://login.microsoftonline.com/other/login'
    if(variant==='kmsi-path')f.setURL('https://login.microsoftonline.com/kmsi')
    if(variant==='challenge'){
      const code=new FakeInput({type:'text',name:'otc',rect:{left:500,top:100,width:170,height:30}})
      code.parentElement=f.form;f.state.extra.push(code)
    }
    assert.notEqual(f.auth.fillAndSubmit({document:variant==='nonce'?'nonceB456':nonce,
      stage:'password',account,password:secret,identityAcknowledged:true}),'PASSWORD_SUBMITTED',variant)
    assert.equal(f.submit.clicked,0,variant)
    assert.notEqual(f.pass.value,secret,variant)
  }
})

test('only positively identified visible CAPTCHA or MFA controls produce the non-secret challenge stage',()=>{
  for(const kind of ['captcha','code','otc','approval']){
    const f=fixture()
    let control
    if(kind==='captcha'){
      control=new FakeElement({tagName:'IFRAME',rect:{left:500,top:100,width:240,height:80}})
      control.attrs.title='CAPTCHA challenge'
    }else if(kind==='approval'){
      control=new FakeElement({tagName:'H1',textContent:'Approve sign in request',rect:{left:500,top:100,width:240,height:32}})
    }else{
      control=new FakeInput({name:kind==='otc'?'otc':'verification',type:'text',rect:{left:500,top:100,width:170,height:30}})
      if(kind==='code')control.attrs.autocomplete='one-time-code'
    }
    control.parentElement=f.form;f.state.extra.push(control)
    f.document.readyState='loading'
    const state=inspect(f);assertFixed(state)
    assert.equal(state.stage,'challenge',kind)
    assert.equal(state.reason,kind==='captcha'?'CAPTCHA_REQUIRED':'MFA_REQUIRED',kind)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED',kind)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'challenge',account}),'REJECTED',kind)
    assert.equal(f.user.value,'');assert.equal(f.submit.clicked,0);assert.equal(control.clicked,0)
    control.hidden=true;assert.equal(inspect(f).stage,'loading',kind)
    f.document.readyState='complete';assert.equal(inspect(f).stage,'username',kind)
  }
  const unknown=fixture()
  const title=new FakeElement({tagName:'H1',textContent:'More information required'})
  const input=new FakeInput({type:'text',name:'unknown'})
  title.parentElement=unknown.form;input.parentElement=unknown.form;unknown.state.extra.push(title,input)
  assert.equal(inspect(unknown).stage,'manual')
  const untrusted=fixture();untrusted.setURL('https://evil.invalid/login')
  const otp=new FakeInput({name:'otc',type:'text'});otp.parentElement=untrusted.form;untrusted.state.extra.push(otp)
  assert.equal(inspect(untrusted).stage,'manual')
})

test('recognized KMSI continuation requires current identity and submits Yes once without touching checkbox or password',()=>{
  for(const url of [msURL,'https://login.microsoftonline.com/kmsi']){
    const f=continuationFixture({checkbox:true,url})
    assert.equal(inspect(f).stage,'continue');assert.equal(inspect(f).reason,'CURRENT_ACCOUNT_VERIFIED')
    const state=inspect(f,account,nonce,true);assertFixed(state)
    assert.equal(state.stage,'continue');assert.equal(state.reason,'READY');assert.equal(state.accountMatch,true)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'continue',account,identityAcknowledged:true,password:secret}),'REJECTED')
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'continue',account}),'MANUAL_REQUIRED')
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'continue',account,identityAcknowledged:true}),'CONTINUE_SUBMITTED')
    assert.equal(f.submit.clicked,1);assert.equal(f.back.clicked,0)
    assert.equal(f.state.kmsiCheckbox.clicked,0);assert.equal(f.state.kmsiCheckbox.checked,false)
    assert.equal(f.pass.value,'');assert.equal(f.user.value,'')
    assert.equal(inspect(f,account,nonce,true).reason,'ALREADY_ATTEMPTED')
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'continue',account,identityAcknowledged:true}),'MANUAL_REQUIRED')
    assert.equal(f.submit.clicked,1)
  }
})

test('missing KMSI identity evidence never becomes an account mismatch or permission to continue',()=>{
  for(const variant of ['missing','hidden','occluded','name-only','no-hint']){
    const f=continuationFixture()
    if(variant==='missing'){
      const query=f.document.querySelectorAll.bind(f.document)
      f.document.querySelectorAll=selector=>selector==='#displayName'?[]:query(selector)
    }
    if(variant==='hidden')f.displayName.hidden=true
    if(variant==='occluded'){
      const hit=f.document.elementFromPoint.bind(f.document)
      f.document.elementFromPoint=(x,y)=>y<80?new FakeElement():hit(x,y)
    }
    if(variant==='name-only')f.displayName.textContent='Synthetic Display Name'
    const state=inspect(f,variant==='no-hint'?'':account,nonce,true);assertFixed(state)
    assert.equal(state.stage,'manual',variant)
    assert.equal(state.reason,variant==='no-hint'?'ACCOUNT_HINT_REQUIRED':'KNOWN_FORM_ABSENT',variant)
    if(variant!=='no-hint')assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'continue',account,identityAcknowledged:true}),'MANUAL_REQUIRED')
    assert.equal(f.submit.clicked,0);assert.equal(f.back.clicked,0)
  }
  const other=continuationFixture();other.displayName.textContent='other@example.org'
  assert.equal(inspect(other,account,nonce,true).reason,'ACCOUNT_MISMATCH')
})

test('the confirmed MFA method-selection heading requests user interaction without choosing or sending a code',()=>{
  for(const title of ['Verify your identity', '验证您的身份', '驗證您的身分', '驗證您的身份']){
    for(const tagName of ['H1','H2','DIV']){
      const f=fixture({readyState:'loading'})
      const heading=new FakeElement({tagName,textContent:title,rect:{left:500,top:100,width:280,height:32}})
      if(tagName==='DIV')heading.attrs.role='heading'
      const method=new FakeElement({tagName:'BUTTON',textContent:'Synthetic SMS option',rect:{left:500,top:160,width:280,height:32}})
      heading.parentElement=f.form;method.parentElement=f.form;f.state.extra.push(heading,method)
      const report=inspect(f);assertFixed(report)
      assert.equal(report.stage,'challenge');assert.equal(report.reason,'MFA_REQUIRED')
      assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
      assert.equal(method.clicked,0);assert.equal(f.submit.clicked,0);assert.equal(f.user.value,'')
      heading.hidden=true
      assert.equal(inspect(f).stage,'loading')
    }
  }
  const unknown=fixture()
  const heading=new FakeElement({tagName:'H1',textContent:'Verify your identity and accept new permissions'})
  const consent=new FakeInput({type:'checkbox'})
  heading.parentElement=unknown.form;consent.parentElement=unknown.form;unknown.state.extra.push(heading,consent)
  assert.equal(inspect(unknown).stage,'manual')
})

// Primary evidence: https://github.com/AzureAD/microsoft-authentication-library-common-for-android/blob/f0aa6a9c55575e26380d526ab97126b2cb2e5e01/uiautomationutilities/src/main/java/com/microsoft/identity/client/ui/automation/interaction/microsoftsts/AadLoginComponentHandler.java#L319
// handleVerifyYourIdentity identifies the method picker by idDiv_SAOTCS_Title.
test('the official MSAL MFA title ID recognizes bounded localized and nested text without touching phone methods',()=>{
  for(const title of ['Verify your identity','验证您的身份','Vérifiez votre identité','任意语言标题']){
    const f=fixture({readyState:'loading'})
    const marker=new FakeElement({id:'idDiv_SAOTCS_Title',textContent:title,rect:{left:500,top:100,width:280,height:32}})
    marker.parentElement=f.form;f.state.extra.push(marker)
    marker.appendChild(new FakeElement({textContent:' — synthetic nested description'}))
    const phone=new FakeInput({type:'tel',name:'syntheticPhone'})
    const sms=new FakeElement({tagName:'BUTTON',textContent:'Synthetic SMS'})
    const call=new FakeElement({tagName:'BUTTON',textContent:'Synthetic Call'})
    for(const node of [phone,sms,call]){node.parentElement=f.form;f.state.extra.push(node)}
    assert.equal(marker.tagName,'DIV');assert.equal(marker.getAttribute('role'),null)
    const state=inspect(f);assertFixed(state)
    assert.equal(state.stage,'challenge');assert.equal(state.reason,'MFA_REQUIRED')
    for(const stage of ['account','username','password','continue']){
      const options={document:nonce,stage,account,...(stage==='password'?{password:secret}:{} )}
      assert.equal(f.auth.fillAndSubmit(options),'MANUAL_REQUIRED')
    }
    assert.equal(marker.clicked,0);assert.equal(f.user.value,'');assert.equal(f.submit.clicked,0)
    assert.equal(f.pass.value,'');assert.equal(phone.value,'');assert.equal(phone.clicked,0)
    assert.equal(sms.clicked,0);assert.equal(call.clicked,0)
    assert.doesNotMatch(JSON.stringify(state),/student@|synthetic-password|syntheticPhone/)
    marker.hidden=true;assert.equal(inspect(f).stage,'loading')
    marker.hidden=false;marker.textContent=' '
    assert.equal(inspect(f).stage,'loading')
    marker.textContent=title;f.state.extra.push(marker)
    assert.equal(inspect(f).stage,'loading','A duplicated nonsemantic marker is not sufficient challenge evidence')
  }
})

test('MSAL method-title recognition rejects duplicate, hidden, invisible, unbounded, editable and untrusted markers',()=>{
  for(const variant of ['duplicate','hidden','invisible','empty','long','input','textarea','editable','foreign','frame']){
    const f=fixture({readyState:'loading'})
    const marker=variant==='input'?new FakeInput({id:'idDiv_SAOTCS_Title',type:'text',textContent:'Synthetic title'}):
      new FakeElement({id:'idDiv_SAOTCS_Title',tagName:variant==='textarea'?'TEXTAREA':'DIV',textContent:'Synthetic title'})
    marker.parentElement=f.form;f.state.extra.push(marker)
    if(variant==='duplicate')f.state.extra.push(marker)
    if(variant==='hidden')marker.hidden=true
    if(variant==='invisible')marker.style.opacity='0'
    if(variant==='empty')marker.textContent=' '
    if(variant==='long')marker.textContent='x'.repeat(129)
    if(variant==='editable')marker.isContentEditable=true
    if(variant==='foreign')f.setURL('https://evil.invalid/login')
    if(variant==='frame')f.window.top={}
    assert.notEqual(inspect(f).stage,'challenge',variant)
    assert.equal(marker.clicked,0);assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(f.submit.clicked,0)
  }
})

test('the exact device-auth verification path only observes pending or MFA states and never fills any form',()=>{
  for(const path of ['/common/DeviceAuthTls/reprocess','/COMMON/DEVICEAUTHTLS/REPROCESS']){
    for(const readyState of ['loading','complete']){
      const f=fixture({url:new URL('https://login.microsoftonline.com'+path),readyState})
      const pending=inspect(f,'');assertFixed(pending)
      assert.equal(pending.stage,'loading');assert.equal(pending.reason,'LOADING')
      for(const stage of ['account','username','password','continue']){
        const request={document:nonce,stage,account}
        if(stage==='password')Object.assign(request,{password:secret,identityAcknowledged:true})
        if(stage==='continue')request.identityAcknowledged=true
        assert.equal(f.auth.fillAndSubmit(request),'MANUAL_REQUIRED',stage)
      }
      assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(f.user.focused,undefined)
      assert.equal(f.submit.clicked,0)
      const title=new FakeElement({id:'idDiv_SAOTCS_Title',textContent:'验证您的身份',rect:{left:500,top:100,width:280,height:32}})
      title.parentElement=f.form;f.state.extra.push(title)
      const challenge=inspect(f,'');assertFixed(challenge)
      assert.equal(challenge.stage,'challenge');assert.equal(challenge.reason,'MFA_REQUIRED')
      assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'password',account,password:secret,identityAcknowledged:true}),'MANUAL_REQUIRED')
      assert.equal(f.user.value,'');assert.equal(f.pass.value,'');assert.equal(f.submit.clicked,0);assert.equal(title.clicked,0)
    }
    const continuation=continuationFixture({url:'https://login.microsoftonline.com'+path})
    assert.equal(inspect(continuation,account,nonce,true).stage,'loading')
    assert.equal(continuation.auth.fillAndSubmit({document:nonce,stage:'continue',account,identityAcknowledged:true}),'MANUAL_REQUIRED')
    assert.equal(continuation.submit.clicked,0);assert.equal(continuation.back.clicked,0)
  }
})

test('verification-only path matching does not allow adjacent paths, other hosts, frames or credential-path case folding',()=>{
  for(const url of [
    'https://login.microsoftonline.com/common/DeviceAuthTls/reprocess/',
    'https://login.microsoftonline.com/common/DeviceAuthTls/other',
    'https://login.microsoftonline.com/common/%44eviceAuthTls/reprocess',
    'https://login.microsoftonline.com/other/DeviceAuthTls/reprocess',
    'https://login.microsoftonline.com.evil.invalid/common/DeviceAuthTls/reprocess',
    'http://login.microsoftonline.com/common/DeviceAuthTls/reprocess',
    `https://login.microsoftonline.com/${tenant}/LOGIN`
  ]){
    const f=fixture({url:new URL(url)})
    const title=new FakeElement({id:'idDiv_SAOTCS_Title',textContent:'Verify your identity'})
    title.parentElement=f.form;f.state.extra.push(title)
    assert.equal(inspect(f).stage,'manual',url)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
    assert.equal(f.user.value,'');assert.equal(f.submit.clicked,0)
  }
  const frame=fixture({url:new URL('https://login.microsoftonline.com/common/DeviceAuthTls/reprocess')})
  frame.window.top={}
  assert.equal(inspect(frame).stage,'manual')
})

test('KMSI never generalizes to unknown consent, permissions, alerts, extra controls or another account',()=>{
  for(const variant of ['no-title','terms-title','other-account','untrusted-action','tenant-action','checkbox-terms',
    'unknown-input','unknown-button','alert','missing-back','duplicate-title','credential','occluded']){
    const f=continuationFixture({checkbox:true})
    if(variant==='no-title')f.state.kmsiTitle=null
    if(variant==='terms-title')f.title.textContent='Accept the terms and permissions'
    if(variant==='other-account')f.displayName.textContent='other@example.org'
    if(variant==='untrusted-action')f.form.action='https://evil.invalid/kmsi'
    if(variant==='tenant-action')f.form.action=formURL
    if(variant==='checkbox-terms')f.state.kmsiLabel.textContent='I accept the terms and permissions'
    if(variant==='unknown-input')f.state.extra.push(new FakeInput({type:'checkbox'}))
    if(variant==='unknown-button')f.state.extra.push(new FakeElement({tagName:'BUTTON'}))
    if(variant==='alert'){f.state.alert=new FakeElement();f.state.alert.attrs.role='alert'}
    if(variant==='missing-back')f.state.back=null
    if(variant==='occluded')f.state.occluder=new FakeElement()
    if(variant==='duplicate-title'||variant==='credential'){
      const query=f.document.querySelectorAll.bind(f.document)
      f.document.querySelectorAll=selector=>variant==='duplicate-title'&&selector==='#kmsiTitle'?[f.title,f.title]:
        variant==='credential'&&selector==='#i0116, #i0118'?[f.pass]:query(selector)
    }
    assert.equal(inspect(f,account,nonce,true).stage,'manual',variant)
    assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'continue',account,identityAcknowledged:true}),'MANUAL_REQUIRED',variant)
    assert.equal(f.submit.clicked,0,variant)
  }
  const f=fixture();f.setURL('https://login.microsoftonline.com/kmsi')
  assert.equal(inspect(f,account,nonce,true).stage,'manual')
  assert.equal(f.auth.fillAndSubmit({document:nonce,stage:'username',account}),'MANUAL_REQUIRED')
  assert.equal(f.user.value,'')
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
