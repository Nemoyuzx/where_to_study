import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const read=path=>readFileSync(new URL(`../${path}`,import.meta.url),'utf8').replace(/\r\n/g,'\n')
const files=[
  'native/apple/Sources/Shared/CoursesView.swift',
  'native/apple/Sources/Shared/CourseCatalogDetailView.swift',
]
const officialLink=source=>{
  const links=[...source.matchAll(/Link\(destination:\s*CalendarDeadlineSources\.assignments\)\s*\{([^{}]*)\}((?:\s*\.[A-Za-z]+\([^\n]*\))*)/g)]
  assert.equal(links.length,1,'each teaching-cloud surface retains exactly one official link')
  return {body:links[0][1],modifiers:links[0][2],block:links[0][0]}
}

for(const path of files)test(`${path} uses the localized official destination with a real small bordered icon button`,()=>{
  const source=read(path),link=officialLink(source)
  assert.equal(link.body.trim(),'Label(model.localized("打开教学云平台"), systemImage: "arrow.up.right.square")')
  assert.match(link.modifiers,/\.buttonStyle\(\.bordered\)/)
  assert.match(link.modifiers,/\.controlSize\(\.small\)/)
  assert.doesNotMatch(link.modifiers,/\.frame\(|\.fixedSize\(|\.padding\(|\.font\(/)
  assert.doesNotMatch(link.block,/\b(?:Button|Task|URLSession|fetch|loadAssignmentQuery|onTapGesture|onAppear|onChange)\b/)
  assert.doesNotMatch(source,/Link\(model\.localized\("打开教学云平台"\), destination:/)
})

test('course detail preserves its existing accessibility identifier and localization key',()=>{
  const source=read(files[1]),link=officialLink(source)
  assert.match(link.modifiers,/\.accessibilityIdentifier\("course-detail\.open-official"\)/)
  assert.equal((link.modifiers.match(/\.accessibilityIdentifier\("course-detail\.open-official"\)/g)||[]).length,1)
  const english=read('native/apple/Resources/Localizations/en.lproj/Localizable.strings')
  assert.match(english,/"打开教学云平台"\s*=\s*"Open Teaching Cloud Platform"/)
})
