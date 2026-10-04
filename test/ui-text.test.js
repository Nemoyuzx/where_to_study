import test from 'node:test'
import assert from 'node:assert/strict'
import {uiText} from '../src/ui-text.js'

test('static UI uses the requested resource without modifying API or machine data', () => {
  assert.equal(uiText('ja', '设置', 'Settings'), '設定')
  assert.equal(uiText('zh-Hant', '设置', 'Settings'), '設定')
  assert.equal(uiText('en', '设置', 'Settings'), 'Settings')
  const raw = 'EBU6304 Algorithms — week 2'
  assert.equal(uiText('ja', raw), raw)
  assert.equal(uiText('ar', 'unknown/{date}', 'Unknown/{date}', {date:'2026-10-04'}), 'Unknown/2026-10-04')
})
