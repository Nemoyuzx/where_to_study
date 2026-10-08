import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'

const root=readFileSync(new URL('../native/harmony/entry/src/main/ets/view/RootView.ets',import.meta.url),'utf8').replace(/\r\n?/g,'\n')
const sections=['planner','calendar','courses','query','settings']
const navigation=root.slice(root.indexOf('  phoneNavigationItem(section:'),root.indexOf('  sectionView(section:'))
const selection=root.slice(root.indexOf('  selectSection(section:'),root.indexOf('  private setSettingsPrivacyPolicyVisible('))
function fixture(){
  const events=[],pending=[]
  const create=new Function('AppSection','hilog',transformSync('class NavigationHarness {\n'+selection+'\n}\nreturn NavigationHarness',
    {loader:'ts',target:'es2022'}).code)
  const owner=new (create(Object.fromEntries(sections.map(value=>[value,value])),{info(){}}))()
  Object.assign(owner,{currentSection:'planner',languageTransitionTarget:null,settingsFavoriteManagerVisible:false,
    settingsSession:{clearTransientPasswords(){events.push('clearDraft')},takeLanguageRequest(){return 'en'},
      showingLanguagePicker:true,showingPrivacyPolicy:true},
    qmPlusSession:{loginVisible:false,closeLogin(){events.push('closeLogin')}},
    model:{selectedSection:'planner',setLanguageSetting(){return new Promise(resolve=>pending.push(resolve))}},
    cancelLanguageTransition(){events.push('retireLanguage');owner.languageTransitionTarget=null}})
  return {owner,events,pending}
}
test('Harmony phone selection colors and accessibility derive directly from one route without crossfade',()=>{
  assert.match(navigation,/\.backgroundColor\(this\.currentSection === section \? AppTheme\.background\(\) : Color\.Transparent\)/)
  assert.match(navigation,/\.accessibilitySelected\(this\.currentSection === section\)/)
  assert.match(navigation,/\.accessibilityText\(this\.model\.text\(AppSectionInfo\.title\(section\)\)\)/)
  assert.match(navigation,/\.onClick\(\(\) => \{\s*this\.selectSection\(section\);/)
  assert.doesNotMatch(navigation,/\.animation\(|\.transition\(|animateTo\(|setTimeout|onTouch|stateStyles|clickEffect/)
  assert.match(root,/ForEach\(AppSectionInfo\.all,[\s\S]*?AppSectionInfo\.accessibilityId\(section\)/)
})
test('rapid and repeated route selections stay single-owned after late local language work',async()=>{
  const {owner,pending}=fixture()
  const sessions={settings:owner.settingsSession,qm:owner.qmPlusSession}
  for(const section of [...sections,'settings','settings','courses','query','planner','calendar','calendar']){
    owner.selectSection(section)
    assert.deepEqual(sections.filter(value=>owner.currentSection===value),[section])
    assert.equal(owner.model.selectedSection,section)
  }
  const selected=owner.currentSection
  pending.forEach(resolve=>resolve())
  await Promise.resolve()
  assert.equal(owner.currentSection,selected)
  assert.equal(owner.settingsSession,sessions.settings)
  assert.equal(owner.qmPlusSession,sessions.qm)
  assert.equal((root.match(/this\.currentSection\s*=(?!=)/g)||[]).length,1,
    'page load, presentation and delayed callbacks cannot write a previous route')
  const appear=root.slice(root.indexOf('  aboutToAppear()'),root.indexOf('  aboutToDisappear()'))
  assert.doesNotMatch(appear,/currentSection\s*=(?!=)/)
})
test('route changes preserve existing language retirement and close only an actually visible old login',()=>{
  const {owner,events}=fixture()
  owner.currentSection='settings';owner.languageTransitionTarget='ja';owner.qmPlusSession.loginVisible=true
  owner.selectSection('courses')
  assert.deepEqual(events,['clearDraft','retireLanguage','closeLogin'])
  assert.equal(owner.currentSection,'courses')
  assert.equal(owner.settingsSession.showingLanguagePicker,false)
  assert.equal(owner.settingsSession.showingPrivacyPolicy,false)
})
