import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read=name=>readFileSync(new URL('../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/'+name,import.meta.url),'utf8')
test('folding clips natural-size bodies rather than squeezing rows',()=>{
  const viewport=read('NaturalDisclosureViewport.kt')
  assert.match(viewport,/MeasureSpec\.UNSPECIFIED/)
  assert.match(viewport,/clipChildren = true/)
  assert.match(viewport,/y \+ child\.measuredHeight/)
  assert.match(read('SettingsPage.kt'),/NaturalDisclosureViewport[\s\S]*DisclosureMotionController/)
})
test('shuttle heading remains visible with independent period and direction folds',()=>{
  const query=read('InformationQueryPage.kt')
  assert.match(query,/shuttleTimetableDisclosure\("period\.\$periodKey"/)
  assert.match(query,/shuttleTimetableDisclosure\("direction\.\$directionKey"/)
  assert.match(query,/expandedTimetablePeriods/)
  assert.match(query,/expandedTimetableDirections/)
  assert.doesNotMatch(query,/visibility = if \(sessionState\.fullTimetableExpanded\)/)
  assert.match(query,/addView\(shuttleSourceFooter\(snapshot\.sourcePage\)\)/)
})
test('language success waits for readiness and fences two haptic pulses',()=>{
  const transition=read('LanguageChangeTransition.kt')
  assert.match(transition,/stableLayout\.observe[\s\S]*completionIcon\?\.play\(reducedMotion\)[\s\S]*playSuccessHaptics\(token\)/)
  assert.match(transition,/revision\.get\(\) == token[\s\S]*hasWindowFocus\(\)/)
  assert.match(transition,/postDelayed\(it, 120\)/)
  assert.match(transition,/secondHaptic\?\.let\(handler::removeCallbacks\)/)
  assert.match(read('LanguageSuccessMark.kt'),/PathMeasure[\s\S]*getSegment/)
})
test('system network assistance has its own settings surface',()=>{
  const settings=read('SettingsPage.kt')
  assert.match(settings,/tag = "settings\.network-assistance"[\s\S]*"系统网络辅助"/)
  assert.match(settings,/if \(savedCredentials != credentials\) \{\s*activity\.clearCalendarAssignmentData\(\)/)
})
