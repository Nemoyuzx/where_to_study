import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

test('course refresh clears every exit only for the selected flight',()=>{
  const source=readFileSync(new URL('../native/apple/Sources/Shared/TeachingCloudCourseStore.swift',import.meta.url),'utf8')
  assert.match(source,/defer \{[\s\S]*flight\?\.id == selected\.id[\s\S]*isRefreshing = false/)
  assert.match(source,/selected\.task\.value/)
  assert.match(source,/flight\?\.task\.cancel\(\)/)
})
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8')
// Specifications only. No local automated execution was performed.
test('course controls share a center line and disclosure retains a clipped top-anchored subtree',()=>{
  const row=read('native/apple/Sources/Shared/CourseCatalogRow.swift')
  const content=read('native/apple/Sources/Shared/ExpandableContent.swift')
  assert.match(row,/HStack\(alignment: \.center, spacing: 8\)/)
  assert.match(row,/ExpandableContent\(expanded: isExpanded\)/)
  assert.doesNotMatch(row,/\.move\(edge: \.top\)/)
  assert.match(content,/frame\(height: expanded \? nil : 0, alignment: \.top\)/)
  assert.match(content,/accessibilityHidden\(!expanded\)/)
})
test('network help has an independent settings surface and language value is in a stable leading menu label',()=>{
  const source=read('native/apple/Sources/Shared/SettingsView.swift')
  assert.match(source,/case network/)
  assert.match(source,/case \.network:[\s\S]*?Surface \{ systemNetworkAssistanceDescription/)
  const language=source.slice(source.indexOf('private var languageSurface:'),source.indexOf('private func changeInterfaceLanguage('))
  assert.match(language,/Menu \{/)
  assert.match(language,/frame\(maxWidth: \.infinity, minHeight: 32, alignment: \.leading\)/)
  const info=source.slice(source.indexOf('private var informationSurface:'),source.indexOf('private var referenceNotice:'))
  assert.doesNotMatch(info,/systemNetworkAssistanceDescription/)
})
test('success uses an original stroke mark and two revision-fenced foreground pulses',()=>{
  const mark=read('native/apple/Sources/Shared/LanguageCompletionMark.swift')
  const owner=read('native/apple/Sources/Shared/LanguageChangeTransition.swift')
  assert.match(mark,/CABasicAnimation\(keyPath: "strokeEnd"\)/)
  assert.match(owner,/completionImage\?\.play\(\)/)
  assert.match(owner,/playSuccessHaptics\(revision: currentRevision\)/)
  assert.match(owner,/secondHaptic\?\.cancel\(\)/)
  assert.match(owner,/self\.revision == currentRevision/)
})
