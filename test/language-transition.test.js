import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {LanguageTransition, createLanguageTransitionFocusGuard} from '../src/language-transition.js'

function fixture() {
  let now=0, nextID=0
  const tasks=new Map(), published=[], applied=[]
  const state={locale:'zh-Hans',ready:true,reduced:false}
  const schedule=(action,delay)=>{const id=++nextID;tasks.set(id,{at:now+delay,action});return id}
  const owner=new LanguageTransition({
    apply:value=>{applied.push(value);state.locale=value==='system'?'en':value},
    publish:value=>published.push(value), layoutReady:target=>state.ready&&state.locale===target,
    reducedMotion:()=>state.reduced, schedule, cancel:id=>tasks.delete(id),
    frame:action=>schedule(action,16), cancelFrame:id=>tasks.delete(id),
  })
  return {owner,state,applied,published,tasks,schedule,cancel:id=>tasks.delete(id),
    advance(ms) {
      const limit=now+ms
      while(true) {
        const due=[...tasks].filter(([,value])=>value.at<=limit).sort((a,b)=>a[1].at-b[1].at)[0]
        if(!due)break
        tasks.delete(due[0]);now=due[1].at;due[1].action()
      }
      now=limit
    }, phase:()=>published.at(-1)?.phase}
}

test('default native timers retain the browser host receiver',t=>{
  t.mock.method(globalThis,'setTimeout',function() {
    assert.equal(this,globalThis)
    return 1
  })
  t.mock.method(globalThis,'clearTimeout',function() { assert.equal(this,globalThis) })
  const owner=new LanguageTransition({apply:()=>{},publish:()=>{},layoutReady:()=>false,
    reducedMotion:()=>false,frame:()=>2,cancelFrame:()=>{}})
  owner.request('en','en','zh-Hans')
  owner.finish(false)
})

test('cover precedes commit and target layout plus a paint precede reveal',()=>{
  const f=fixture();f.state.ready=false
  f.owner.request('en','en','zh-Hans')
  assert.equal(f.phase(),'covering');assert.deepEqual(f.applied,[])
  f.advance(120)
  assert.deepEqual(f.applied,['en']);assert.equal(f.phase(),'waiting')
  f.advance(100);assert.equal(f.phase(),'waiting')
  f.state.ready=true
  f.advance(100);assert.equal(f.phase(),'completed');assert.equal(f.published.at(-1).completed,true)
  f.advance(800);assert.equal(f.phase(),'revealing')
  f.advance(220);assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
})

test('rapid opposite selection cancels the still-pending choice',()=>{
  const f=fixture();f.owner.request('en','en','zh-Hans');f.advance(50)
  f.owner.request('zh-Hans','zh-Hans','zh-Hans');f.advance(1000)
  assert.deepEqual(f.applied,['zh-Hans']);assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
})

test('a layout that changes again before paint is not acknowledged early',()=>{
  const f=fixture();f.owner.request('en','en','zh-Hans');f.advance(140)
  f.state.ready=false;f.advance(80)
  assert.equal(f.phase(),'waiting')
  f.state.ready=true;f.advance(100)
  assert.equal(f.phase(),'completed')
  f.advance(800);assert.equal(f.phase(),'revealing')
  f.advance(220);assert.equal(f.phase(),'idle')
})

test('stale layout callbacks cannot reveal a newer transition',()=>{
  const f=fixture();f.owner.request('en','en','zh-Hans');f.advance(120)
  const stale=[...f.tasks.values()].map(value=>value.action)
  f.owner.request('zh-Hans','zh-Hans','en')
  for(const action of stale)action()
  assert.equal(f.phase(),'covering')
  f.advance(1400);assert.equal(f.state.locale,'zh-Hans');assert.equal(f.phase(),'idle')
})

test('leave or background commits a pending explicit choice and releases all work',()=>{
  const f=fixture();f.owner.request('en','en','zh-Hans');f.advance(30);f.owner.finish()
  assert.deepEqual(f.applied,['en']);assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
  f.advance(1000);assert.deepEqual(f.applied,['en'])
})

test('unmount and local-data clearing cancel without publishing a pending language',()=>{
  const f=fixture();f.owner.request('en','en','zh-Hans');f.owner.finish(false)
  assert.deepEqual(f.applied,[]);assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
})

test('reduced motion and unchanged resolved locale are immediate',()=>{
  const f=fixture();f.state.reduced=true;f.owner.request('en','en','zh-Hans')
  assert.equal(f.phase(),'idle');assert.deepEqual(f.applied,['en']);assert.equal(f.tasks.size,0)
  f.state.reduced=false;f.owner.request('system','en','en')
  assert.equal(f.phase(),'idle');assert.deepEqual(f.applied,['en','system']);assert.equal(f.tasks.size,0)
})

test('a detached renderer cannot retain an unbounded overlay or animation loop',()=>{
  const f=fixture();f.state.ready=false;f.owner.request('en','en','zh-Hans');f.advance(5300)
  assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
  assert.equal(f.published.some(value=>value.completed),false)
})

test('cancellation during target readiness never publishes a completion check',()=>{
  const f=fixture();f.state.ready=false;f.owner.request('en','en','zh-Hans');f.advance(180)
  f.owner.finish(false);f.advance(6000)
  assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
  assert.equal(f.published.some(value=>value.completed),false)
})

