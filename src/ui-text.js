import catalogs from './ui-catalogs.generated.json' with {type:'json'}
import { resolveUiLanguage } from './ui-languages.js'
import { UI_KEY_ALIASES } from './ui-key-aliases.js'

// Only callers' static UI keys enter this lookup. Never pass API content or
// student-provided course names here. Placeholder data is substituted last.
export function uiText(language, key, englishFallback = key, values = {}) {
  const resolved = resolveUiLanguage(language)
  const template = catalogs[resolved]?.[key]
    || (resolved !== 'zh-Hans' && UI_KEY_ALIASES[key] && catalogs[resolved]?.[UI_KEY_ALIASES[key]])
    || (resolved === 'zh-Hans' ? key : catalogs.en?.[key] || englishFallback)
  return Object.entries(values).reduce((result, [name, value]) =>
    result.replaceAll(`{${name}}`, String(value)), template)
}

// Cross-platform static printf-style resources. Arguments are never translated
// or reparsed: course names, campus text and API values remain verbatim.
export function uiFormat(language, key, args = [], englishFallback = key) {
  let sequential = 0
  return uiText(language, key, englishFallback).replace(
    /%%|%(?:(\d+)\$)?(?:lld|ld|@|d|u|s|f)/g,
    (token, position) => token === '%%' ? '%' : String(args[position ? Number(position)-1 : sequential++] ?? ''),
  )
}
