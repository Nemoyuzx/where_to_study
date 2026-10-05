import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
import {transformSync} from 'esbuild'

const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8')
const harmonyRoot='native/harmony/entry/src/'
const view=read(harmonyRoot+'main/ets/view/QueryView.ets')
const android=read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/InformationQueryPage.kt')
function load(path,injected={}){
  const source=read(harmonyRoot+path).replace(/^import[\s\S]*?;\r?\n/gm,'')
    .replace(/@ObservedV2\s*/g,'').replace(/@Trace\s+/g,'')
  const module={exports:{}}
  vm.runInNewContext(transformSync(source,{loader:'ts',format:'cjs',target:'es2022'}).code,
    {...injected,module,exports:module.exports,setTimeout,clearTimeout})
  return module.exports
}
const query=load('main/ets/common/QueryLogic.ets')
const shuttle=load('main/ets/net/ShuttleBusClient.ets')
const {QuerySession}=load('main/ets/view/QuerySession.ets',{...query,...shuttle})
const dedicated=[]
load('test/QuerySession.test.ets',{QuerySession,...query,...shuttle,
  describe:(_name,work)=>work(),it:(name,_level,work)=>dedicated.push({name,work}),
  expect:value=>({assertTrue:()=>assert.equal(value,true),assertFalse:()=>assert.equal(value,false),
    assertEqual:expected=>assert.equal(value,expected)})}).default()
for(const {name,work} of dedicated)test('production Harmony QuerySession: '+name,work)

function disclosure({reduced=false,animator='1',transition='1',width=390}={}){
  const source=view.slice(view.indexOf('  private reduceFullTimetableMotion()'),view.indexOf('  private selectedTab()'))
  assert.ok(source.includes('private toggleFullTimetable()'),'drive the actual production handler')
  const animations=[]
  const context={Curve:{EaseOut:'ease-out'},accessibility:{isAnimationReduceEnabledSync:()=>reduced},
    settings:{display:{ANIMATOR_DURATION_SCALE:'animator',TRANSITION_ANIMATION_SCALE:'transition'},
      getValueSync:(_context,key)=>key==='animator'?animator:transition}}
  vm.runInNewContext(transformSync('class DisclosureHarness {\n'+source+'\n}\nglobalThis.DisclosureHarness=DisclosureHarness',
    {loader:'ts',target:'es2022'}).code,context)
  const owner=new context.DisclosureHarness(),session=new QuerySession()
  Object.assign(owner,{session,contentWidth:width,fullTimetableMotionDuration:160,
    getUIContext:()=>({getHostContext:()=>({}),animateTo:(options,work)=>{animations.push(options);work()}})})
  return {owner,session,animations}
}
test('production Harmony disclosure is initially collapsed at every width and fast toggles only change presentation',()=>{
  for(const width of [320,390,700,840,1180]){
    const f=disclosure({width}),cached={generatedAt:'synthetic-cached'}
    f.session.shuttleSnapshot=cached
    f.session.shuttleFetchedAtMillis=12345
    f.session.shuttleError='retained-last-good'
    f.session.regularScrollOffsets.set('shuttle',120)
    f.session.loadShuttle=()=>{throw Error('disclosure must not fetch')}
    assert.equal(f.session.fullTimetableExpanded,false)
    for(let index=0;index<51;index++)f.owner.toggleFullTimetable()
    assert.equal(f.session.fullTimetableExpanded,true)
    assert.equal(f.animations.length,51)
    assert.ok(f.animations.every(options=>options.duration===160&&!options.onFinish))
    f.session.detachView();f.session.attachView()
    assert.equal(f.session.fullTimetableExpanded,true)
    assert.equal(f.session.shuttleSnapshot,cached)
    assert.equal(f.session.shuttleFetchedAtMillis,12345)
    assert.equal(f.session.shuttleError,'retained-last-good')
    assert.equal(f.session.regularScrollOffsets.get('shuttle'),120)
    assert.equal(new QuerySession().fullTimetableExpanded,false)
    f.session.dispose()
  }
})
test('production Harmony disclosure reads Reduce Motion and both zero system animation scales on every action',()=>{
  for(const options of [{reduced:true},{animator:'0'},{transition:'0'}]){
    const f=disclosure(options)
    f.owner.toggleFullTimetable()
    f.owner.toggleFullTimetable()
    assert.equal(f.session.fullTimetableExpanded,false)
    assert.ok(f.animations.every(animation=>animation.duration===0))
  }
})
test('native disclosure boundaries keep current service and source footer outside the gated timetable body',()=>{
  const h=view.slice(view.indexOf('  shuttleFullTimetable('),view.indexOf('  shuttleRouteCard('))
  const a=android.slice(android.indexOf('tag = "information.query.shuttle.full-timetable"'),android.indexOf('private fun fullTimetableCell'))
  assert.match(h,/Text\(daily\.scheduleNotice\.title\)[\s\S]*?if \(this\.session\.fullTimetableExpanded\)[\s\S]*?ForEach\(daily\.scheduleNotice\.schedules/)
  assert.match(h,/sys\.symbol\.chevron_down/)
  assert.match(h,/accessibilityStateDescription\(this\.model\.text\(this\.session\.fullTimetableExpanded \? '已展开' : '已折叠'\)\)/)
  assert.match(h,/minHeight: ControlMetrics\.height/)
  assert.match(view,/this\.shuttleStatusCard\(daily\)[\s\S]*this\.shuttleScheduleGrid\(daily\)[\s\S]*this\.shuttleFullTimetable\(daily\)[\s\S]*this\.shuttleSourceCard\(\)/)
  assert.match(a,/ic_chevron_down/)
  assert.match(a,/visibility = if \(sessionState\.fullTimetableExpanded\) View\.VISIBLE else View\.GONE/)
  assert.match(a,/DisclosureMotionController\(this, viewport, indicator, onDetached/)
  assert.match(a,/ViewCompat\.setStateDescription/)
  assert.match(a,/ACTION_EXPAND[\s\S]*ACTION_COLLAPSE/)
  assert.match(a,/addView\(shuttleSourceFooter\(snapshot\.sourcePage\)\)/)
  const handler=a.slice(a.indexOf('header.setOnClickListener'),a.indexOf('addView(header)'))
  assert.doesNotMatch(handler,/Repository|\.load\(|force\s*=|snapshot\s*=/)
  const controller=read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/DisclosureMotionController.kt')
  assert.match(controller,/!ValueAnimator\.areAnimatorsEnabled\(\)/)
  assert.match(controller,/onViewDetachedFromWindow[\s\S]*?cancel\(\)/)
})
