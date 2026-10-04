// Mechanical inventory only. Human/agent-reviewed translations live in localization/*.json.
import {readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync} from 'node:fs'
import {resolve, dirname} from 'node:path'
import {fileURLToPath} from 'node:url'
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..')
const read=path=>readFileSync(resolve(root,path),'utf8')
const english={}, seeds={}
const languages=['en','zh-Hant','ja','es','pt','ar','ru','tr','th','ms','vi','id']
const add=(key,value)=>{if(typeof key==='string'&&typeof value==='string'&&key&&value&&!Object.hasOwn(english,key))english[key]=value}
function strings(path) {
  if(!existsSync(resolve(root,path)))return {}
  const values={}
  for(const match of read(path).matchAll(/"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;/g)) {
    const key=JSON.parse(`"${match[1]}"`),value=JSON.parse(`"${match[2]}"`)
    if(Object.hasOwn(values,key))throw new Error(`Duplicate Apple resource: ${path} / ${key}`)
    values[key]=value
  }
  return values
}
function xmlValues(path) {
  if(!existsSync(resolve(root,path)))return {}
  const decode=value=>value.replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&lt;/g,'<')
    .replace(/&gt;/g,'>').replace(/&amp;/g,'&').replace(/^"([\s\S]*)"$/,'$1')
    .replace(/\\n/g,'\n').replace(/\\'/g,"'").replace(/\\"/g,'"').replace(/\\\\/g,'\\')
  return Object.fromEntries([...read(path).matchAll(/<string\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/string>/g)]
    .map(match=>[match[1],decode(match[2])]))
}
const appleBase=strings('native/apple/Resources/Localizations/en.lproj/Localizable.strings')
Object.entries(appleBase).forEach(([k,v])=>add(k,v))
for(const language of languages) {
  const hPath=`native/harmony/localizations/${language}.json`
  seeds[language]={...(existsSync(resolve(root,hPath))?JSON.parse(read(hPath)):{}),
    ...strings(`native/apple/Resources/Localizations/${language}.lproj/Localizable.strings`)}
}
const single=value=>JSON.parse(`"${value.replaceAll("\\'","'").replaceAll('"','\\"')}"`)
const harmony=read('native/harmony/entry/src/main/ets/common/AppLocalization.ets')
const hEnglish=harmony.slice(harmony.indexOf('private static readonly english:'),harmony.indexOf('static text('))
for(const match of hEnglish.matchAll(/'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'/g))add(single(match[1]),single(match[2]))
const app=read('src/App.jsx')
const appEnglish=app.slice(app.indexOf('const EN_TEXT ='),app.indexOf('function translator('))
for(const match of appEnglish.matchAll(/'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'/g))add(single(match[1]),single(match[2]))
for(const module of ['QmplusLoginSettings','CourseHub','PrivateQueriesPanel','GradesPanel','ColorThemeSettings','QueryHub']) {
  for(const match of read(`src/${module}.jsx`).matchAll(/text\('((?:\\.|[^'\\])*)',\s*'((?:\\.|[^'\\])*)'/g))add(single(match[1]),single(match[2]))
}
const androidFiles=readdirSync(resolve(root,'native/android/app/src/main/res/values-en')).filter(name=>name.endsWith('.xml'))
const android={}
for(const file of androidFiles) {
  const zh=xmlValues(`native/android/app/src/main/res/values/${file}`)
  const en=xmlValues(`native/android/app/src/main/res/values-en/${file}`)
  for(const [id,key] of Object.entries(zh)) {
    if(!en[id])throw new Error(`Missing English Android resource: ${file} / ${id}`)
    add(key,en[id]); android[id]={key,file}
    const hant=xmlValues(`native/android/app/src/main/res/values-b+zh+Hant/${file}`)
    if(hant[id])seeds['zh-Hant'][key]=hant[id]
  }
}
const inventory=JSON.parse(read('native/android/localization/android-only-ui.json'))
inventory.entries.forEach(entry=>add(entry.zh,entry.en))
mkdirSync(resolve(root,'localization'),{recursive:true})
const sorted=value=>Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b)))
writeFileSync(resolve(root,'localization/ui-source.json'),JSON.stringify(sorted(english),null,2)+'\n')
writeFileSync(resolve(root,'localization/android-resources.json'),JSON.stringify(sorted(android),null,2)+'\n')
const deficits={}
for(const language of languages) {
  const path=resolve(root,`localization/${language}.json`)
  const hasReviewedFile=existsSync(path)
  const previous=hasReviewedFile?JSON.parse(readFileSync(path,'utf8')):{}
  // Never reseed a reviewed dictionary from development resources: a generated
  // English fallback is not a reviewed translation of a newly added key.
  const values=language==='en'?english:hasReviewedFile?previous:seeds[language]
  writeFileSync(path,JSON.stringify(sorted(values),null,2)+'\n')
  deficits[language]=Object.keys(english).filter(key=>!Object.hasOwn(values,key)).length
}
console.log(JSON.stringify({sourceKeys:Object.keys(english).length,missing:deficits}))
