import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import test from 'node:test'

const css=readFileSync(new URL('../src/App.css',import.meta.url),'utf8')
test('desktop password hints clear input borders without changing global control metrics',()=>{
  const hint=css.match(/\.account-password-hint\s*\{([^}]+)\}/)?.[1]
  assert.ok(hint)
  assert.match(hint,/margin:\s*6px 0 10px;/)
  assert.doesNotMatch(hint,/margin:\s*-/)
})
test('desktop daily-info categories have more separation than their title and description',()=>{
  const row=css.match(/\.settings-daily-info > \.settings-switch-row\s*\{([^}]+)\}/)?.[1]
  const content=css.match(/\.settings-switch-row > div\s*\{([^}]+)\}/)?.[1]
  assert.ok(row&&content)
  const padding=Number(row.match(/padding-block:\s*(\d+)px;/)?.[1])
  const gap=Number(content.match(/gap:\s*(\d+)px;/)?.[1])
  assert.equal(padding,12)
  assert.ok(padding*2>gap)
})
