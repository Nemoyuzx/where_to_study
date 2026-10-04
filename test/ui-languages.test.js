import test from 'node:test'
import assert from 'node:assert/strict'
import { UI_LANGUAGE_CODES, canonicalUiLanguage, normalizeUiPreference, resolveUiLanguage, uiDirection } from '../src/ui-languages.js'
import { normalizeUiLanguage, resolvedUiLanguage } from '../src/planner-domain.js'

test('thirteen UI locales resolve script and region without changing raw API values', () => {
  assert.equal(UI_LANGUAGE_CODES.length, 13)
  for (const code of UI_LANGUAGE_CODES) {
    assert.equal(canonicalUiLanguage(code), code)
    assert.equal(normalizeUiLanguage(code), code)
  }
  for (const code of ['zh-Hant','zh-TW','zh_HK','zh-MO']) assert.equal(canonicalUiLanguage(code), 'zh-Hant')
  assert.equal(canonicalUiLanguage('zh-Hans-TW'), 'zh-Hans')
  assert.equal(canonicalUiLanguage('zh-Hant-CN'), 'zh-Hant')
  assert.equal(resolveUiLanguage('system', ['fr-CA','ja-JP']), 'ja')
  assert.equal(resolvedUiLanguage('system', 'es-MX'), 'es')
  assert.equal(canonicalUiLanguage('in-ID'), 'id')
  assert.equal(normalizeUiPreference('not-a-ui-locale'), 'system')
  assert.equal(resolveUiLanguage('system', ['unknown']), 'en')
  assert.equal(canonicalUiLanguage('ar?token=secret'), null)
  assert.equal(uiDirection('ar-SA'), 'rtl')
  assert.equal(uiDirection('zh-Hant'), 'ltr')
})
