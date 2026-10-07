import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

// Source/flag contracts only, not an Android input-dispatch or physical-device test.
const source=readFileSync(new URL('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/QmplusActivity.kt',import.meta.url),'utf8')
const between=(start,end)=>{
  const first=source.indexOf(start),last=source.indexOf(end,first)
  assert.ok(first>=0&&last>first)
  return source.slice(first,last)
}
const initial=between('override fun onCreate(', 'Palette.configure(this)')
const reveal=between('private fun revealOfficialWindow(', 'private fun beginSync(')
const hide=between('private fun hideForSync(', 'private fun startVerifiedSync(')
const bits={FLAG_SECURE:1,FLAG_NOT_TOUCHABLE:2}
function applyActualFlagStatements(state,body){
  for(const [,operation,expression] of body.matchAll(/window\.(addFlags|clearFlags)\(([^)]+)\)/g)){
    const mask=expression.split(/\s+or\s+/).reduce((mask,name)=>{
      const flag=name.trim().replace('WindowManager.LayoutParams.','')
      assert.ok(flag in bits,`unexpected window flag ${flag}`)
      return mask|bits[flag]
    },0)
    state=operation==='addFlags'?state|mask:state&~mask
  }
  return state
}
test('Android initial hidden QM window declares both secure and non-touchable flags before browser setup',()=>{
  assert.equal(applyActualFlagStatements(0,initial),bits.FLAG_SECURE|bits.FLAG_NOT_TOUCHABLE)
  assert.match(source,/alpha = 0f/)
})
test('official MFA reveal restores touch while subsequent quiet sync preserves secure non-touchable state',()=>{
  assert.match(source,/verificationRequired = \{ weakOwner\.get\(\)\?\.revealOfficialWindow\(verification = true\) \}/)
  assert.match(reveal,/browserRoot\?\.alpha = 1f/)
  assert.match(hide,/browserRoot\?\.alpha = 0f/)
  const initialFlags=applyActualFlagStatements(0,initial)
  const visible=applyActualFlagStatements(initialFlags,reveal)
  assert.equal(visible,bits.FLAG_SECURE)
  assert.equal(applyActualFlagStatements(visible,hide),bits.FLAG_SECURE|bits.FLAG_NOT_TOUCHABLE)
})
test('window transition never clears secure or changes focus/lifecycle policy',()=>{
  assert.doesNotMatch(source,/clearFlags\([^)]*FLAG_SECURE|FLAG_NOT_FOCUSABLE/)
  for(const body of [reveal,hide]) assert.doesNotMatch(body,/requestFocus\(|clearFocus\(|moveTaskToBack\(/)
  assert.match(source,/override fun onPause\(\)[\s\S]*?authFlow\?\.suspend\(\)/)
})

const insetOwner=between('private fun applySystemInsets(', 'private fun reportDiagnosticPhase(')
const paddingExpression=/view\.setPadding\(([^)]+)\)/.exec(insetOwner)?.[1]
assert.ok(paddingExpression)
const paddingTerms=paddingExpression.split(',').map(term=>{
  const match=/^\s*(base(?:Left|Top|Right|Bottom))\s*\+\s*safe\.(left|top|right|bottom)\s*$/.exec(term)
  assert.ok(match,'padding must use the bounded base-plus-inset expression')
  return {base:match[1],edge:match[2]}
})
assert.deepEqual(paddingTerms.map(term=>[term.base,term.edge]),[
  ['baseLeft','left'],['baseTop','top'],['baseRight','right'],['baseBottom','bottom'],
])
function applyActualPadding(baseLeft,baseTop,baseRight,baseBottom,safe){
  const base={baseLeft,baseTop,baseRight,baseBottom}
  return paddingTerms.map(term=>base[term.base]+safe[term.edge])
}
const union=(...sources)=>Object.fromEntries(['left','top','right','bottom'].map(edge=>[edge,Math.max(...sources.map(source=>source[edge]||0))]))

test('QM safe-area root owns system bars, cutout and IME once and consumes child insets',()=>{
  assert.match(insetOwner,/getInsets\(WindowInsets\.Type\.systemBars\(\) or WindowInsets\.Type\.displayCutout\(\) or WindowInsets\.Type\.ime\(\)\)/)
  assert.match(insetOwner,/setDecorFitsSystemWindows\(false\)/)
  assert.match(insetOwner,/SOFT_INPUT_ADJUST_NOTHING/)
  assert.match(insetOwner,/WindowInsets\.CONSUMED/)
  assert.match(insetOwner,/SOFT_INPUT_ADJUST_RESIZE/)
  assert.match(source,/applySystemInsets\(root\)[\s\S]*?setContentView\(root\); root\.requestApplyInsets\(\)/)
})
test('repeated portrait insets and IME show-hide preserve base padding without accumulating',()=>{
  assert.match(insetOwner,/val baseLeft = root\.paddingLeft; val baseTop = root\.paddingTop/)
  assert.match(insetOwner,/val baseRight = root\.paddingRight; val baseBottom = root\.paddingBottom/)
  const bars={top:24,bottom:24},cutout={top:40}
  const ordinary=union(bars,cutout),keyboard=union(bars,cutout,{bottom:320})
  assert.deepEqual(applyActualPadding(0,0,0,0,ordinary),[0,40,0,24])
  assert.deepEqual(applyActualPadding(0,0,0,0,ordinary),[0,40,0,24])
  assert.deepEqual(applyActualPadding(0,0,0,0,keyboard),[0,40,0,320])
  assert.deepEqual(applyActualPadding(0,0,0,0,ordinary),[0,40,0,24])
})
test('landscape cutouts protect both sides and fallback errors use the same inset owner',()=>{
  const landscape=union({right:24},{left:60,right:48})
  assert.deepEqual(applyActualPadding(0,0,0,0,landscape),[60,0,48,0])
  assert.deepEqual(applyActualPadding(20,20,20,20,landscape),[80,20,68,20])
  assert.match(source,/applySystemInsets\(errorView\); setContentView\(errorView\); errorView\.requestApplyInsets\(\)/)
})
