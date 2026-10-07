import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'

const read=path=>readFileSync(new URL(`../native/harmony/entry/src/main/ets/${path}.ets`,import.meta.url),'utf8')
const source=read('view/calendar/CalendarLogic')
const pureClass=source.slice(source.indexOf('export class TeachingCalendarLogic {'),source.indexOf('export class CalendarPageTransitionOffsets {'))
const {code}=transformSync(pureClass,{loader:'ts',format:'esm'})
const {TeachingCalendarLogic:logic}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`)
const mobile=read('view/calendar/MobileTeachingCalendarView')

test('actual Harmony month policy fills every measured six-row capacity without the old cap',()=>{
  for(const height of [120,240,360,456,720,1020]) for(const header of [26,74,132]) {
    const capacity=Math.max(height-96-header-8-28,0)
    const row=logic.measuredExpandedMonthCellHeight(height,96,header)
    assert.ok(capacity-row*6>=0 && capacity-row*6<6)
    for(const position of [0,.001,.5,1,1.001,1.5,2]) {
      const stageRow=logic.monthRowHeight(position,0,3,row)
      assert.equal(logic.monthRowHeight(position,5,3,row),stageRow)
      assert.ok(logic.monthGridViewportHeight(position,6,stageRow)<=capacity)
      assert.ok(logic.monthDetailsTopGap(position,capacity)<=capacity)
    }
    const compact=Math.min(46,row)
    assert.equal(logic.monthGridTranslationY(2,3,compact),-3*compact)
  }
  assert.equal(logic.measuredExpandedMonthCellHeight(1020,96,26),143)
  assert.equal(logic.measuredExpandedMonthCellHeight(240,96,26),13)
})

test('actual navigation policy separates unmeasured, hidden, non-overlapping and resized geometry',()=>{
  for(const [top,height,navTop,navBottom,visible,expected] of [
    [100,720,-1,-1,true,96],[100,720,732,792,true,96],
    [100,720,700,760,true,128],[100,720,732,792,false,0],
    [100,720,732,732,true,0],[100,720,0,60,true,0],
    [100,720,900,960,true,0],[40,320,284,344,true,84],
    [100,36,0,150,true,36],[100,36,-1,-1,true,36],
  ]) assert.equal(logic.monthNavigationBottomInset(top,height,navTop,navBottom,visible,96),expected)
  assert.equal(logic.monthDetailsTopGap(0,100),0)
  assert.equal(logic.monthDetailsTopGap(.001,100),.008)
  assert.equal(logic.monthDetailsTopGap(1,3),3)
})

test('actual Harmony gesture maps physical displacement across unequal measured segments',()=>{
  const physical=p=>Math.min(p,1)*323+Math.max(p-1,0)*230
  for(const start of [0,.25,.75,1,1.25,1.75,2]) for(const delta of [-600,-300,-25,0,25,300,600]) {
    const position=logic.monthSheetDragPosition(delta,start,323,230)
    assert.ok(Math.abs(physical(position)-Math.min(Math.max(physical(start)-delta,0),553))<.001)
  }
  assert.equal(logic.monthSheetDragPosition(-100,.5,0,0),.5)
  assert.equal(logic.monthSheetDragPosition(-115,0,0,230),1.5)
  assert.equal(logic.monthSheetDragPosition(-1,1,323,0),2)
  assert.equal(logic.monthSheetDragPosition(1,1,0,230),0)
  assert.equal(logic.monthSheetDragPosition(NaN,1,323,230),1)
  assert.match(mobile,/this\.monthExpandedTravel = 6 \* \(expanded - compact\)/)
  assert.match(mobile,/this\.monthWeekTravel = 5 \* compact/)
  assert.match(mobile,/offsetY, this\.monthDragStartPosition, this\.monthExpandedTravel, this\.monthWeekTravel/)
})

test('month-only bounds use native measurements and preserve mounted scrollers and page identities',()=>{
  const root=read('view/RootView'),section=read('view/CalendarSectionView')
  assert.match(root,/phoneNavigationGlobalTop = height > 0 \? top : -1/)
  assert.match(root,/phoneNavigationGlobalBottom = height > 0 \? top \+ height : -1/)
  assert.match(section,/phoneNavigationGlobalTop: this\.phoneNavigationGlobalTop/)
  assert.match(mobile,/this\.contentGlobalTop = Number\(newArea\.globalPosition\.y\)/)
  assert.match(mobile,/this\.monthHeaderHeight = Number\(newArea\.height\)/)
  assert.match(mobile,/this\.incomingMonthHeaderHeight = Number\(newArea\.height\)/)
  const month=mobile.slice(mobile.indexOf('  monthView('),mobile.indexOf('  private selectedMonthWeekIndex('))
  assert.match(month,/\.height\(this\.monthUsableHeight\(\)\)/)
  assert.match(month,/monthDetailsTopGap/)
  assert.match(month,/Visibility\.Visible : Visibility\.None/)
  assert.match(month,/this\.monthDetailsScroller : this\.incomingMonthDetailsScroller/)
  assert.doesNotMatch(month,/minimumContentBottomInsetVp|resetMonthDetailsScroll|prewarm|connectQm|\.opacity\(0\)/)
  const measured=mobile.slice(mobile.indexOf('  private expandedMonthCellHeight('),mobile.indexOf('  private monthRowHeight('))
  assert.doesNotMatch(measured,/Math\.min|Math\.max\(44|monthExpandedCellHeight/)
})
