// One-time, reproducible preparation of the Harmony-specific Traditional
// Chinese UI catalogue. Apple-reviewed shared keys win over ICU conversion;
// only known static app strings are converted, never API responses or IDs.
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const toolsDir = dirname(fileURLToPath(import.meta.url))
const root = resolve(toolsDir, '../../../')
const source = readFileSync(resolve(root, 'native/harmony/entry/src/main/ets/common/AppLocalization.ets'), 'utf8')
const apple = readFileSync(resolve(root, 'native/apple/Resources/Localizations/zh-Hant.lproj/Localizable.strings'), 'utf8')
const keys = [...source.matchAll(/^\s*'((?:\\.|[^'\\])*)'\s*:/gm)]
  .map((match) => match[1].replaceAll("\\'", "'").replaceAll('\\n', '\n'))
const unique = [...new Set(keys)]
const appleValues = new Map()
for (const match of apple.matchAll(/^((?:"(?:\\.|[^"\\])*"))\s*=\s*((?:"(?:\\.|[^"\\])*"));$/gm)) {
  appleValues.set(JSON.parse(match[1]), JSON.parse(match[2]))
}
const missing = unique.filter((key) => !appleValues.has(key))
const run = spawnSync('swift', [resolve(toolsDir, 'hans-to-hant.swift')], {
  input: JSON.stringify(missing), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024,
})
if (run.status !== 0) throw new Error(`Hans-Hant conversion failed: ${run.stderr.trim()}`)
const converted = JSON.parse(run.stdout)
if (!Array.isArray(converted) || converted.length !== missing.length) throw new Error('Hans-Hant output length mismatch')
const harmonize = (value) => value
  .replaceAll('設置', '設定').replaceAll('賬戶', '帳戶').replaceAll('緩存', '快取')
  .replaceAll('界面', '介面').replaceAll('默認', '預設').replaceAll('保存', '儲存')
  .replaceAll('信息', '資訊').replaceAll('小組件', '小工具').replaceAll('當前', '目前')
  .replaceAll('周', '週')
const convertedValues = new Map(missing.map((key, index) => [key, harmonize(converted[index])]))
const result = Object.fromEntries(unique.map((key) => [key, appleValues.get(key) ?? convertedValues.get(key)]))
const target = resolve(root, 'native/harmony/localizations/zh-Hant.json')
mkdirSync(dirname(target), { recursive: true })
writeFileSync(target, `${JSON.stringify(result, null, 2)}\n`, 'utf8')
process.stdout.write(`Harmony zh-Hant static keys: ${unique.length}; Apple shared: ${unique.length - missing.length}; ICU supplement: ${missing.length}\n`)
