import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'
import {transformSync} from 'esbuild'

const shared = readFileSync(new URL('../native/harmony/entry/src/main/ets/view/SharedComponents.ets', import.meta.url), 'utf8')
  .replace(/\r\n?/g, '\n')
const disclosure = shared.slice(shared.indexOf('export struct DisclosureClip {'), shared.indexOf('// 对应 PageTitle'))
const build = disclosure.slice(disclosure.indexOf('  build() {'))

// These are source/lifecycle contracts. ArkUI's real zero-viewport measurement,
// nested fold layout and retained input state still require device acceptance.
test('Harmony disclosure measures one natural body through a non-interactive vertical viewport', () => {
  assert.match(build, /build\(\) \{\s*Scroll\(\) \{\s*if \(this\.mounted\) \{\s*Column\(\) \{ this\.content\(\); \}/)
  assert.match(build, /\.width\('100%'\)\.height\(LayoutPolicy\.fixAtIdealSize\)/)
  assert.match(build, /\.onAreaChange\(/)
  assert.match(build, /\.height\(this\.viewportHeight\)\.clip\(true\)/)
  assert.match(build, /\.scrollable\(ScrollDirection\.Vertical\)/)
  assert.match(build, /\.enableScrollInteraction\(false\)/)
  assert.match(build, /\.scrollBar\(BarState\.Off\)/)
  assert.match(build, /\.edgeEffect\(EdgeEffect\.None\)/)
  assert.match(build, /\.align\(Alignment\.TopStart\)/)
  assert.match(build, /\.hitTestBehavior\(this\.expanded \? HitTestMode\.Default : HitTestMode\.None\)/)
  assert.match(build, /\.accessibilityLevel\(this\.expanded \? 'auto' : 'no-hide-descendants'\)/)
  assert.equal((build.match(/this\.content\(\)/g) ?? []).length, 1)
  assert.doesNotMatch(build, /if \(this\.expanded\)|\.height\(\d|setTimeout|fetch\(|openLogin|loadCourse/)
})

function fixture({expanded = false, reduced = false} = {}) {
  const methods = disclosure.slice(0, disclosure.indexOf('  build() {'))
    .replace('export struct DisclosureClip', 'class DisclosureHarness')
    .replace(/@(Param|BuilderParam|Local)\s+/g, '')
    .replace(/@Monitor\('expanded'\)\s*/g, '')
  const measurement = build.match(/\.onAreaChange\(\(oldArea: Area, area: Area\): void => \{([\s\S]*?)\n\s*\}\)/)?.[1]
  assert.ok(measurement, 'exercise the production natural-height callback')
  const animations = []
  const create = new Function('accessibility', 'Curve', transformSync(methods +
    `\n measured(area: Area): void {${measurement}\n}\n}\nreturn DisclosureHarness`, {loader: 'ts', target: 'es2022'}).code)
  const Subject = create({isAnimationReduceEnabledSync: () => reduced}, {EaseOut: 'ease-out'})
  const subject = new Subject()
  subject.expanded = expanded
  subject.getUIContext = () => ({animateTo: (options, work) => {animations.push(options); work()}})
  subject.aboutToAppear()
  return {subject, animations, toggle(value) {subject.expanded = value; subject.onExpandedChanged()}}
}

test('Harmony first expansion waits for natural measurement and reopening retains its mounted owner', () => {
  for (const initiallyExpanded of [false, true]) {
    const {subject, animations, toggle} = fixture({expanded: initiallyExpanded})
    assert.equal(subject.mounted, initiallyExpanded)
    if (!initiallyExpanded) toggle(true)
    assert.equal(subject.mounted, true)
    assert.equal(subject.viewportHeight, 0)
    subject.measured({height: 184})
    assert.equal(subject.viewportHeight, 184)
    toggle(false)
    assert.equal(subject.viewportHeight, 0)
    assert.equal(subject.mounted, true)
    subject.measured({height: 256})
    assert.equal(subject.viewportHeight, 0)
    toggle(true)
    assert.equal(subject.viewportHeight, 256)
    assert.equal(subject.mounted, true)
    subject.measured({height: 312})
    assert.equal(subject.viewportHeight, 312)
    assert.ok(animations.every(animation => animation.duration === 180))
  }
})

test('Harmony disclosure keeps reduced motion and rejects invalid or unchanged body measurements', () => {
  const {subject, animations, toggle} = fixture({reduced: true})
  toggle(true)
  for (const height of [NaN, Infinity, -1, 0]) subject.measured({height})
  assert.equal(subject.viewportHeight, 0)
  assert.equal(animations.length, 0)
  subject.measured({height: 184})
  subject.measured({height: 184.2})
  assert.equal(animations.length, 1)
  toggle(false)
  toggle(true)
  assert.equal(subject.viewportHeight, 184)
  assert.ok(animations.every(animation => animation.duration === 0))
})
