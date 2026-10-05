import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const settings = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8')
const root = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/RootView.ets', import.meta.url), 'utf8')
const session = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/SettingsSession.ets', import.meta.url), 'utf8')

test('Harmony language choice animates only its isolated selection layer, not the whole text reflow', () => {
  const language = settings.slice(settings.indexOf('  languageSegments() {'), settings.indexOf('  languageSurface() {'))
  const surface = settings.slice(settings.indexOf('  languageSurface() {'), settings.indexOf('  removedCoursesSurface() {'))
  assert.ok(language.length > 0)
  assert.match(language, /Column\(\) \{\}[\s\S]*?\.backgroundColor\([\s\S]*?\.animation\(\{ duration: 160/)
  assert.match(language, /\.id\('settings\.language\.' \+ index\.toString\(\)\)/)
  assert.match(language, /\.onClick\(\(\) => this\.onLanguageChangeRequested\(language\)\)/)
  assert.doesNotMatch(language, /animateTo\(/)
  assert.match(surface, /this\.languageSegments\(\)/)
  assert.doesNotMatch(surface, /segmentedOptions\(/)
})

test('Harmony covers the complete app before changing language and reveals only a stable target layout', () => {
  assert.match(root, /if \(this\.languageOverlayVisible\) \{[\s\S]*?\.backgroundBlurStyle\(BlurStyle\.Regular\)[\s\S]*?\.opacity\(this\.languageOverlayOpacity\)[\s\S]*?\.hitTestBehavior\(HitTestMode\.Block\)[\s\S]*?\.id\('language_transition_overlay'\)/)
  assert.match(root, /this\.postLanguageFrame\(epoch,[\s\S]*?animateTo\(\{ duration: 110,[\s\S]*?onFinish:[\s\S]*?this\.requestLanguageUnderOverlay\(epoch\);[\s\S]*?this\.sampleLanguageLayout\(epoch\)/)
  assert.match(settings, /@Monitor\('session\.languageChangeRevision'\)[\s\S]*?this\.applyRequestedLanguageChange\(\)/)
  assert.match(settings, /this\.session\.languageChangeAppliedRevision = revision;\s*this\.selectLanguageAtCurrentPosition\(target\)/)
  assert.match(languageSelection(), /\.id\('settings\.language\.thumb\.' \+ index\.toString\(\) \+[\s\S]*?'\.active'/)
  assert.match(root, /getAttachedFrameNodeById\('settings_language_surface'\)/)
  assert.match(root, /getAttachedFrameNodeById\([\s\S]*?'settings\.language\.thumb\.' \+ index\.toString\(\) \+ '\.active'\)/)
  assert.match(root, /this\.languageStableFrames >= 2\)[\s\S]*?this\.fadeLanguageOverlay\(epoch\)/)
  assert.match(session, /requestLanguageChange\(target: AppLanguage, revision: number\): void/)
})

test('Harmony cancels old language owners, honors reduced animation, and never leaves the blur blocking navigation', () => {
  assert.match(root, /this\.languageTransitionEpoch\+\+;[\s\S]*?this\.clearLanguageTransitionTimer\(\);[\s\S]*?this\.languageOverlayVisible = false/)
  assert.match(root, /settings\.getValueSync\(context, settings\.display\.ANIMATOR_DURATION_SCALE, '1'\)/)
  assert.match(root, /animatorScale\.length > 0 && Number\(animatorScale\) === 0/)
  assert.match(root, /if \(this\.reduceLanguageMotion\(\)\) \{[\s\S]*?this\.settingsSession\.requestLanguageChange\(target, revision\);\s*return;/)
  assert.match(root, /on\('windowEvent', languageListener\)/)
  assert.match(root, /off\('windowEvent', this\.languageWindowEventListener\)/)
  assert.match(root, /WINDOW_INACTIVE[\s\S]*?WINDOW_HIDDEN[\s\S]*?this\.cancelLanguageTransition\(true\)/)
  assert.match(root, /aboutToDisappear\(\): void \{\s*this\.cancelLanguageTransition\(true\)/)
  assert.match(root, /selectSection\(section: AppSection\): void \{[\s\S]*?if \(section !== AppSection\.settings && this\.languageTransitionTarget !== null\) \{\s*this\.cancelLanguageTransition\(true\)/)
  assert.match(root, /if \(epoch === this\.languageTransitionEpoch\) \{ work\(\); \}/)
  assert.match(root, /\}, 1600\)/)
  assert.doesNotMatch(root, /componentSnapshot|\.backdropBlur\(/)
})

function languageSelection() {
  return settings.slice(settings.indexOf('  languageSegments() {'), settings.indexOf('  languageSurface() {'))
}

test('Harmony phone navigation keeps its animation on background/icon, not its text geometry', () => {
  const navigation = root.slice(root.indexOf('  phoneNavigationItem(section: AppSection) {'),
    root.indexOf('  sectionView(section: AppSection) {'))
  assert.ok(navigation.length > 0)
  assert.match(navigation, /Stack\(\) \{[\s\S]*?Column\(\) \{\}[\s\S]*?\.backgroundColor\([\s\S]*?\.animation\(\{ duration: 160/)
  assert.match(navigation, /SymbolGlyph\([\s\S]*?\.fontColor\([\s\S]*?\.animation\(\{ duration: 160/)
  const label = navigation.slice(navigation.indexOf('Text(this.model.text(AppSectionInfo.title(section)))'))
  assert.ok(label.indexOf('.animation(') < 0 || label.indexOf('.animation(') > label.indexOf('.onClick('),
    'the translated label must not own a geometry animation')
})
