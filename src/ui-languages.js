// UI preferences only. Academic/API text and contract date parsing never use
// this resolver, and user-facing changes must not replace the application root.
export const UI_LANGUAGES = Object.freeze([
  {code:'zh-Hans', name:'简体中文'}, {code:'zh-Hant', name:'繁體中文'},
  {code:'en', name:'English'}, {code:'ja', name:'日本語'},
  {code:'es', name:'Español'}, {code:'pt', name:'Português'},
  {code:'ar', name:'اللغة العربية'}, {code:'ru', name:'Русский'},
  {code:'tr', name:'Türkçe'}, {code:'th', name:'ไทย'},
  {code:'ms', name:'Bahasa Melayu'}, {code:'vi', name:'Tiếng Việt'},
  {code:'id', name:'Bahasa Indonesia'},
])
export const UI_LANGUAGE_CODES = Object.freeze(UI_LANGUAGES.map(item => item.code))
const supported = new Set(UI_LANGUAGE_CODES)

export function canonicalUiLanguage(tag) {
  if (typeof tag !== 'string' || tag.length > 80) return null
  const value = tag.trim().replaceAll('_', '-').toLowerCase()
  if (!/^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$/.test(value)) return null
  const parts = value.split('-')
  if (parts[0] === 'zh') {
    if (parts.includes('hant')) return 'zh-Hant'
    if (parts.includes('hans')) return 'zh-Hans'
    return parts.some(part => ['tw','hk','mo'].includes(part)) ? 'zh-Hant' : 'zh-Hans'
  }
  const base = parts[0] === 'in' ? 'id' : parts[0]
  return supported.has(base) ? base : null
}

export function normalizeUiPreference(value) {
  if (value === 'system') return 'system'
  return canonicalUiLanguage(value) ?? 'system'
}

export function resolveUiLanguage(preference, systemLanguages = []) {
  const normalized = normalizeUiPreference(preference)
  if (normalized !== 'system') return normalized
  const languages = Array.isArray(systemLanguages) ? systemLanguages : [systemLanguages]
  for (const candidate of languages.slice(0, 32)) {
    const language = canonicalUiLanguage(candidate)
    if (language) return language
  }
  return 'en'
}

export const uiDirection = language => canonicalUiLanguage(language) === 'ar' ? 'rtl' : 'ltr'
export const uiDateLocale = language => canonicalUiLanguage(language) ?? 'en'

const weekCopy = {
  'zh-Hans':['第 {n} 教学周','非教学周','公历第 {n} 周'],
  'zh-Hant':['第 {n} 教學週','非教學週','公曆第 {n} 週'],
  en:['Teaching week {n}','Outside teaching weeks','Calendar week {n}'],
  ja:['授業第 {n} 週','授業期間外','暦の第 {n} 週'],
  es:['Semana lectiva {n}','Fuera del periodo lectivo','Semana del año {n}'],
  pt:['Semana letiva {n}','Fora do período letivo','Semana do ano {n}'],
  ar:['الأسبوع الدراسي {n}','خارج الأسابيع الدراسية','الأسبوع {n} من السنة'],
  ru:['Учебная неделя {n}','Вне учебных недель','Календарная неделя {n}'],
  tr:['Ders haftası {n}','Ders haftaları dışında','Takvim haftası {n}'],
  th:['สัปดาห์เรียนที่ {n}','นอกช่วงสัปดาห์เรียน','สัปดาห์ที่ {n} ของปี'],
  ms:['Minggu pengajian {n}','Di luar minggu pengajian','Minggu kalendar {n}'],
  vi:['Tuần học {n}','Ngoài các tuần học','Tuần dương lịch {n}'],
  id:['Minggu perkuliahan {n}','Di luar minggu perkuliahan','Minggu kalender {n}'],
}
export function localizedWeek(kind, number, language) {
  const values = weekCopy[canonicalUiLanguage(language)] ?? weekCopy.en
  return values[kind === 'calendar' ? 2 : number > 0 ? 0 : 1].replace('{n}', String(number))
}
