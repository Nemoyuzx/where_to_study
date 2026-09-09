import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { transformSync } from 'esbuild'
import { COLOR_THEME_PRESETS, colorThemeSurfaces, readableColor } from '../src/color-themes.js'

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8')
const harmony = read('native/harmony/entry/src/main/ets/common/ColorThemes.ets')
const android = read('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/ColorThemes.kt')
const apple = read('native/apple/Sources/WidgetShared/ColorThemeConfiguration.swift')
// Color derivation is pure; exclude ArkUI's runtime-only observable state.
const pureHarmony = harmony.slice(0, harmony.indexOf('@ObservedV2'))
const { code } = transformSync(pureHarmony, { loader: 'ts', format: 'esm' })
const { ColorThemes, ColorThemeSelection } = await import('data:text/javascript;base64,' + Buffer.from(code).toString('base64'))

test('native preset seed triples match the web shared contract', () => {
  for (const preset of COLOR_THEME_PRESETS) {
    const native = ColorThemes.presets.find((item) => item.id === preset.id)
    assert.deepEqual(
      [native.primary, native.accent, native.selectedDate, native.nameZh, native.nameEn],
      [preset.primary, preset.accent, preset.selectedDate, preset.nameZh, preset.nameEn],
    )
    if (preset.id === 'default') continue // default seeds are declared in native default constructors
    const appleRow = apple.split('\n').find((line) => line.includes('case .' + preset.id + ': ('))
    assert.ok(appleRow, 'missing Apple preset ' + preset.id)
    const androidRow = android.split('\n').find((line) => line.includes('ColorThemePreset("' + preset.id + '"'))
    assert.ok(androidRow, 'missing Android preset ' + preset.id)
    for (const row of [appleRow, androidRow]) {
      assert.deepEqual(row.match(/#[0-9A-F]{6}/g), [preset.primary, preset.accent, preset.selectedDate])
    }
  }
})

test('ArkTS and JavaScript use the same sRGB derivation for presets and extreme colors', () => {
  const seeds = new Set(['#FFFFFF', '#000000', '#808080', '#FFFF00', '#FF00FF', '#00FF00'])
  for (const preset of COLOR_THEME_PRESETS) {
    seeds.add(preset.primary)
    seeds.add(preset.accent)
    seeds.add(preset.selectedDate)
  }
  for (const seed of seeds) {
    assert.equal(ColorThemes.fill(seed), readableColor(seed, '#FFFFFF', '#000000'), seed)
    assert.equal(ColorThemes.text(seed, true), readableColor(seed, '#282828', '#FFFFFF'), seed)
    assert.equal(ColorThemes.normalizeHex(seed.toLowerCase()), seed)
  }
})

test('ArkTS surface recipes match shared web values for all families and extreme custom seeds', () => {
  const themes = COLOR_THEME_PRESETS.slice(1).map((preset) => ({ preset: preset.id }))
  for (const seed of ['#FFFFFF', '#000000', '#FF0000', '#00FF00', '#0000FF']) {
    themes.push({ preset: 'custom', customPrimary: seed })
  }
  for (const settings of themes) {
    for (const dark of [false, true]) {
      const expected = colorThemeSurfaces(settings, dark)
      const actual = ColorThemes.surfaces(
        new ColorThemeSelection(settings.preset, settings.customPrimary || '#166B5D'), dark,
      )
      for (const role of ['background', 'surface', 'elevated', 'surfaceVariant', 'border', 'text', 'secondaryText']) {
        assert.equal(actual[role], expected[role], settings.preset + ' ' + dark + ' ' + role)
      }
    }
  }
})
