import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import test from 'node:test'
import {transformSync} from 'esbuild'
import {jsx,jsxs} from 'react/jsx-runtime'
import {renderToStaticMarkup} from 'react-dom/server'

const require=createRequire(import.meta.url)
const source=readFileSync(new URL('../src/QmplusLoginSettings.jsx',import.meta.url),'utf8')
const compiled=transformSync(source,{loader:'jsx',format:'cjs',jsx:'automatic'}).code
const tick=()=>new Promise(resolve=>setImmediate(resolve))
const gate=()=>{let resolve,reject;return {promise:new Promise((done,fail)=>{resolve=done;reject=fail}),resolve:value=>resolve(value),reject:error=>reject(error)}}

// Execute the real editor/effect with controlled hooks and synthetic native IPC.
// No browser profile, account, network or operating-system vault is accessed.
function editor(command,listen,overrides={}) {
  const cells=[],effects=[]
  let cursor=0,writes=0
  const hooks={
    useState(initial){
      const index=cursor++
      if(!cells[index])cells[index]={value:initial}
      return [cells[index].value,value=>{writes++;cells[index].value=typeof value==='function'?value(cells[index].value):value}]
    },
    useRef(initial){const index=cursor++;return cells[index]??(cells[index]={current:initial})},
    useId(){return `qmplus-fixture-${cursor++}`},
    useEffect(run,deps){
      const index=cursor++,old=effects[index]
      if(!old||deps.some((value,i)=>!Object.is(value,old.deps[i])))effects[index]={run,deps,pending:true,cleanup:old?.cleanup}
    },
  }
  const module={exports:{}}
  new Function('require','module','exports',compiled)(name=>{
    if(name==='react')return hooks
    if(name==='react/jsx-runtime')return {jsx,jsxs}
    if(name==='lucide-react')return require(name)
    if(name==='@tauri-apps/api/event')return {listen}
    if(name==='./ui-text.js')return {uiText:(_language,key,english)=>english||key}
    if(name==='./AnimatedDisclosure.jsx')return {__esModule:true,default:props=>jsx('div',{id:props.id,children:props.children})}
    if(name==='./qmplus-settings-errors.js')return {qmplusSettingsErrorKey:()=> 'Synthetic failure'}
    throw new Error(`Unexpected test import: ${name}`)
  },module,module.exports)
  const props={language:'en',native:true,enabled:true,command,...overrides}
  return {
    render(){cursor=0;return renderToStaticMarkup(module.exports.default(props))},
    mount(){this.render();for(const effect of effects){if(effect?.pending){effect.pending=false;effect.cleanup?.();effect.cleanup=effect.run()}}},
    unmount(){for(const effect of effects)effect?.cleanup?.()},
    writes:()=>writes,
  }
}

async function mounted(phase,overrides={}) {
  let receive
  const view=editor(async name=>name==='load_qmplus_login'?{saved:true,enabled:true}:{phase,reason:''},
    async(name,callback)=>{assert.equal(name,'qmplus:connection-status');receive=callback;return ()=>{}},overrides)
  view.mount();await tick()
  return {view,emit:next=>receive({payload:{phase:next,reason:''}})}
}

test('manual recovery disappears after validated sync without hiding a current reauthentication request',async()=>{
  for(const initial of ['manual','challenge']) {
    for(const completed of ['synced','partial']) {
      const {view,emit}=await mounted(initial)
      assert.match(view.render(),/>Continue manually<\/button>/)
      emit(completed)
      assert.doesNotMatch(view.render(),/>Continue manually<\/button>/)
      emit('manual')
      assert.match(view.render(),/>Continue manually<\/button>/)
      view.unmount()
    }
  }
})

test('manual recovery stays hidden during ordinary work, after completion and while disabled',async()=>{
  for(const phase of ['', 'checking','username','password','submitted','synced','partial','failed','cancelled']) {
    const {view}=await mounted(phase)
    assert.doesNotMatch(view.render(),/>Continue manually<\/button>/,phase)
    view.unmount()
  }
  for(const flags of [{enabled:false,native:true},{enabled:true,native:false},{enabled:false,native:false}]) {
    const {view}=await mounted('manual',flags)
    assert.doesNotMatch(view.render(),/>Continue manually<\/button>/)
    view.unmount()
  }
})

