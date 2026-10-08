import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'

const read=path=>readFileSync(new URL(`../native/harmony/entry/src/main/ets/${path}.ets`,import.meta.url),'utf8').replace(/\r\n?/g,'\n')
const logic=read('common/CourseLogic'),session=read('view/CourseSession'),view=read('view/CourseView')
const snapshotSource=read('net/QMPlusSnapshot')
const policy=snapshotSource.slice(snapshotSource.indexOf('export class QMPlusCourseworkPolicy'),snapshotSource.indexOf('export class QMPlusSnapshot {'))
const source=(policy+logic+session).replace(/^import[^\n]+\n/gm,'').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s+/g,'')
const module={exports:{}}
new Function('module','exports',transformSync(source,{loader:'ts',format:'cjs',target:'es2022'}).code)(module,module.exports)
const {CourseQMPlusScope:scope,CourseSession}=module.exports
const courses=[{id:'current',name:' EBU Current',currentTermStatus:'current'},
  {id:'other',name:'ebu History',currentTermStatus:'other'},
  {id:'unknown',name:'EBU Undated',currentTermStatus:'unknown'},
  {id:'foreign',name:'Course EBU',currentTermStatus:'other'}]
const activity=(id,courseID,kind='assignment',title=id)=>({id,courseID,kind,title,dueAt:null,closesAt:null,status:'unknown'})
const snapshot={fetchedAt:'2026-10-09T00:00:00.000Z',partial:true,courses,
  activities:[activity('current-a','current'),activity('history-undated','other'),activity('history-quiz','other','quiz'),
    activity('unknown-a','unknown'),activity('foreign-a','foreign'),activity('forum','other','forum'),
    activity('admin','other','assignment','Coursework Mark Review Request')]}

