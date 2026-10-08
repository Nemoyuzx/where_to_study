import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read=path=>readFileSync(new URL(`../native/harmony/entry/src/main/ets/${path}`,import.meta.url),'utf8').replace(/\r\n?/g,'\n')
const view=read('view/CourseView.ets')
const compact=value=>value.replace(/\s+/g,'')

// Read each actual modifier chain. A rounded parent card must never make an
// unrounded Button pass; nested callbacks and custom Button content stay local.
function closing(source,opening) {
  const pairs={'(':')','{':'}','[':']'},stack=[pairs[source[opening]]]
  let quote=null
  for(let i=opening+1;i<source.length;i++){
    const char=source[i]
    if(quote){if(char==='\\')i++;else if(char===quote)quote=null;continue}
    if(char==='"'||char==="'"||char==='`'){quote=char;continue}
    if(char==='/'&&source[i+1]==='/'){i=source.indexOf('\n',i);if(i<0)break;continue}
    if(pairs[char])stack.push(pairs[char])
    else if(char===stack.at(-1)){stack.pop();if(stack.length===0)return i}
  }
  assert.fail('Button arguments, content and modifier calls must close')
}
function buttons(source) {
  const controls=[]
  for(const match of source.matchAll(/\bButton\(/g)){
    const start=match.index,open=start+'Button'.length,argumentsEnd=closing(source,open)
    let cursor=argumentsEnd+1,content=''
    const skip=()=>{while(/\s/.test(source[cursor]??'')&&cursor<source.length)cursor++}
    skip()
    if(source[cursor]==='{'){
      const end=closing(source,cursor)
      content=source.slice(cursor,end+1);cursor=end+1
    }
    const modifiers=[]
    for(;;){
      skip()
      const modifier=source.slice(cursor).match(/^\.\w+\(/)
      if(!modifier)break
      const end=closing(source,cursor+modifier[0].length-1)
      modifiers.push(source.slice(cursor,end+1));cursor=end+1
    }
    controls.push({args:source.slice(open+1,argumentsEnd),content,modifiers,chain:modifiers.join('')})
  }
  return controls
}

test('all compact course text actions have their own theme-preserving capsule geometry',()=>{
  assert.match(read('common/ControlMetrics.ets'),/static readonly height: number = 32;/)
  for(const source of [view,view.replaceAll('\n','\r\n')]){
    const actions=buttons(source).filter(button=>button.args.trim().length>0)
    assert.equal(actions.length,13)
    for(const button of actions){
      const chain=compact(button.chain)
      assert.ok(chain.includes('.height(ControlMetrics.height)'),button.args)
      assert.equal(button.modifiers.filter(modifier=>modifier.startsWith('.borderRadius(')).length,1,button.args)
      assert.ok(chain.includes('.borderRadius(ControlMetrics.height/2)'),button.args)
      if(chain.includes('.type(ButtonType.Normal)')){
        assert.ok(chain.includes('.backgroundColor(AppTheme.surfaceVariant())'),button.args)
        assert.ok(chain.includes('.fontColor(AppTheme.primary())'),button.args)
      }
    }
  }
})

test('rounded course actions retain refresh gates, cached pagination and original destinations',()=>{
  const actions=buttons(view).filter(button=>button.args.trim().length>0)
  const find=marker=>{
    const found=actions.find(button=>(button.args+button.chain).includes(marker))
    assert.ok(found,marker);return compact(found.chain)
  }
  assert.ok(find("'courses.cloud.refresh'").includes('.enabled(!this.model.cloudCoursesLoading&&!this.model.isSampleMode())'))
  assert.ok(find("'courses.cloud.refresh'").includes('this.model.loadCloudCourseDirectory(true)'))
  assert.ok(find("'前往个人账户'").includes('.onClick(()=>this.onOpenSettings())'))
  assert.ok(find("'courses.qmplus.connect'").includes('.onClick(()=>this.qmPlusSession.openLogin())'))
  for(const button of actions.filter(button=>button.args.includes("'打开教学云平台'")))assert.ok(button.chain.includes('AppContext.get().openLink(CalendarDailyInfoSources.assignments)'))
  assert.ok(find("'打开 QMplus 官方课程页'").includes('this.qmPlusSession.openLogin(course.url??undefined)'))
  assert.ok(find("'打开 QMplus 官方活动页'").includes('this.qmPlusSession.openLogin(item.url)'))
  const pages=actions.filter(button=>button.args.includes("'加载更多'"))
  assert.equal(pages.length,4)
  for(const button of pages){
    assert.match(button.chain,/this\.session\.visible(?:CloudAssignments|QMActivities) \+= 40/)
    assert.doesNotMatch(button.chain,/openLogin|loadCloud|fetch\(/)
  }
})

test('language and official-login back actions use the same compact rounded shape',()=>{
  for(const [file,id] of [['view/LanguagePickerView.ets','settings.language.back'],
    ['view/QMPlusConnectionView.ets','qmplus.login.close']]){
    const action=buttons(read(file)).find(button=>button.chain.includes(`.id('${id}')`))
    assert.ok(action,id)
    assert.ok(compact(action.chain).includes('.height(ControlMetrics.height)'),id)
    assert.ok(compact(action.chain).includes('.borderRadius(ControlMetrics.height/2)'),id)
    assert.ok(compact(action.chain).includes('.backgroundColor(AppTheme.surfaceVariant())'),id)
    assert.ok(compact(action.chain).includes('.fontColor(AppTheme.primary())'),id)
  }
})

test('info, disclosure, tab and course-row touch geometry stay distinct from text actions',()=>{
  const custom=buttons(view).filter(button=>button.args.trim().length===0)
  assert.equal(custom.length,4)
  const icons=custom.filter(button=>/info_circle|chevron_down/.test(button.content))
  assert.equal(icons.length,3)
  for(const button of icons){
    const chain=compact(button.chain)
    assert.ok(chain.includes('.width(ControlMetrics.height).height(ControlMetrics.height).padding(4)'))
    assert.ok(chain.includes('.backgroundColor(Color.Transparent)'))
    assert.doesNotMatch(chain,/borderRadius/)
  }
  const tab=custom.find(button=>button.content.includes('CoursePageContract.symbol'))
  assert.ok(tab)
  assert.ok(compact(tab.chain).includes('.constraintSize({minHeight:ControlMetrics.height})'))
  assert.doesNotMatch(tab.chain,/\.height\(/)
  assert.ok(compact(tab.chain).includes('.borderRadius(8)'))
  assert.doesNotMatch(tab.chain,/ControlMetrics\.height \/ 2/)
  for(const [start,end] of [['  cloudCourseRow(', '  private visibleQMPlusCourses('],['  qmPlusCourseRow(', '  @Builder\n  courseDisclosureButton(']]){
    const row=view.slice(view.indexOf(start),view.indexOf(end))
    assert.match(row,/constraintSize\(\{ minHeight: 64 \}\)/)
    assert.doesNotMatch(row,/borderRadius\(ControlMetrics\.height \/ 2\)/)
  }
})
