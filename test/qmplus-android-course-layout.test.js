import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8')
const android=read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/InformationQueryPage.kt')
const apple=read('native/apple/Sources/Shared/CoursesView.swift')
const appleCard=read('native/apple/Sources/Shared/CourseCatalogDetailView.swift').split('struct QMplusCachedActivityRow: View')[1]
const courses=android.slice(android.indexOf('private fun coursesContent()'),android.indexOf('private fun courseSectionHeader('))
const inline=android.slice(android.indexOf('private fun populateInlineAssignments('),android.indexOf('private fun showCourseDetails('))
const card=android.slice(android.indexOf('private fun qmplusActivityCard('),android.indexOf('private fun qmplusContent('))

test('inline cloud and QM assignments have the Apple ten-point item separation, without a leading gap',()=>{
  assert.match(apple,/VStack\(alignment: \.leading, spacing: 10\) \{[\s\S]*?ForEach\(activities\) \{ QMplusCachedActivityRow/)
  assert.match(inline,/if \(cardIndex\+\+ > 0\) topMargin = activity\.dp\(10\)/)
  assert.match(inline,/cloudItems[\s\S]*?forEach \{ addActivityCard\(cloudAssignmentCard\(it\)\) \}/)
  assert.match(inline,/qmItems[\s\S]*?forEach \{ addActivityCard\(qmplusActivityCard\(it\)\) \}/)
})
test('other-term filter uses a themed native Switch before the course list and only rerenders local state',()=>{
  assert.ok(apple.indexOf('Toggle(model.localized("显示其他学期／历史课程")')<apple.indexOf('ForEach(selected.courses)'))
  const toggle=courses.slice(courses.indexOf('Switch(activity)'),courses.indexOf('if (visible.orEmpty().isEmpty())'))
  assert.match(toggle,/isChecked = sessionState\.showsOtherQmCourses/)
  assert.match(toggle,/setThemeTextColor \{ Palette\.text \}/)
  assert.match(toggle,/minHeight = activity\.dp\(UiMetrics\.controlHeightDp\)/)
  assert.match(toggle,/sessionState\.showsOtherQmCourses = checked[\s\S]*?renderMode\(animate = false\)/)
  assert.doesNotMatch(toggle,/connectQmplus|load\w*\(|fetch\w*\(|expandedCourseKeys\.clear|inlineCourseCounts\.clear/)
  assert.ok(courses.indexOf('Switch(activity)')<courses.indexOf('id = R.id.course_qmplus_list'))
  assert.doesNotMatch(courses,/qmplus_hide_other_courses|qmplus_show_other_courses/)
  assert.match(android,/visibleQmplusRowCount = maxOf\(sessionState\.visibleQmplusRowCount, 20, target\)/)
})
test('QM card retains Apple metadata order, eight-point internal spacing and unmodified raw webpage text',()=>{
  assert.match(appleCard,/spacing: 8/)
  assert.match(appleCard,/\.padding\(10\)/)
  assert.match(appleCard,/metadata\.joined\(separator: " · "\)/)
  assert.match(card,/setPadding\(activity\.dp\(10\), activity\.dp\(10\), activity\.dp\(10\), activity\.dp\(10\)\)/)
  assert.match(card,/setPadding\(0, activity\.dp\(8\), 0, 0\)/)
  assert.match(card,/QmplusActivityPresentation\.displayTimeFields\(item\)/)
  assert.match(card,/metadata\.joinToString\(" · "\)/)
  assert.match(card,/item\.rawTimeText\?\.takeIf \{ it\.isNotBlank\(\) \}\?\.let \{ addView\(detail\(it\)\) \}/)
  assert.doesNotMatch(card,/rawTimeText[\s\S]*?(?:\.split\(|\.replace\(|\.translate\()/)
})
