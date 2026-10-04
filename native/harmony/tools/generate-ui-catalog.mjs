// Mechanical build input for Harmony's synchronous, per-render UI lookup.
// Each locale JSON contains vetted static UI text; API payloads are never translated.
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../../')
const source = readFileSync(resolve(root, 'native/harmony/entry/src/main/ets/common/AppLocalization.ets'), 'utf8')
const keys = [...new Set([...source.matchAll(/^\s*'((?:\\.|[^'\\])*)'\s*:/gm)]
  .map((match) => match[1].replaceAll("\\'", "'").replaceAll('\\n', '\n')))]
const languages = ['zh-Hant', 'ja', 'es', 'pt', 'ar', 'ru', 'tr', 'th', 'ms', 'vi', 'id']
const strict = process.argv.includes('--strict')
const result = {}
const missingLocales = []
const placeholders = (text) => [...text.matchAll(/\{[A-Za-z_][A-Za-z_0-9]*\}|%(?:\d+\$)?[sd]/g)]
  .map((match) => match[0]).sort()
function appleTranslations(language) {
  const file = resolve(root, `native/apple/Resources/Localizations/${language}.lproj/Localizable.strings`)
  if (!existsSync(file)) return {}
  const values = {}
  for (const match of readFileSync(file, 'utf8').matchAll(/^((?:"(?:\\.|[^"\\])*"))\s*=\s*((?:"(?:\\.|[^"\\])*"));$/gm)) {
    values[JSON.parse(match[1])] = JSON.parse(match[2])
  }
  return values
}
const reportIndex = process.argv.indexOf('--report-harmony-only-missing')
if (reportIndex >= 0) {
  const language = process.argv[reportIndex + 1]
  if (!languages.includes(language)) throw new Error('Specify a supported non-base locale')
  const file = resolve(root, `native/harmony/localizations/${language}.json`)
  const translated = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {}
  const appleBase = appleTranslations('en')
  for (const key of keys.filter((item) => appleBase[item] === undefined && translated[item] === undefined)) {
    process.stdout.write(`${key}\n`)
  }
  process.exit(0)
}
for (const language of languages) {
  const file = resolve(root, `native/harmony/localizations/${language}.json`)
  if (!existsSync(file) && Object.keys(appleTranslations(language)).length === 0) {
    missingLocales.push(language); continue
  }
  // Apple-reviewed common keys win; Harmony JSON supplies platform-only UI.
  const translated = { ...(existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {}),
    ...appleTranslations(language) }
  const missing = keys.filter((key) => typeof translated[key] !== 'string' || translated[key].length === 0)
  if (missing.length) {
    if (strict) throw new Error(`${language}: ${missing.length} missing static keys: ${missing.slice(0, 8).join(' | ')}`)
    missingLocales.push(language)
    continue
  }
  for (const key of keys) {
    if (placeholders(key).join('|') !== placeholders(translated[key]).join('|')) {
      throw new Error(`${language}: placeholder mismatch for ${key}`)
    }
  }
  result[language] = Object.fromEntries(keys.map((key) => [key, translated[key]]))
}
if (strict && missingLocales.length) throw new Error(`Missing full locales: ${missingLocales.join(', ')}`)
const output = `// Generated from native/harmony/localizations/*.json. Do not translate API payloads.\n` +
  `export class AppLocalizationCatalog {\n` +
  `  private static readonly values: Record<string, Record<string, string>> = ${JSON.stringify(result, null, 2)};\n` +
  `  static text(source: string, language: string): string | undefined {\n` +
  `    const locale: Record<string, string> | undefined = AppLocalizationCatalog.values[language];\n` +
  `    return locale === undefined ? undefined : locale[source];\n` +
  `  }\n` +
  `}\n`
writeFileSync(resolve(root, 'native/harmony/entry/src/main/ets/common/AppLocalizationCatalog.ets'), output)
process.stdout.write(`Harmony locale catalog: ${Object.keys(result).join(', ') || 'none'}; known static keys: ${keys.length}; missing: ${missingLocales.join(', ') || 'none'}\n`)
