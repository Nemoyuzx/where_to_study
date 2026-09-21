import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { runInNewContext } from 'node:vm'
import { buildSync } from 'esbuild'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'

const module = { exports: {} }
const compiled = buildSync({
  entryPoints: [fileURLToPath(new URL('../src/GradesPanel.jsx', import.meta.url))],
  bundle: true, write: false, platform: 'node', format: 'cjs', jsx: 'automatic', packages: 'external',
}).outputFiles[0].text
runInNewContext(compiled, { module, exports: module.exports, require: createRequire(import.meta.url) })
const { GradeCard } = module.exports
const words = { score: '成绩', credits: '学分' }

test('compact grade cards preserve zero, text, unpublished and all optional metadata', () => {
  for (const score of [0, '合格', '', null]) {
    const item = { name: '长课程名称 / A long academic course title', score, credits: 0,
      course_code: 'C123', semester_name: '2026–2027 Autumn', course_attribute: '必修',
      course_nature: '实践', exam_nature: '首次', grade_status: '正常' }
    const html = renderToStaticMarkup(createElement(GradeCard, { item, words }))
    for (const text of [item.name, '学分 · 0', 'C123', item.semester_name, '必修', '实践', '首次', '正常']) {
      assert.ok(html.includes(text), text)
    }
    assert.ok(html.includes(`aria-label="成绩: ${score === '' || score == null ? '—' : score}"`))
    assert.doesNotMatch(html, /<small><\/small>|<p>/)
  }
})

test('missing grade metadata creates no blank spacer and names remain escaped', () => {
  const html = renderToStaticMarkup(createElement(GradeCard, {
    item: { name: '<script>Grade</script>', score: 'A', credits: null }, words,
  }))
  assert.match(html, /&lt;script&gt;Grade&lt;\/script&gt;/)
  assert.ok(html.includes('学分 · —'))
  assert.doesNotMatch(html, /<script>|<small>|<span><\/span>/)
})

test('grade density remains natural-height and independent of data retrieval', () => {
  const css = readFileSync(new URL('../src/App.css', import.meta.url), 'utf8')
  const cardRule = css.match(/\.query-grade-card\s*\{([^}]+)\}/)?.[1] ?? ''
  assert.match(cardRule, /padding:\s*10px 12px/)
  assert.doesNotMatch(cardRule, /(?:max-|min-)?height\s*:/)
  assert.match(css, /\.query-grade-list\s*\{[^}]*align-items:\s*start/)
  assert.match(css, /\.query-grades\s*\{[^}]*align-content:\s*start/)
  assert.match(css, /\.query-grade-metadata\s*\{[^}]*flex-wrap:\s*wrap/)
})
