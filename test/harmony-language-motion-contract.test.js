import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const settings = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/SettingsView.ets', import.meta.url), 'utf8')
const root = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/RootView.ets', import.meta.url), 'utf8')

test('Harmony language choice animates only its isolated selection layer, not the whole text reflow', () => {
  const language = settings.slice(settings.indexOf('  languageSegments() {'), settings.indexOf('  languageSurface() {'))
  const surface = settings.slice(settings.indexOf('  languageSurface() {'), settings.indexOf('  removedCoursesSurface() {'))
  assert.ok(language.length > 0)
  assert.match(language, /Column\(\) \{\}[\s\S]*?\.backgroundColor\([\s\S]*?\.animation\(\{ duration: 160/)
  assert.match(language, /\.id\('settings\.language\.' \+ index\.toString\(\)\)/)
  assert.match(language, /\.onClick\(\(\) => this\.selectLanguageAtCurrentPosition\(language\)\)/)
  assert.doesNotMatch(language, /animateTo\(/)
  assert.match(surface, /this\.languageSegments\(\)/)
  assert.doesNotMatch(surface, /segmentedOptions\(/)
})

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
