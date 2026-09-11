import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = file => readFileSync(new URL(`../${file}`, import.meta.url), 'utf8')
const android = 'native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/'
const harmony = 'native/harmony/entry/src/main/ets/'

test('regular Android and Harmony controls retain the requested 32 baseline', () => {
  const ui = read(`${android}UiSupport.kt`)
  for (const name of ['controlHeightDp', 'compactControlHeightDp', 'phoneControlMinHeightDp']) {
    assert.match(ui, new RegExp(`const val ${name} = 32`))
  }
  assert.match(read(`${harmony}common/ControlMetrics.ets`), /height: number = 32/)
  for (const file of ['SettingsView', 'PlannerView', 'QueryView', 'ColorThemeSettingsCard']) {
    const source = read(`${harmony}view/${file}.ets`)
    assert.match(source, /ControlMetrics\.height/)
    assert.doesNotMatch(source, /\.height\(36\)/)
  }
})

test('dense period cells and spacing are restored without removing safe areas or navigation animation', () => {
  const planner = read(`${android}PlannerPage.kt`)
  assert.match(planner, /cellHeightDp = if \(isCompact\) 46 else 54/)
  assert.match(planner, /spacingDp = 4/)
  assert.match(planner, /PhoneNavigationLayoutLogic\.CONTENT_INSET_DP/)
  const layout = read(`${android}AdaptiveLayout.kt`)
  assert.match(layout, /ITEM_HEIGHT_DP = 46/)
  assert.match(layout, /HORIZONTAL_MARGIN_DP = 32/)
  assert.match(read(`${android}PhoneNavigationBar.kt`), /translationX\(target\)/)
  assert.match(read(`${harmony}view/QueryView.ets`), /PhoneNavigationLayout\.minimumContentBottomInsetVp/)
})
