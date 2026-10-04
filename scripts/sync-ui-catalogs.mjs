// Build-time reuse of reviewed, static UI translations. No API/user content
// enters this catalog. Missing desktop-only keys remain visible in coverage.
import { readFileSync, existsSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { UI_LANGUAGES } from '../src/ui-languages.js'

const root = new URL('../', import.meta.url)
const sharedSource = new URL('localization/ui-source.json', root)
if (existsSync(sharedSource)) {
  const english = JSON.parse(readFileSync(sharedSource, 'utf8'))
  const unified = {'zh-Hans':Object.fromEntries(Object.keys(english).map(key=>[key,key])),en:english}
  const tokens = text => [...text.matchAll(/%%|%(?:\d+\$)?(?:lld|ld|@|d|u|s|f)|\{[A-Za-z_][A-Za-z_0-9]*\}/g)]
    .map(match=>match[0]).sort().join('|')
  for (const {code} of UI_LANGUAGES) {
    if (code==='en'||code==='zh-Hans') continue
    const file = new URL(`localization/${code}.json`, root)
    const values = existsSync(file)?JSON.parse(readFileSync(file,'utf8')):{}
    if (process.argv.includes('--strict')) {
      const missing=Object.keys(english).filter(key=>typeof values[key]!=='string'||!values[key].trim())
      if(missing.length)throw new Error(`Incomplete UI locale: ${code} (${missing.length} keys)`)
      for(const key of Object.keys(english)){
        if(tokens(values[key])!==tokens(english[key]))throw new Error(`Invalid UI placeholders: ${code} / ${key}`)
        if(english[key].length>32&&values[key]===english[key]&&/\p{Script=Han}/u.test(key))throw new Error(`Unreviewed English fallback: ${code} / ${key}`)
      }
      if(Object.keys(english).filter(key=>values[key]===english[key]).length>Object.keys(english).length/2)throw new Error(`Untranslated UI locale: ${code}`)
    }
    unified[code]=values
  }
  const target=new URL('src/ui-catalogs.generated.json',root)
  const output=`${JSON.stringify(unified,null,2)}\n`
  if(process.argv.includes('--check')){
    if(!existsSync(target)||readFileSync(target,'utf8')!==output)throw new Error('Regenerate unified UI resources: node scripts/sync-ui-catalogs.mjs')
  }else writeFileSync(target,output)
  process.exit(0)
}
const catalogs = {}
const harmonyEnglish = {}
const harmonySource = readFileSync(new URL('native/harmony/entry/src/main/ets/common/AppLocalization.ets',root),'utf8')
const staticEnglish = harmonySource.slice(harmonySource.indexOf('private static readonly english:'),
  harmonySource.indexOf('static text('))
const singleQuoted = text => JSON.parse(`"${text.replaceAll("\\'", "'").replaceAll('"', '\\"')}"`)
for (const match of staticEnglish.matchAll(/^\s*'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'/gm)) {
  harmonyEnglish[singleQuoted(match[1])] = singleQuoted(match[2])
}
for (const {code} of UI_LANGUAGES) {
  const source = new URL(`native/apple/Resources/Localizations/${code}.lproj/Localizable.strings`, root)
  const supplement = new URL(`native/harmony/localizations/${code}.json`,root)
  const values = code === 'en' ? {...harmonyEnglish} :
    existsSync(supplement) ? JSON.parse(readFileSync(supplement,'utf8')) : {}
  if (!existsSync(source) && !Object.keys(values).length) continue
  const text = existsSync(source) ? readFileSync(source, 'utf8') : ''
  const appleKeys = new Set()
  for (const match of text.matchAll(/"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;/g)) {
    const key = JSON.parse(`"${match[1]}"`)
    const value = JSON.parse(`"${match[2]}"`)
    if (typeof value !== 'string' || !value.trim()) throw new Error(`Empty UI resource: ${code}`)
    if (appleKeys.has(key) && values[key] !== value) throw new Error(`Conflicting UI resource: ${code}`)
    appleKeys.add(key)
    // Same canonical keys share Apple-reviewed copy; Harmony supplies static
    // desktop-compatible keys, never any user/API content or network fetch.
    values[key] = value
  }
  catalogs[code] = Object.fromEntries(Object.entries(values).sort(([a], [b]) => a.localeCompare(b)))
}
const target = new URL('src/ui-catalogs.generated.json', root)
if (process.argv.includes('--strict')) {
  const base = Object.keys(catalogs.en ?? {})
  if (!base.length) throw new Error('English UI resource baseline is missing')
  for (const {code} of UI_LANGUAGES) {
    // Simplified Chinese UI keys already contain their source text.
    if (code === 'zh-Hans') continue
    const missing = base.filter(key => !Object.hasOwn(catalogs[code] ?? {}, key))
    if (missing.length) throw new Error(`Incomplete UI locale: ${code} (${missing.length} keys)`)
    for (const key of base) {
      const tokens = value => [...value.matchAll(/%(?:\d+\$)?(?:lld|ld|@|d|u|s|f)|\{[a-zA-Z_][a-zA-Z_0-9]*\}/g)]
        .map(match => match[0]).sort().join('|')
      if (tokens(catalogs[code][key]) !== tokens(catalogs.en[key])) {
        throw new Error(`Invalid UI placeholders: ${code} / ${key}`)
      }
    }
    // Prevent adding whole English copies and calling them supported locales.
    if (code !== 'en' && base.filter(key => catalogs[code][key] === catalogs.en[key]).length > base.length / 2) {
      throw new Error(`Untranslated UI locale: ${code}`)
    }
  }
}
const output = `${JSON.stringify(catalogs, null, 2)}\n`
if (process.argv.includes('--check')) {
  if (!existsSync(target) || readFileSync(target, 'utf8') !== output) {
    throw new Error(`Regenerate UI resources: node ${fileURLToPath(import.meta.url)}`)
  }
} else {
  writeFileSync(target, output)
}
