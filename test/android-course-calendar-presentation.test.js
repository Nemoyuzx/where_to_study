import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read=name=>readFileSync(new URL(`../native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/${name}.kt`,import.meta.url),'utf8')
const calendar=read('TeachingCalendarPage')
const section=(source,start,end)=>{
  const first=source.indexOf(start),last=source.indexOf(end,first+start.length)
  assert.ok(first>=0 && last>first,`missing source boundary ${start} / ${end}`)
  return source.slice(first,last)
}

test('week all-day events are independent bounded blocks plus the original overflow popup',()=>{
  const week=section(calendar,'private fun allDayStrip(','private fun singleDayAllDayStrip(')
  assert.match(week,/days\.forEach \{ day ->/)
  assert.match(week,/agendaVisibleItemCount\(items\.size, compactWeek = true\)/)
  assert.match(week,/items\.take\(visibleCount\)\.forEach \{ item ->/)
  assert.match(week,/dayWeekAllDayBlock\(day\.date, item, items, compactWeek\)/)
  assert.match(week,/dayWeekAllDayOverflow\(day\.date, items, hiddenCount, compactWeek\)/)
  assert.match(week,/if \(compactWeek\) activity\.dp\(26\)/)
  assert.doesNotMatch(week,/joinToString|ScrollView/)
  const day=section(calendar,'private fun singleDayAllDayStrip(','private fun dayWeekAllDayBlock(')
  assert.match(day,/items\.take\(3\)\.forEach/)
  assert.match(day,/dayWeekAllDayOverflow/)
})

test('assignment blocks and overflow rows route only through validated cached course details',()=>{
  const block=section(calendar,'private fun dayWeekAllDayBlock(','private fun dayWeekAllDayOverflow(')
  assert.match(block,/radius = 10/)
  assert.match(calendar,/CalendarSupplementaryKind\.ASSIGNMENT -> Palette\.assignment/)
  assert.match(block,/CalendarSupplementaryKind\.ASSIGNMENT && courseKey != null && activity\.showCachedCourseDetails\(courseKey\)/)
  assert.match(block,/showDayWeekAllDayDialog\(day, items\)/)
  assert.doesNotMatch(block,/loadAssignments|loadCourses|connectQmplus|https?:/)
  const popup=section(calendar,'private fun showDayWeekAllDayDialog(','private fun supplementaryAccent(')
  assert.match(popup,/courseDetailKey = item\.courseDetailKey\.takeIf \{ item\.kind == CalendarSupplementaryKind\.ASSIGNMENT \}/)
  assert.match(popup,/if \(activity\.showCachedCourseDetails\(key\)\) dialog\.dismiss\(\)/)
  const main=section(read('MainActivity'),'internal fun showCachedCourseDetails(','internal fun calendarShowsOtherQMplusCourses(')
  assert.match(main,/if \(!isCurrentUiOwner\(\)\) return false/)
  assert.match(main,/if \(!cloud && !qm\) return false/)
  assert.match(main,/automaticCourseLoadAttempted = true/)
  assert.doesNotMatch(main,/load\(|connectQmplus/)
})

test('QM calendar updates observe exactly the attached calendar owner and never start data work',()=>{
  for(const owner of ['scrollView','root']) {
    assert.ok(calendar.includes(`activity.qmplusState().addObserver(${owner})`))
    assert.ok(calendar.includes(`activity.qmplusState().removeObserver(${owner})`))
    assert.ok(calendar.includes(`activity.isCurrentUiOwner() && calendarHostRoot === ${owner} && ${owner}.isAttachedToWindow`))
  }
  const projection=section(calendar,'private fun supplementaryItemsOn(','private fun deadlineKindTitle(')
  assert.match(projection,/matches\.singleOrNull\(\)/)
  assert.match(projection,/it\.currentTermStatus == "current" \|\| activity\.calendarShowsOtherQMplusCourses\(\)/)
  assert.match(projection,/if \(item\.kind == "quiz"\) item\.closesAt else item\.dueAt/)
  assert.doesNotMatch(projection,/opensAt|cutoffAt|loadAssignments|loadCourses|connectQmplus/)
})

test('language readiness measures visible controls but ignores hidden FORCE_LAYOUT descendants',()=>{
  const transition=read('LanguageChangeTransition')
  const geometry=section(transition,'private fun layoutGeometry(','fun runLocalLanguageWork(')
  assert.match(geometry,/if \(root\.visibility != View\.VISIBLE\) return null/)
  assert.ok(geometry.indexOf('if (view.visibility != View.VISIBLE) continue')<geometry.indexOf('view.isLayoutRequested'))
  assert.match(geometry,/if \(child\.visibility == View\.VISIBLE\) queue\.add\(child\)/)
  assert.match(transition,/stableLayout\.observe\(ready, root\.isAttachedToWindow, !ready/)
  const request=section(transition,'fun request(','private fun startLegacyBlur(')
  assert.match(request,/deadline = Runnable \{ if \(revision\.get\(\) == token\) \{ applyPending\(\); cancel\(\) \} \}/)
  assert.doesNotMatch(request,/visibility = View\.VISIBLE/)
  const settings=section(read('SettingsPage'),'private fun qmplusSurface(','private fun ')
  assert.match(settings,/enabledSwitch\.isEnabled = !repository\.isClearingSession/)
  assert.match(settings,/connect\.isEnabled = repository\.isFeatureEnabled && !repository\.isLoading/)
})
