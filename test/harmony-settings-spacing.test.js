import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL(`../native/harmony/entry/src/main/ets/view/${path}`, import.meta.url), 'utf8')
const settings = read('SettingsView.ets').replace(/\r\n?/g, '\n')
const qmplus = settings.slice(settings.indexOf('  qmPlusConnectionSurface() {'), settings.indexOf('  accountSurface() {'))
const account = settings.slice(settings.indexOf('  accountSurface() {'), settings.indexOf('  field(placeholder:'))

// Find actual enclosing layout owners, including across conditional branches.
// An outer card's space does not reach through DisclosureClip's zero-space body.
function closingDelimiter(source, opening, open = '{', close = '}') {
  let depth = 0, quote = null
  for (let i = opening; i < source.length; i++) {
    const char = source[i]
    if (quote) {
      if (char === '\\') i++
      else if (char === quote) quote = null
      continue
    }
    if (char === '/' && source[i + 1] === '/') {
      i = source.indexOf('\n', i)
      if (i < 0) break
      continue
    }
    if (char === "'" || char === '"' || char === '`') { quote = char; continue }
    if (char === open) depth++
    if (char === close && --depth === 0) return i
  }
  assert.fail('layout block must close')
}

function owners(source, marker) {
  const position = source.indexOf(marker)
  assert.ok(position >= 0, `control or note exists: ${marker}`)
  return [...source.matchAll(/Column\(\{ space: (\d+) \}\) \{/g)]
    .map(match => ({start: match.index, end: closingDelimiter(source, match.index + match[0].length - 1), gap: Number(match[1])}))
    .filter(block => block.start < position && position < block.end)
    .reverse()
}

const gaps = (source, marker) => owners(source, marker).map(block => block.gap)

test('Harmony settings title uses the page gap without a second bottom inset', () => {
  const content = settings.slice(settings.indexOf('  settingsContent() {'), settings.indexOf('  settingsTitle() {'))
  const title = settings.slice(settings.indexOf('  settingsTitle() {'), settings.indexOf('  referenceNotice() {'))
  assert.match(content, /Column\(\{ space: 16 \}\) \{\s*this\.settingsTitle\(\)\s*this\.referenceNotice\(\)/)
  assert.doesNotMatch(title, /\.(?:padding|margin)\(/)
})

test('Harmony expanded QM content owns group spacing inside the measured disclosure viewport', () => {
  assert.match(read('SharedComponents.ets'), /Column\(\) \{ this\.content\(\); \}/)
  assert.match(qmplus, /DisclosureClip\(\{ expanded: this\.session\.qmplusDetailsExpanded \}\) \{\s*Column\(\{ space: 16 \}\)/)
  for (const marker of ['settings.qmplus.connect', 'settings.qmplus.save-login', 'settings.qmplus.delete-login']) {
    assert.deepEqual(gaps(qmplus, marker), [16, 12], `${marker} clears adjacent groups`)
  }
  assert.deepEqual(gaps(qmplus, 'settings.qmplus.account'), [12, 16, 12])
  assert.deepEqual(gaps(qmplus, 'settings.qmplus.password'), [12, 16, 12])
  assert.equal(owners(qmplus, 'settings.qmplus.account')[0].start, owners(qmplus, 'settings.qmplus.password')[0].start)
})

test('Harmony QM hints stay together while enable and autofill toggles retain clear group boundaries', () => {
  for (const marker of ['登录与同步在后台完成', 'settings.qmplus.autofill', '关闭“启用 QMplus”只暂停连接和同步']) {
    assert.deepEqual(gaps(qmplus, marker), [8, 16, 12])
  }
  assert.deepEqual(gaps(qmplus, 'settings.qmplus.enabled'), [12])
  assert.deepEqual(gaps(qmplus, 'settings.qmplus.details-toggle'), [12])
  assert.match(qmplus, /\.layoutWeight\(1\)\s*Toggle\(\{ type: ToggleType\.Switch, isOn: this\.qmPlusSession\.savedLoginAvailable/)
  assert.match(qmplus, /\.width\(48\)\s*\.enabled\(!this\.qmPlusSession\.loginSettingsBusy\)/)
})

test('Harmony account passwords own their descriptions and clear the next field and action groups', () => {
  const sectionTitle = settings.slice(settings.indexOf('  sectionTitle(title:'), settings.indexOf('  segmentedOptions('))
  assert.match(sectionTitle, /\.padding\(\{ bottom: 12 \}\)/)
  assert.deepEqual(gaps(account, 'settings_account_input'), [0, 16])
  assert.equal(owners(account, "this.sectionTitle('个人账户')")[0].start, owners(account, 'settings_account_input')[0].start,
    'the account header preserves its own 12vp inset without adding the outer 16vp gap')
  for (const [field, description] of [
    ['settings_password_input', '用于移动教务登录和查询课表'],
    ['settings_cloud_password_input', '用于课程作业 DDL 查询'],
  ]) {
    assert.deepEqual(gaps(account, field), [8, 16])
    assert.equal(owners(account, field)[0].start, owners(account, description)[0].start)
  }
  assert.notEqual(owners(account, 'settings_password_input')[0].start, owners(account, 'settings_cloud_password_input')[0].start)
  assert.deepEqual(gaps(account, "'保存设置'"), [12, 16])
  assert.deepEqual(gaps(account, "'获取/刷新个人课表'"), [12, 16])
  assert.deepEqual(gaps(account, '账号和密码仅保存于本机'), [8, 16])
  assert.doesNotMatch(account, /Blank\(\)|\.padding\(\{[^}]*\btop:/)
})

test('Harmony spacing keeps shared control metrics and lets translated descriptions grow naturally', () => {
  const field = settings.slice(settings.indexOf('  field(placeholder:'), settings.indexOf('  semesterSurface() {'))
  assert.match(field, /\.height\(ControlMetrics\.height\)/)
  assert.match(qmplus, /\.height\(ControlMetrics\.height\)\.width\(ControlMetrics\.height\)/)
  assert.doesNotMatch(qmplus + account, /\.maxLines\(|\.textOverflow\(|\.clip\(|\.height\(\d/)
  assert.deepEqual(gaps(qmplus.replaceAll('\n', '\r\n'), 'settings.qmplus.password'), [12, 16, 12])
})

function componentChains(source, name) {
  return [...source.matchAll(new RegExp(`\\b${name}\\s*\\(`, 'g'))].map(match => {
    const opening = source.indexOf('(', match.index)
    let end = closingDelimiter(source, opening, '(', ')') + 1
    const skipSpace = () => { while (/\s/.test(source[end] ?? '') && end < source.length) end++ }
    skipSpace()
    if (source[end] === '{') { end = closingDelimiter(source, end) + 1; skipSpace() }
    while (source[end] === '.') {
      const modifier = source.slice(end).match(/^\.[A-Za-z]+\s*\(/)
      assert.ok(modifier, 'component modifier is a method call')
      end = closingDelimiter(source, end + modifier[0].length - 1, '(', ')') + 1
      skipSpace()
    }
    return source.slice(match.index, end)
  })
}

const buttonChains = source => componentChains(source, 'Button')

test('Harmony outlined buttons specify radius in the composite border after borderRadius', () => {
  const outlined = buttonChains(settings).filter(chain => /\.border\(/.test(chain))
  assert.equal(outlined.length, 6, 'account actions, semester save, data clear, filing and shared links')
  for (const button of outlined) {
    assert.match(button, /\.borderRadius\(6\)/)
    assert.match(button, /\.border\(\{[^}]*\bradius: 6\b/,
      'a prior borderRadius alone must not be overwritten by a radius-less composite border')
    assert.match(button, /\.height\(ControlMetrics\.height\)/)
  }
  const demo = settings.slice(settings.indexOf('  reviewDemoSurface() {'), settings.indexOf('  sectionTitle(title:'))
  assert.match(demo, /this\.linkButton\('浏览内置示例数据'/)
  const link = settings.slice(settings.indexOf('  linkButton(label:'))
  assert.match(link, /\.border\(\{ width: 1, radius: 6, color: AppTheme\.border\(\) \}\)/)
})

test('Harmony academic and settings inputs retain theme surfaces and radius in their own borders', () => {
  const academic = read('AcademicQueryViews.ets')
  const grades = read('GradeQueryView.ets')
  const groups = [
    [componentChains(settings, 'TextInput'), 2, 6],
    [componentChains(academic, 'TextInput'), 1, 8],
    [componentChains(academic, 'Select'), 1, 8],
    [componentChains(grades, 'Select'), 2, 8],
  ]
  for (const [controls, count, radius] of groups) {
    assert.equal(controls.length, count)
    for (const control of controls) {
      assert.match(control, /\.height\(ControlMetrics\.height\)/)
      assert.match(control, /\.backgroundColor\(AppTheme\.inputSurface\(\)\)/)
      assert.match(control, new RegExp(`\\.borderRadius\\(${radius}\\)`))
      assert.match(control, new RegExp(`\\.border\\(\\{ width: 1, radius: ${radius}, color: AppTheme\\.border\\(\\) \\}\\)`))
    }
  }
})

test('Harmony theme presets and shared surfaces carry their radius through composite borders', () => {
  const theme = read('ColorThemeSettingsCard.ets')
  const preset = buttonChains(theme).find(chain => chain.includes(".id('color_theme_' + seed.id)"))
  assert.ok(preset)
  assert.match(preset, /\.borderRadius\(8\)/)
  assert.match(preset, /\.border\(\{ width: this\.model\.colorTheme\.selection\.preset === seed\.id \? 2 : 1, radius: 8,/)
  assert.match(preset, /this\.swatch\(seed\.primary\)/)
  assert.match(preset, /this\.swatch\(seed\.accent\)/)
  assert.match(preset, /this\.swatch\(seed\.selectedDate\)/)
  assert.match(preset, /this\.choosePreset\(seed\.id\)/)
  const shared = read('SharedComponents.ets')
  const surface = shared.slice(shared.indexOf('export struct SurfaceCard'), shared.indexOf('export struct SectionHeader'))
  const chip = shared.slice(shared.indexOf('export struct ChipButton'))
  for (const control of [surface, chip]) {
    assert.match(control, /\.borderRadius\(8\)/)
    assert.match(control, /\.border\(\{[^}]*radius: 8/)
  }
  assert.match(qmplus, /Toggle\(\{ type: ToggleType\.Switch, isOn: this\.qmplusFeatureSwitchValue \}\)\s*\.selectedColor\(AppTheme\.primaryFill\(\)\)/)
})

test('Harmony compact text fields keep their full font height and vertically center the content', () => {
  const definitions = [
    [read('ColorThemeSettingsCard.ets'), [16]],
    [settings, [13, 16]],
    [read('AcademicQueryViews.ets'), [16]],
    [read('QueryView.ets'), [12]],
  ]
  for (const [source, horizontalInsets] of definitions) {
    const fields = componentChains(source, 'TextInput')
    assert.equal(fields.length, horizontalInsets.length)
    fields.forEach((field, index) => {
      const inset = horizontalInsets[index]
      assert.match(field, new RegExp(`\\.padding\\(\\{ left: ${inset}, right: ${inset}, top: 0, bottom: 0 \\}\\)`))
      assert.match(field, /\.align\(Alignment\.Center\)/)
      assert.match(field, /\.height\((?:ControlMetrics\.height|38)\)/)
      assert.match(field, /\.fontSize\(ControlMetrics\.inputFontSize\)/)
      assert.match(field, /\.placeholderFont\(\{ size: ControlMetrics\.inputFontSize \}\)/)
      assert.match(field, /\.onChange\(/)
    })
  }
  const theme = read('ColorThemeSettingsCard.ets')
  const hex = componentChains(theme, 'TextInput')[0]
  const metrics = read('../common/ControlMetrics.ets')
  assert.match(metrics, /static readonly inputFontSize: number = 14;/)
  assert.match(metrics, /static readonly height: number = 32;/)
  assert.match(hex, /\.fontFamily\('monospace'\)/)
  assert.match(hex, /\.enableKeyboardOnFocus\(!this\.seedOnlyScene\)/)
  assert.match(hex, /onChange\(next\)/)
  for (const id of ['color_theme_primary', 'color_theme_accent', 'color_theme_selected_date']) {
    assert.match(theme, new RegExp(`this\\.colorField\\([^\\n]*'${id}'`))
  }
})