test('a newer language cancels the old completion dwell and its fade',()=>{
  const f=fixture();f.owner.request('en','en','zh-Hans');f.advance(160)
  assert.equal(f.phase(),'completed')
  f.owner.request('zh-Hans','zh-Hans','en')
  assert.equal(f.phase(),'covering')
  f.advance(150);assert.equal(f.phase(),'waiting')
  f.advance(20);assert.equal(f.phase(),'completed')
  assert.equal(f.published.at(-1).target,'zh-Hans')
  f.advance(1100);assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
})

test('a late native rejection cannot cancel a new choice before its language commit',()=>{
  const f=fixture();f.state.ready=false
  f.owner.request('en','en','zh-Hans');f.advance(120)
  const oldNativeRevision=f.owner.revision
  f.owner.request('zh-Hant','zh-Hant','en')
  const currentRevision=f.owner.revision
  f.owner.finish(false,oldNativeRevision)
  assert.equal(f.phase(),'covering');assert.equal(f.owner.revision,currentRevision)
  assert.equal(f.owner.pending,'zh-Hant')
  f.advance(120)
  assert.deepEqual(f.applied,['en','zh-Hant']);assert.equal(f.phase(),'waiting')
  f.owner.finish(false,currentRevision)
  assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
  assert.equal(f.published.some(value=>value.completed),false)
})

test('native picker focus returning after120ms retains readiness and the completion paint',()=>{
  const f=fixture();f.state.ready=false
  let focused=false
  const guard=createLanguageTransitionFocusGuard({owner:f.owner,hasFocus:()=>focused,
    schedule:f.schedule,cancel:f.cancel})
  f.owner.request('en','en','zh-Hans');guard.blur()
  f.advance(250)
  assert.equal(f.phase(),'waiting');assert.deepEqual(f.applied,['en'])
  assert.equal(f.published.some(value=>value.completed),false)
  focused=true;guard.focus();f.advance(300)
  assert.equal(f.phase(),'waiting')
  f.state.ready=true;f.advance(60)
  assert.equal(f.phase(),'completed')
  guard.dispose();f.advance(1100)
  assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
})

test('persistent focus loss cancels at400ms without acknowledging an unready language',()=>{
  const f=fixture();f.state.ready=false
  const guard=createLanguageTransitionFocusGuard({owner:f.owner,hasFocus:()=>false,
    schedule:f.schedule,cancel:f.cancel})
  f.owner.request('en','en','zh-Hans');guard.blur();f.advance(399)
  assert.equal(f.phase(),'waiting')
  f.advance(1)
  assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
  assert.equal(f.published.some(value=>value.completed),false)
  assert.deepEqual(f.applied,['en'])
})

test('hide or pagehide immediately releases blur work and never draws a completion check',()=>{
  const f=fixture();f.state.ready=false
  const guard=createLanguageTransitionFocusGuard({owner:f.owner,hasFocus:()=>false,
    schedule:f.schedule,cancel:f.cancel})
  f.owner.request('en','en','zh-Hans');guard.blur();f.advance(30);guard.finish()
  assert.equal(f.phase(),'idle');assert.equal(f.tasks.size,0)
  assert.deepEqual(f.applied,['en'])
  f.advance(6000)
  assert.equal(f.published.some(value=>value.completed),false)
})

test('an old popup blur cannot cancel a newer locale and disposal releases its timer',()=>{
  const f=fixture();f.state.ready=false
  const guard=createLanguageTransitionFocusGuard({owner:f.owner,hasFocus:()=>false,
    schedule:f.schedule,cancel:f.cancel})
  f.owner.request('en','en','zh-Hans');guard.blur();f.advance(140)
  f.owner.request('zh-Hant','zh-Hant','en');f.advance(300)
  assert.equal(f.phase(),'waiting');assert.equal(f.owner.target,'zh-Hant')
  guard.blur();guard.dispose();f.owner.finish(false);f.advance(6000)
  assert.equal(f.tasks.size,0);assert.equal(f.published.some(value=>value.completed),false)
})

test('desktop blur owns only active frame phases and preserves accessibility fallbacks',()=>{
  const css=readFileSync(new URL('../src/App.css',import.meta.url),'utf8')
  const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8')
  assert.match(app,/data-language-transition=\{languageTransition\.overlay\.phase\}/)
  const frame=css.match(/\.app-frame\s*\{([^}]*)\}/)[1]
  assert.doesNotMatch(frame,/filter|will-change|transform/)
  const fallback=css.slice(css.indexOf('@supports (filter: blur(1px))'),css.indexOf('.language-transition-status'))
  assert.match(fallback,/data-language-transition="covering".*data-language-transition="waiting".*data-language-transition="completed"/)
  assert.match(fallback,/> \.app-frame\s*\{\s*filter: blur\(12px\)/)
  assert.match(fallback,/data-language-transition="revealing"[^}]*filter: blur\(0px\)/)
  assert.doesNotMatch(fallback,/data-language-transition="idle"|will-change|backdrop-filter: blur/)
  const accessibility=css.slice(css.lastIndexOf('@media (prefers-reduced-motion: reduce)'))
  assert.match(accessibility,/prefers-reduced-motion: reduce[^]*filter: none; transition: none/)
  assert.match(accessibility,/prefers-reduced-transparency: reduce[^]*background: var\(--app-background\)[^]*filter: none; transition: none/)
})
