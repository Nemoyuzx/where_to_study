import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'

const read=name=>readFileSync(new URL(`../native/harmony/entry/src/main/ets/view/calendar/${name}.ets`,import.meta.url),'utf8')
const source=read('CalendarLogic')
const pure=source.slice(source.indexOf('export class TeachingCalendarLogic {'),source.indexOf('export class CalendarPageTransitionOffsets {'))
const {code}=transformSync(pure,{loader:'ts',format:'esm'})
const {TeachingCalendarLogic:logic}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`)

test('actual Almanac policy uses current natural translated width and wraps at narrow/font-scaled capacities',()=>{
  assert.equal(logic.almanacAdviceLabelWidth(300,80),92)
  assert.equal(logic.almanacAdviceLabelWidth(300,12),24)
  assert.equal(logic.almanacAdviceUsesVertical(300,80,1),false)
  assert.equal(logic.almanacAdviceUsesVertical(160,80,1),true)
  assert.equal(logic.almanacAdviceUsesVertical(160,12,1),false)
  assert.equal(logic.almanacAdviceUsesVertical(120,80,1),true)
  assert.equal(logic.almanacAdviceUsesVertical(300,128,1.6),true)
  assert.equal(logic.almanacAdviceUsesVertical(300,160,2),true)
  for(const width of [0,24,120,160,300]) for(const measured of [12,32,80,160,320]) {
    assert.ok(logic.almanacAdviceLabelWidth(width,measured)<=width)
  }
})

test('native Almanac rows wire real area/font measurement and keep raw text with no fixed height or ellipsis',()=>{
  const cards=read('CalendarDailyInfoCards')
  const rows=cards.slice(cards.indexOf('  almanacAdviceRow('),cards.indexOf('  publicDeadlineCard('))
  assert.match(rows,/this\.almanacAdviceWidth = Number\(newArea\.width\)/)
  assert.match(rows,/this\.updateAlmanacFontScale\(\)/)
  assert.match(cards,/AppContext\.get\(\)\.config\.fontSizeScale/)
  assert.match(rows,/getMeasureUtils\(\)\.measureText/)
  assert.match(rows,/textContent: this\.model\.text\(label\)/)
  assert.match(rows,/fontSize: \(12 \* this\.almanacFontScale\)/)
  assert.match(rows,/almanacAdviceUsesVertical/)
  assert.match(rows,/Column\(\{ space: 8 \}\)/)
  assert.match(rows,/Row\(\{ space: 8 \}\)/)
  assert.match(rows,/Text\(value\)/)
  assert.doesNotMatch(rows,/Text\(this\.model\.text\(value\)\)|\.height\(|\.maxLines\(|\.textOverflow\(|Scroll/)
  assert.match(rows,/\.fontColor\(Color\.White\)/)
  assert.match(rows,/\.backgroundColor\(color\)/)
})