test('a late initial manual status cannot overwrite a newer successful event',async()=>{
  const initial=gate()
  let receive
  const view=editor(name=>name==='load_qmplus_login'?Promise.resolve({saved:true,enabled:true}):initial.promise,
    async(_name,callback)=>{receive=callback;return ()=>{}})
  view.mount();await tick()
  receive({payload:{phase:'synced',reason:'SYNC_VALIDATED'}})
  initial.resolve({phase:'manual',reason:'USER_CONTINUE'})
  await tick()
  assert.match(view.render(),/QMplus sync completed/)
  assert.doesNotMatch(view.render(),/>Continue manually<\/button>/)
  view.unmount()
})

test('initial connection read starts only after subscription and catches completion during registration',async()=>{
  const registration=gate(),calls=[]
  let phase='manual'
  const view=editor(async name=>{
    calls.push(name)
    return name==='load_qmplus_login'?{saved:true,enabled:true}:{phase,reason:''}
  },()=>{calls.push('listen');return registration.promise})
  view.mount();await tick()
  assert.equal(calls.includes('load_qmplus_connection_status'),false)
  phase='synced';registration.resolve(()=>{})
  await tick()
  assert.ok(calls.indexOf('listen')<calls.indexOf('load_qmplus_connection_status'))
  assert.match(view.render(),/QMplus sync completed/)
  assert.doesNotMatch(view.render(),/>Continue manually<\/button>/)
  view.unmount()
})

test('unmount releases a late subscription without starting another read or writing stale state',async()=>{
  const registration=gate(),calls=[]
  let releases=0,receive
  const view=editor(async name=>{calls.push(name);return {saved:true,enabled:true}},
    (_name,callback)=>{receive=callback;return registration.promise})
  view.mount();await tick();view.unmount()
  const writes=view.writes()
  registration.resolve(()=>{releases++})
  receive({payload:{phase:'synced'}})
  await tick()
  assert.equal(releases,1)
  assert.equal(view.writes(),writes)
  assert.equal(calls.includes('load_qmplus_connection_status'),false)
})

test('a failed event subscription still reads the initial native connection status once',async()=>{
  const calls=[]
  const view=editor(async name=>{
    calls.push(name)
    return name==='load_qmplus_login'?{saved:true,enabled:true}:{phase:'manual',reason:''}
  },async()=>{throw new Error('Synthetic listener unavailable')})
  view.mount();await tick()
  assert.equal(calls.filter(name=>name==='load_qmplus_connection_status').length,1)
  assert.match(view.render(),/>Continue manually<\/button>/)
  view.unmount()
})

test('a subscription failure after unmount cannot start the fallback status read',async()=>{
  const registration=gate(),calls=[]
  const view=editor(async name=>{calls.push(name);return {saved:true,enabled:true}},()=>registration.promise)
  view.mount();await tick();view.unmount()
  const writes=view.writes()
  registration.reject(new Error('Synthetic late listener failure'))
  await tick()
  assert.equal(calls.includes('load_qmplus_connection_status'),false)
  assert.equal(view.writes(),writes)
})

test('an initial status read failure does not retry or become a subscription failure',async()=>{
  const calls=[]
  const view=editor(async name=>{
    calls.push(name)
    if(name==='load_qmplus_connection_status')throw new Error('Synthetic status unavailable')
    return {saved:true,enabled:true}
  },async()=>()=>{})
  view.mount();await tick();await tick()
  assert.equal(calls.filter(name=>name==='load_qmplus_connection_status').length,1)
  view.unmount()
})

test('QMplus actions reuse themed controls and real SVG icons instead of unstyled browser rectangles',async()=>{
  const {view}=await mounted('manual')
  const html=view.render()
  assert.equal((html.match(/class="settings-actions qmplus-settings-actions"/g)||[]).length,2)
  for(const label of ['Save QMplus credentials securely','Delete QMplus credentials','Connect / sync QMplus','Continue manually']) {
    assert.match(html,new RegExp(`<button[^>]*class="(?:primary|secondary|danger)"[^>]*><svg[^>]*>[\\s\\S]*?<\\/svg>${label.replaceAll('/','\\/')}<\\/button>`))
  }
  assert.doesNotMatch(html,/<button[^>]*>[^<]*Disconnect and clear QMplus data<\/button>/)
  const css=readFileSync(new URL('../src/App.css',import.meta.url),'utf8')
  assert.match(css,/\.settings-actions button\s*\{[^}]*border-radius:\s*6px;/)
  assert.match(css,/\.qmplus-settings-actions > button\s*\{[^}]*height:\s*auto;[^}]*max-width:\s*100%;[^}]*overflow-wrap:\s*anywhere;/)
  assert.match(css,/\.qmplus-settings-actions > button > svg\s*\{\s*flex:\s*0 0 auto;/)
  view.unmount()
})
