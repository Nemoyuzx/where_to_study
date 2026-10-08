import assert from 'node:assert/strict'
import {readFileSync,readdirSync} from 'node:fs'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import test from 'node:test'

// Static ArkUI modifier contracts only; these checks do not validate rendering
// on a device. A child radius must not satisfy its parent's BorderOptions.
const root=fileURLToPath(new URL('../native/harmony/entry/src/main/ets/',import.meta.url))
const read=file=>readFileSync(path.join(root,file),'utf8').replace(/\r\n?/g,'\n')
const compact=value=>value.replace(/\s+/g,'')

function ignoredEnd(source,index) {
  const char=source[index]
  if(char==='"'||char==="'"||char==='`'){
    for(let i=index+1;i<source.length;i++){
      if(source[i]==='\\')i++
      else if(source[i]===char)return i+1
    }
    throw new Error('Unclosed source string')
  }
  if(source.startsWith('//',index)){
    const end=source.indexOf('\n',index+2);return end<0?source.length:end+1
  }
  if(source.startsWith('/*',index)){
    const end=source.indexOf('*/',index+2);assert.ok(end>=0,'source comment closes');return end+2
  }
  return index
}
function closing(source,opening) {
  const pairs={'(':')','{':'}','[':']'},stack=[pairs[source[opening]]]
  for(let i=opening+1;i<source.length;i++){
    const skipped=ignoredEnd(source,i)
    if(skipped!==i){i=skipped-1;continue}
    if(pairs[source[i]])stack.push(pairs[source[i]])
    else if(source[i]===stack.at(-1)){stack.pop();if(stack.length===0)return i}
  }
  assert.fail('modifier argument closes without crossing an enclosing control')
}
function spacesAndComments(source,index) {
  for(;;){
    while(index<source.length&&/\s/.test(source[index]))index++
    if(source.startsWith('//',index)||source.startsWith('/*',index)){index=ignoredEnd(source,index);continue}
    return index
  }
}
function options(argument) {
  const source=argument.trim()
  if(!source.startsWith('{')||closing(source,0)!==source.length-1)return null
  const entries=[];let begin=1
  for(let i=1;i<source.length-1;i++){
    const skipped=ignoredEnd(source,i)
    if(skipped!==i){i=skipped-1;continue}
    if('({['.includes(source[i])){i=closing(source,i);continue}
    if(source[i]===','){entries.push(source.slice(begin,i).trim());begin=i+1}
  }
  entries.push(source.slice(begin,-1).trim())
  if(entries.some(entry=>entry.startsWith('...')))return null
  return new Map(entries.filter(Boolean).map(entry=>{
    const match=entry.match(/^(\w+|"[^"\\]+"|'[^'\\]+')\s*(?::([\s\S]*))?$/)
    assert.ok(match,`simple BorderOptions property: ${entry}`)
    return [match[1].replace(/^['"]|['"]$/g,''),(match[2]??match[1]).trim()]
  }))
}
function borderChains(source) {
  const found=new Map()
  for(let start=0;start<source.length;start++){
    const skipped=ignoredEnd(source,start)
    if(skipped!==start){start=skipped-1;continue}
    if(!source.startsWith('.borderRadius(',start))continue
    let cursor=start,radius=null,lastBorder=null
    for(;;){
      cursor=spacesAndComments(source,cursor)
      const method=source.slice(cursor).match(/^\.(\w+)\(/)
      if(!method)break
      const opening=cursor+method[0].length-1,end=closing(source,opening)
      const argument=source.slice(opening+1,end)
      if(method[1]==='borderRadius'){radius=argument.trim();lastBorder=null}
      else if(method[1]==='border'&&radius!==null){
        lastBorder={start:cursor,radius,properties:options(argument)}
      }
      cursor=end+1
    }
    if(lastBorder)found.set(lastBorder.start,lastBorder)
  }
  return [...found.values()].sort((left,right)=>left.start-right.start)
}
const expected={
  'view/PlannerView.ets':['8','7','7','6','6','6','6'],
  'view/PrivacyConsentView.ets':['7','7'],
  'view/PrivacyPolicyView.ets':['6'],
  'view/QueryView.ets':['10','10','10','10','10'],
  'view/calendar/CalendarDailyInfoCards.ets':['10','10','10'],
  'view/calendar/ExpandedTeachingCalendarView.ets':['8','6','7','6','6','6','6','6','10','6'],
  'view/calendar/MobileCalendarTimelineView.ets':['9','6','6'],
  'view/calendar/MobileTeachingCalendarView.ets':['10','6','12','8','6','framed ? 10 : 0'],
}

test('the 37 audited round controls repeat their existing radius in the same BorderOptions',()=>{
  assert.equal(Object.values(expected).flat().length,37)
  for(const [file,radii] of Object.entries(expected)){
    for(const source of [read(file),read(file).replaceAll('\n','\r\n')]){
      const chains=borderChains(source)
      assert.deepEqual(chains.map(chain=>compact(chain.radius)),radii.map(compact),file)
      for(const chain of chains){
        assert.ok(chain.properties?.has('radius'),`${file}: BorderOptions owns its radius`)
        assert.equal(compact(chain.properties.get('radius')),compact(chain.radius),file)
      }
    }
  }
})

test('conditional card corners and left-only course emphasis preserve their existing geometry',()=>{
  const mobile=borderChains(read('view/calendar/MobileTeachingCalendarView.ets'))
  const conditional=mobile.find(chain=>chain.radius.includes('framed'))
  assert.equal(compact(conditional.properties.get('radius')),'framed?10:0')
  assert.equal(compact(conditional.properties.get('width')),'framed?1:0')
  const courses=borderChains(read('view/calendar/MobileCalendarTimelineView.ets')).filter(chain=>chain.radius==='6')
  assert.equal(courses.length,2)
  for(const chain of courses){
    assert.equal(compact(chain.properties.get('width')),'{left:3}')
    assert.equal(chain.properties.get('color'),'AppTheme.accent()')
  }
})

test('chain scanning distinguishes cards, buttons and nested children from rectangular grids',()=>{
  const child="Column() { Button('child').borderRadius(8) }.border({ width: 1 })"
  assert.deepEqual(borderChains(child),[],'a child radius cannot round the parent border')
  assert.deepEqual(borderChains('Column() {}.border({ width: { bottom: 1 } })'),[],'rectangular grid lines have no round intent')
  assert.deepEqual(borderChains('Text().borderRadius(6).border({ width: 1 }).borderRadius(6)'),[],'a later radius already restores the final shape')
  const missing=borderChains("Button('action').borderRadius(7).backgroundColor(fill).border({ width: 1, color: ink })")
  assert.equal(missing.length,1)
  assert.equal(missing[0].properties.has('radius'),false,'a filled button missing the property is detected')
  const rounded=borderChains('Column() {}.borderRadius(10).onClick(() => { const example = ".border({})"; }).border({ width: 1, radius: 10 })')
  assert.equal(rounded.length,1)
  assert.equal(rounded[0].properties.get('radius'),'10','callback text cannot become a style owner')
})

test('literal BorderOptions after existing round intent do not omit radius across Harmony view/common components',()=>{
  const files=directory=>readdirSync(directory,{withFileTypes:true}).flatMap(entry=>{
    const file=path.join(directory,entry.name)
    return entry.isDirectory()?files(file):entry.name.endsWith('.ets')?[file]:[]
  })
  for(const file of files(root).filter(file=>/\/(?:view|common|components?)\//.test(file.replaceAll(path.sep,'/')))){
    const source=readFileSync(file,'utf8').replace(/\r\n?/g,'\n')
    for(const chain of borderChains(source)){
      if(chain.properties===null)continue // A dynamic/spread options object needs separate review.
      assert.ok(chain.properties.has('radius'),`${path.relative(root,file)}:${source.slice(0,chain.start).split('\n').length}`)
    }
  }
})