test('Harmony matches Apple current plus unknown default and shows only cached EBU history on demand',()=>{
  const before=JSON.stringify(snapshot),owner=new CourseSession()
  assert.equal(owner.showsOtherQMplusTerms,false)
  assert.deepEqual(scope.visibleCourses(snapshot,owner.showsOtherQMplusTerms).map(course=>course.id),['current','unknown'])
  assert.equal(scope.hasHistoricalCourses(snapshot),true)
  owner.showsOtherQMplusTerms=true
  assert.deepEqual(scope.visibleCourses(snapshot,owner.showsOtherQMplusTerms).map(course=>course.id),['current','other','unknown'])
  assert.equal(scope.hasHistoricalCourses({...snapshot,courses:[courses[2],courses[3]]}),false,
    'unknown and non-EBU courses never create a history switch')
  assert.deepEqual(scope.visibleCourses(null,true),[])
  assert.equal(scope.hasHistoricalCourses(null),false)
  assert.equal(JSON.stringify(snapshot),before)
})
test('cached historical and unknown activities keep undated items and administrative filters without changing calendar scope',()=>{
  assert.deepEqual(scope.activitiesForCourse(snapshot,'other').map(item=>item.id),['history-undated','history-quiz'])
  assert.deepEqual(scope.activitiesForCourse(snapshot,'unknown').map(item=>item.id),['unknown-a'])
  assert.deepEqual(scope.activitiesForCourse(snapshot,'foreign'),[])
  assert.deepEqual(scope.activitiesForCourse(null,'current'),[])
  assert.deepEqual(scope.currentActivities(snapshot).map(item=>item.id),['current-a'])
  assert.equal(scope.activitiesForCourse(snapshot,'other')[0],snapshot.activities[1])
})
test('history selection lives in the root-owned course session and changes no cache, expansion or detail ownership',()=>{
  const owner=new CourseSession();owner.scrollOffsets.set('current',172);owner.toggleExpanded('qmplus','other')
  owner.showsOtherQMplusTerms=true;owner.openCourse('qmplus','other');owner.closeCourse()
  assert.equal(owner.showsOtherQMplusTerms,true)
  assert.equal(owner.isExpanded('qmplus','other'),true)
  assert.equal(owner.scrollOffsets.get('current'),172)
  const toggle=view.slice(view.indexOf('if (this.hasHistoricalQMPlusCourses())'),view.indexOf('if (this.visibleQMPlusCourses().length === 0)'))
  assert.match(toggle,/this\.model\.text\('显示其他学期／历史课程'\)/)
  assert.match(toggle,/\.onChange\(\(enabled: boolean\): void => \{ this\.session\.showsOtherQMplusTerms = enabled; \}\)/)
  assert.match(toggle,/\.enabled\(!this\.model\.isSampleMode\(\)\)/)
  assert.doesNotMatch(toggle,/load|fetch|openLogin|Connect|clear|\.height\(|maxLines|textOverflow/)
  const qm=view.slice(view.indexOf('  qmPlusSection()'),view.indexOf('  qmPlusCourseRow('))
  assert.ok(qm.indexOf('courses.qmplus.other-terms')<qm.indexOf('ForEach(this.visibleQMPlusCourses()'))
  const disappear=view.slice(view.indexOf('  aboutToDisappear()'),view.indexOf('  private selectedTab()'))
  assert.doesNotMatch(disappear,/showsOtherQMplusTerms/)
})
test('course header and tabs stay compact while each source keeps count, time and failure status below its body',()=>{
  const header=view.slice(view.indexOf('  build()'),view.indexOf('      Scroll(this.contentScroller)'))
  assert.match(header,/Column\(\{ space: 8 \}\)/)
  assert.match(header,/PageTitle\([\s\S]*?this\.tabPicker\(\)/)
  assert.doesNotMatch(header,/overviewCount|overview\.count|QMplus EBU|CourseStatus/)
  const tab=view.slice(view.indexOf('  tabLabel('),view.indexOf('  currentCoursesContent()'))
  assert.match(tab,/constraintSize\(\{ minHeight: ControlMetrics\.height \}\)/)
  assert.doesNotMatch(tab,/\.height\(|maxLines|textOverflow|clip\(/)
  for(const [start,end,list,status] of [['  cloudCourseSection()','  courseBookIcon()','ForEach(this.cloudCourseGroups()','Text(this.cloudCourseStatus())'],
    ['  qmPlusSection()','  qmPlusCourseRow(','ForEach(this.visibleQMPlusCourses()','Text(this.qmPlusCourseStatus())']]){
    const section=view.slice(view.indexOf(start),view.indexOf(end))
    assert.ok(section.indexOf(list)<section.indexOf(status))
  }
  const status=view.slice(view.indexOf('  private qmPlusCourseStatus()'),view.indexOf('  private toggleCourseInline('))
  for(const marker of ['this.visibleQMPlusCourses().length','snapshot.fetchedAt','snapshot.partial','showingStalePartial','errorCode'])assert.ok(status.includes(marker),marker)
  assert.doesNotMatch(status,/new Date|Date\.now|load|fetch\(|openLogin/)
})
test('production source footers count the selected cached courses and retain original failure and timestamp evidence',()=>{
  const method=name=>{
    const start=view.indexOf('  private '+name+'('),end=view.indexOf('\n  }',start)+4
    assert.ok(start>=0&&end>start)
    return view.slice(start,end)
  }
  const create=new Function('CourseQMPlusScope',transformSync('class StatusHarness {\n'+
    ['cloudCourseStatus','qmPlusCourseStatus','visibleQMPlusCourses'].map(method).join('\n')+
    '\n}\nreturn StatusHarness',{loader:'ts',target:'es2022'}).code)
  const owner=new (create(scope))()
  Object.assign(owner,{session:new CourseSession(),qmPlusSession:{snapshot,error:'Offline',errorCode:'LOCAL_ONLY',showingStalePartial:true},
    model:{text:value=>value,cloudCoursesFetchedAt:snapshot.fetchedAt,cloudCoursesError:'Cloud offline'},
    cloudCourseGroups:()=>[{id:'cloud'}]})
  assert.match(owner.qmPlusCourseStatus(),/^2 门课程 · /)
  assert.ok(owner.qmPlusCourseStatus().includes(snapshot.fetchedAt))
  assert.ok(owner.qmPlusCourseStatus().includes('部分课程或活动无法读取'))
  assert.ok(owner.qmPlusCourseStatus().includes('继续显示上次完整资料'))
  assert.ok(owner.qmPlusCourseStatus().includes('Offline (LOCAL_ONLY)'))
  owner.session.showsOtherQMplusTerms=true
  assert.match(owner.qmPlusCourseStatus(),/^3 门课程 · /)
  assert.equal(owner.cloudCourseStatus(),`1 门课程 · 更新时间：${snapshot.fetchedAt} · Cloud offline`)
  assert.equal(owner.qmPlusSession.snapshot,snapshot)
})
test('the history UI reuses reviewed Apple translation keys in every supported Harmony locale',()=>{
  const keys=['QMplus 课程与活动','显示其他学期／历史课程','当前筛选没有本学期或学期未确认的课程。','%d 门课程']
  const catalogSource=read('common/AppLocalizationCatalog'),catalogModule={exports:{}}
  new Function('module','exports',transformSync(catalogSource,{loader:'ts',format:'cjs'}).code)(catalogModule,catalogModule.exports)
  for(const locale of ['zh-Hant','ja','es','pt','ru','ar','tr','th','ms','vi','id']){
    const reviewed=JSON.parse(readFileSync(new URL(`../native/harmony/localizations/${locale}.json`,import.meta.url),'utf8'))
    for(const key of keys)assert.equal(catalogModule.exports.AppLocalizationCatalog.text(key,locale),reviewed[key])
  }
  for(const key of keys)assert.ok(read('common/AppLocalization').includes(`'${key}':`))
})
