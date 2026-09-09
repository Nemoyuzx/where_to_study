import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'
import {
  applyColorTheme, COLOR_THEME_PRESETS, COLOR_THEME_STORAGE_KEY, colorContrast,
  colorThemeSeeds, colorThemeVariables, DEFAULT_COLOR_THEME, loadColorTheme,
  normalizeColorTheme, normalizeHexColor, resolvedColorTheme, saveColorTheme,
} from '../src/color-themes.js'

function storageStub() {
  const values = new Map()
  return {
    values,
    getItem(key) { return values.get(key) ?? null },
    setItem(key, value) { values.set(key, value) },
    removeItem(key) { values.delete(key) },
  }
}

test('theme presets use the shared cross-platform contract', () => {
  const contract = JSON.parse(readFileSync(new URL('../contracts/v1/color-themes.json', import.meta.url)))
  assert.deepEqual(COLOR_THEME_PRESETS, contract.presets)
  assert.equal(new Set(COLOR_THEME_PRESETS.map((item) => item.id)).size, 5)
  assert.equal(DEFAULT_COLOR_THEME.preset, contract.defaultPreset)
  assert.equal(DEFAULT_COLOR_THEME.customPrimary, contract.presets[0].primary)
  for (const item of COLOR_THEME_PRESETS) {
    for (const key of ['primary', 'accent', 'selectedDate']) assert.equal(normalizeHexColor(item[key]), item[key])
  }
})

test('six-digit RGB validation rejects CSS injection and malformed values', () => {
  assert.equal(normalizeHexColor('  abC123  '), '#ABC123')
  assert.equal(normalizeHexColor('#000000'), '#000000')
  for (const input of [null, {}, 12, '', '#123', '#12345678', '#GG1234', '##123456', 'red', '#fff;display:none']) {
    assert.equal(normalizeHexColor(input), null, String(input))
  }
})

test('persisted settings migrate safely, retain custom colors, and restore after reload', () => {
  const storage = storageStub()
  assert.deepEqual(loadColorTheme(storage), DEFAULT_COLOR_THEME)
  storage.setItem(COLOR_THEME_STORAGE_KEY, 'broken-json')
  assert.deepEqual(loadColorTheme(storage), DEFAULT_COLOR_THEME)
  assert.deepEqual(normalizeColorTheme({ preset: 'unknown', customPrimary: 'BAD' }), DEFAULT_COLOR_THEME)
  const custom = saveColorTheme(storage, {
    ...DEFAULT_COLOR_THEME, preset: 'custom', customPrimary: 'AA6633', customSelectedDate: '#3412ab',
  })
  assert.equal(custom.customSelectedDate, '#3412AB')
  assert.deepEqual(loadColorTheme(storage), custom)
  for (const preset of ['ocean', 'rose', 'default', 'custom']) {
    const saved = saveColorTheme(storage, { ...loadColorTheme(storage), preset })
    assert.equal(saved.customPrimary, '#AA6633')
    assert.equal(saved.customSelectedDate, '#3412AB')
    assert.equal(loadColorTheme(storage).preset, preset)
  }
})

test('invalid edits and failed storage leave the saved theme untouched', () => {
  const storage = storageStub()
  const saved = saveColorTheme(storage, { ...DEFAULT_COLOR_THEME, preset: 'ocean' })
  assert.throws(() => saveColorTheme(storage, { ...saved, preset: 'custom', customPrimary: '#oops' }))
  assert.deepEqual(loadColorTheme(storage), saved)
  assert.throws(() => saveColorTheme({ setItem() { throw new Error('quota') } }, saved), /quota/)
})

test('preset and extreme custom colors have readable fills and dark primary text', () => {
  const themes = COLOR_THEME_PRESETS.filter((item) => item.id !== 'default').map((item) => ({ preset: item.id }))
  for (const color of ['#FFFFFF', '#000000', '#FFFF00', '#00FF00', '#808080', '#FF00FF', '#001122']) {
    themes.push({ ...DEFAULT_COLOR_THEME, preset: 'custom', customPrimary: color, customAccent: color, customSelectedDate: color })
  }
  for (const settings of themes) {
    for (const dark of [false, true]) {
      const palette = resolvedColorTheme(settings, dark)
      assert.ok(colorContrast(palette.primaryFill, '#FFFFFF') >= 4.5)
      assert.ok(colorContrast(palette.selectedDate, '#FFFFFF') >= 4.5)
      assert.ok(colorContrast(palette.primaryText, dark ? '#282828' : '#FFFFFF') >= 4.5)
      const variables = colorThemeVariables(settings, dark)
      assert.ok(colorContrast(variables['--gold-text'], variables['--gold-surface']) >= 4.5)
      assert.ok(colorContrast(variables['--primary-text'], variables['--primary-surface-selected-strong']) >= 4.5)
      assert.ok(colorContrast(variables['--primary-pressed'], '#FFFFFF') >= 4.5)
      assert.ok(Object.values(variables).every((value) => !String(value).includes('NaN')))
      assert.ok(!Object.keys(variables).some((key) => /deadline|school-notice|error|current-time/.test(key)))
    }
  }
})

test('default theme retains the original CSS; switching back removes only theme overrides', () => {
  const values = new Map([['--unrelated', 'preserve-me']])
  const root = {
    dataset: {},
    style: { setProperty(name, value) { values.set(name, value) }, removeProperty(name) { values.delete(name) } },
  }
  assert.deepEqual(colorThemeVariables(DEFAULT_COLOR_THEME, false), {})
  assert.deepEqual(colorThemeVariables(DEFAULT_COLOR_THEME, true), {})
  applyColorTheme(root, { preset: 'violet' }, false)
  assert.equal(root.dataset.colorTheme, 'violet')
  assert.equal(values.get('--primary-fill'), '#7C3AED')
  applyColorTheme(root, DEFAULT_COLOR_THEME, true)
  assert.equal(root.dataset.colorTheme, 'default')
  assert.deepEqual([...values], [['--unrelated', 'preserve-me']])
})

test('custom colors are independent of selected presets', () => {
  const custom = { ...DEFAULT_COLOR_THEME, customPrimary: '#123456', customAccent: '#FF7700', customSelectedDate: '#663399' }
  assert.equal(colorThemeSeeds({ ...custom, preset: 'ocean' }).primary, '#1565C0')
  assert.equal(colorThemeSeeds({ ...custom, preset: 'custom' }).primary, '#123456')
})

test('pressed fills and selected-date outlines are consumed by real controls', () => {
  const appCss = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
  const themeCss = readFileSync(new URL('../src/ColorThemeSettings.css', import.meta.url), 'utf8')
  assert.equal((appCss.match(/background: var\(--primary-pressed, var\(--primary-focus\)\)/g) || []).length, 4)
  assert.doesNotMatch(appCss, /background: var\(--primary-focus\);/)
  assert.match(themeCss, /\.desktop-month-view \.month-cell\.selected:not\(\.today\):not\(\[class\*="deadline-border-"\]\) \.month-cell-date-button/)
  assert.match(themeCss, /\.mini-month-grid button\.selected:not\(\.today\):not\(\[class\*="deadline-border-"\]\)/)
  assert.match(themeCss, /box-shadow: inset 0 0 0 1\.5px var\(--selected-date-outline\)/)
})
