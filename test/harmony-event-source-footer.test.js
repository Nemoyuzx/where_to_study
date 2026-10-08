import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'

const read=path=>readFileSync(new URL(`../native/harmony/entry/src/main/ets/${path}.ets`,import.meta.url),'utf8').replace(/\r\n?/g,'\n')
const query=read('view/QueryView')
const events=query.slice(query.indexOf('  eventsContent() {'),query.indexOf('  eventRow(item:'))
function closing(source,opening){
  const pairs={'(':')','{':'}','[':']'},stack=[pairs[source[opening]]]
  let quote=null
  for(let i=opening+1;i<source.length;i++){
    const char=source[i]
    if(quote){if(char==='\\')i++;else if(char===quote)quote=null;continue}
    if(char==='"'||char==="'"||char==='`'){quote=char;continue}
    if(char==='/'&&source[i+1]==='/'){i=source.indexOf('\n',i);if(i<0)break;continue}
    if(pairs[char])stack.push(pairs[char])
    else if(char===stack.at(-1)){stack.pop();if(!stack.length)return i}
  }
  assert.fail('event list and item structure must close')
}
const listHeader='List({ space: 9, scroller: this.eventScroller }) {'
const listStart=events.indexOf(listHeader),listOpen=listStart+listHeader.length-1,listEnd=closing(events,listOpen)
const list=events.slice(listStart,listEnd+1)
const footer=query.slice(query.indexOf('  publicEventSourceNotice() {'),query.indexOf('  private routePeriodLabel('))

test('one event-source footer is the last item inside the same virtualized event list for every body state',()=>{
  assert.ok(listStart>0)
  assert.match(list,/ListItem\(\) \{ this\.loadingMessage\('正在读取重要事件', true\) \}/)
  assert.match(list,/ListItem\(\) \{\s*this\.errorMessage\(this\.model\.importantEventsError,[\s\S]*?this\.model\.loadImportantEvents\(true\), true\)/)
  assert.match(list,/ListItem\(\) \{\s*Column\(\{ space: 6 \}\) \{\s*Text\(this\.model\.text\('没有符合条件的重要事件'/)
  assert.match(list,/ForEach\(this\.visibleEvents\(\),[\s\S]*?this\.model\.favoriteDeadlineKey\(item\)/)
  assert.match(list,/ListItem\(\) \{ this\.publicEventSourceNotice\(\) \}\s*\}$/)
  assert.equal((events.match(/this\.publicEventSourceNotice\(\)/g)||[]).length,1)
  assert.doesNotMatch(events.slice(listEnd+1),/sourceCard|publicEventSourceNotice|deadlinePrimaryPage|deadlineMirror|deadlineBackup/)
  assert.doesNotMatch(events,/this\.sourceCard\(/)
  for(const id of ['query.events.search','query.events.show_ended'])assert.ok(events.slice(0,listStart).includes(id))
})

test('the compact source card wraps reviewed copy and links to the same three URLs using the existing opener',()=>{
  assert.match(footer,/\.id\('query\.events\.sources'\)/)
  assert.match(footer,/\.padding\(12\)[\s\S]*?\.borderRadius\(10\)/)
  assert.match(footer,/\.backgroundColor\(AppTheme\.primaryWithAlpha\(0\.08, AppTheme\.state\.dark\)\)/)
  assert.match(footer,/AppTheme\.textOnPrimaryBlend\(0\.08, AppTheme\.state\.dark, true\)/)
  assert.match(footer,/Flex\(\{ wrap: FlexWrap\.Wrap/)
  for(const [label,url,key] of [['GitHub 主源','deadlinePrimaryPage','primary'],['站点镜像','deadlineMirror','mirror'],['备用 API','deadlineBackup','backup']]){
    assert.ok(footer.includes(`this.publicEventSourceLink('${label}', CalendarDailyInfoSources.${url}, '${key}')`))
  }
  assert.match(footer,/\.accessibilityText\(this\.model\.text\(label\)\)/)
  assert.match(footer,/\.onClick\(\(\) => this\.openURL\(url\)\)/)
  assert.doesNotMatch(footer,/\.height\(|maxLines|textOverflow|\.clip\(|loadImportantEvents|fetch\(|connect|setTimeout/)
})

const scrollBody=events.match(/\.onScrollIndex\(\(start: number, end: number, center: number\) => \{([\s\S]*?)\n      \}\)/)?.[1]
assert.ok(scrollBody,'drive the production event-list index callback')
const onScroll=new Function(transformSync(`return function(start: number, end: number, center: number) {${scrollBody}\n}`,
  {loader:'ts',target:'es2022'}).code)()
test('footer indices cannot replace the last event anchor and paging still uses the current cached list',()=>{
  const appended=[],owner={visibleEvents:()=>Array.from({length:20},(_,id)=>({id})),tabContentOpacity:1,
    session:{eventFirstVisibleIndex:7},appendEventPage:index=>appended.push(index)}
  onScroll.call(owner,20,20,20)
  assert.equal(owner.session.eventFirstVisibleIndex,19)
  assert.deepEqual(appended,[20])
  owner.tabContentOpacity=.5
  onScroll.call(owner,4,12,8)
  assert.equal(owner.session.eventFirstVisibleIndex,19)
  assert.deepEqual(appended,[20,12])
})
test('loading, error and empty footer-only lists preserve a saved event anchor without starting paging or requests',()=>{
  const owner={visibleEvents:()=>[],tabContentOpacity:1,session:{eventFirstVisibleIndex:17},
    appendEventPage(){assert.fail('footer-only lists must not page')},model:{loadImportantEvents(){assert.fail('no automatic retry')}}}
  onScroll.call(owner,0,1,0)
  assert.equal(owner.session.eventFirstVisibleIndex,17)
  assert.match(query,/loadingMessage\(message: string, inList: boolean = false\)/)
  assert.match(query,/errorMessage\(message: string, retry: \(\) => void, inList: boolean = false\)/)
  assert.equal((query.match(/\.layoutWeight\(inList \? 0 : 1\)/g)||[]).length,2)
})
test('short source links reuse existing reviewed translations in every supported Harmony locale',()=>{
  const module={exports:{}}
  new Function('module','exports',transformSync(read('common/AppLocalizationCatalog'),{loader:'ts',format:'cjs'}).code)(module,module.exports)
  for(const locale of ['zh-Hant','ja','es','pt','ru','ar','tr','th','ms','vi','id']){
    const reviewed=JSON.parse(readFileSync(new URL(`../native/harmony/localizations/${locale}.json`,import.meta.url),'utf8'))
    for(const key of ['GitHub 主源','站点镜像','备用 API'])assert.equal(module.exports.AppLocalizationCatalog.text(key,locale),reviewed[key])
  }
  for(const key of ['GitHub 主源','站点镜像','备用 API'])assert.ok(read('common/AppLocalization').includes(`'${key}':`))
})
