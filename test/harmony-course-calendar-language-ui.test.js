import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

// Source regression specs, intentionally NOT executed on the user's machine.
const normalizeSource=source=>source.replace(/\r\n?/g,'\n')
const read=path=>normalizeSource(readFileSync(new URL('../native/harmony/entry/src/main/ets/'+path,import.meta.url),'utf8'))
function assertCourseTapOwnership(source){
  const view=normalizeSource(source)
  assert.match(view,/toggleCourseInline\('ucloud', course.id\)/)
  assert.match(view,/toggleCourseInline\('qmplus', course.id\)/)
  assert.match(view,/courses.cloud.info.[\s\S]*?\.onClick\(\(\) => this.openCourse\('ucloud'/)
  assert.match(view,/courses.qmplus.info.[\s\S]*?\.onClick\(\(\) => this.openCourse\('qmplus'/)
  assert.doesNotMatch(view,/stopPropagation/)
  for(const [start,end,kind] of [['  cloudCourseRow(', '  private visibleQMPlusCourses(', 'ucloud'],
    ['  qmPlusCourseRow(', '  @Builder\n  courseDisclosureButton(', 'qmplus']]){
    const row=view.slice(view.indexOf(start),view.indexOf(end))
    const disclosure=row.indexOf(`.onClick(() => this.toggleCourseInline('${kind}'`)
    const info=row.indexOf("Button() { SymbolGlyph($r('sys.symbol.info_circle'))")
    assert.ok(disclosure>=0&&info>disclosure,'disclosure is attached to a separate sibling before info Button')
    assert.doesNotMatch(row.slice(info),/\.onClick\(\(\) => this.toggleCourseInline/,
      'no info ancestor or shared outer row owns the disclosure click')
  }
  const inline=view.slice(view.indexOf('  private toggleCourseInline'),view.indexOf('  build()'))
  assert.doesNotMatch(inline,/loadCloudCourseDirectory|loadAssignment|openLogin|fetch\(/)
}
test('course taps disclose cached work while separate info controls retain original detail navigation',()=>{
  assertCourseTapOwnership(read('view/CourseView.ets'))
  assert.match(read('view/CourseSession.ets'),/expandedCourseKeys/)
})
test('CRLF course source preserves separate disclosure and info ownership boundaries',()=>{
  assertCourseTapOwnership(read('view/CourseView.ets').replaceAll('\n','\r\n'))
})
test('QM Off is initially folded but management can expand without enabling connect or losing drafts',()=>{
  const view=read('view/SettingsView.ets'),session=read('view/SettingsSession.ets')
  assert.match(view,/DisclosureClip\(\{ expanded: this.session.qmplusDetailsExpanded \}\)/)
  assert.match(view,/this.session.qmplusDetailsExpanded = !this.session.qmplusDetailsExpanded/)
  assert.match(view,/enabled\(!this.model.isSampleMode\(\) && this.model.qmplusEnabled\)/)
  assert.match(session,/updateQMplusDisclosure\(enabled: boolean\)[\s\S]*?qmplusDetailsExpanded = enabled/)
  assert.match(view,/this.session.qmPlusPasswordDraft/)
  const disappear=view.slice(view.indexOf('  aboutToDisappear'),view.indexOf('  private',view.indexOf('  aboutToDisappear')))
  assert.doesNotMatch(disappear,/qmPlusPasswordDraft = ''/)
})
test('semester picker sits with refresh and all-term grades are grouped using actual semester names',()=>{
  const view=read('view/GradeQueryView.ets')
  assert.match(view,/Row\(\{ space: 8 \}\)[\s\S]*?query.grades.term[\s\S]*?query.grades.refresh/)
  assert.match(view,/if \(this.model.gradeTermID.length === 0\)[\s\S]*ForEach\(this.gradeTermNames/)
  assert.match(view,/item.semesterName === name/)
})
test('coursework calendar projections use due or quiz close only and current EBU/admin-filtered cache',()=>{
  const projection=read('view/calendar/CalendarCourseworkProjection.ets')
  assert.match(projection,/CourseQMPlusScope.currentActivities\(snapshot\)/)
  assert.match(projection,/item.kind === 'quiz' \? item.closesAt : item.dueAt/)
  assert.doesNotMatch(projection,/cutoffAt|opensAt|fetch\(|loadCourse/)
  for(const name of ['MobileTeachingCalendarView','ExpandedTeachingCalendarView']){
    const view=read('view/calendar/'+name+'.ets')
    assert.match(view,/CalendarCourseworkProjection.qm/)
    assert.match(view,/AppTheme.assignment\(\), AppTheme.assignmentSurface\(\)/)
    assert.match(view,/expandedHiddenAllDayEventCount/)
    assert.match(view,/coursework.courseID/)
  }
})
test('language completion depends on preference and latest widget/notification acknowledgements plus three full-tree frames',()=>{
  const model=read('model/AppModel.ets'),root=read('view/RootView.ets'),widget=read('widget/WidgetSync.ets')
  assert.match(model,/committedLanguageRevision === this.languageSettingRevision/)
  assert.match(model,/languageWidgetAcknowledgedRevision === this.languageWidgetRevision/)
  assert.match(model,/languageNotificationAcknowledgedRevision === this.dailyCourseNotificationRevision/)
  assert.match(root,/model.languageChangeReady\(target\)/)
  assert.match(root,/languageStableFrames >= 3/)
  assert.match(root,/languageTreeGeometry\(mainNode\)/)
  assert.match(root,/Text\('Switching…'\)/)
  assert.match(root,/languageOverlayCompleted = true/)
  assert.match(widget,/writeArchive[\s\S]*await formProvider.reloadForms/)
  assert.match(widget,/widget-preferences.json/)
})
