// Mechanical platform resources from the reviewed shared UI dictionaries.
// Never processes user records, API responses or authentication information.
import {readFileSync, writeFileSync, mkdirSync, existsSync} from 'node:fs'
import {dirname,resolve} from 'node:path'
import {fileURLToPath} from 'node:url'
import {createHash} from 'node:crypto'
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..')
const read=path=>readFileSync(resolve(root,path),'utf8')
const base=JSON.parse(read('localization/ui-source.json'))
const languages=['zh-Hant','en','ja','es','pt','ar','ru','tr','th','ms','vi','id']
const localeArg=process.argv.indexOf('--locale')
const selected=localeArg<0?languages:[process.argv[localeArg+1]]
if(selected.some(language=>!languages.includes(language)))throw new Error('Unknown UI locale')
const partial=process.argv.includes('--partial')
const placeholders=text=>[...text.matchAll(/%%|%(?:\d+\$)?(?:lld|ld|@|d|u|s|f)|\{[A-Za-z_][A-Za-z_0-9]*\}/g)]
  .map(m=>m[0]).sort().join('|')
const catalogs={}
for(const language of selected){
  const values=JSON.parse(read(`localization/${language}.json`))
  for(const [key,english] of Object.entries(base)){
    const value=values[key]
    if(typeof value!=='string'||!value.trim()){
      if(!partial)throw new Error(`Incomplete locale: ${language} / ${key}`)
    }else if(placeholders(value)!==placeholders(english))throw new Error(`Invalid placeholders: ${language} / ${key}`)
    else if(!partial&&language!=='en'&&english.length>32&&value===english&&/\p{Script=Han}/u.test(key))
      throw new Error(`Unreviewed English fallback: ${language} / ${key}`)
  }
  if(language!=='en'&&Object.keys(base).filter(k=>values[k]===base[k]).length>Object.keys(base).length/2)
    throw new Error(`Untranslated locale: ${language}`)
  catalogs[language]={...base,...values}
}
const appleEnglish={}
for(const match of read('native/apple/Resources/Localizations/en.lproj/Localizable.strings')
  .matchAll(/"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;/g)){
  appleEnglish[JSON.parse(`"${match[1]}"`)]=JSON.parse(`"${match[2]}"`)
}
const write=(path,contents)=>{
  const absolute=resolve(root,path)
  if(process.argv.includes('--check')){
    if(!existsSync(absolute)||readFileSync(absolute,'utf8')!==contents)throw new Error(`Stale generated resource: ${path}`)
  }else {mkdirSync(dirname(absolute),{recursive:true});writeFileSync(absolute,contents)}
}
for(const language of selected){
  const values=catalogs[language]
  const apple=Object.keys(appleEnglish).sort().map(key=>{
    if(!partial&&!Object.hasOwn(values,key))throw new Error(`Missing Apple UI key: ${language} / ${key}`)
    return `${JSON.stringify(key)} = ${JSON.stringify(values[key]??appleEnglish[key])};`
  }).join('\n')+'\n'
  write(`native/apple/Resources/Localizations/${language}.lproj/Localizable.strings`,apple)
  if(language!=='en')write(`native/harmony/localizations/${language}.json`,JSON.stringify(values,null,2)+'\n')
}

// Preserve existing Android resource IDs, and extend known static chrome with
// deterministic IDs. Never apply this catalog to fields marked preserveRawText.
const resources=JSON.parse(read('localization/android-resources.json'))
const staticMap=new Map()
for(const [id,{key}] of Object.entries(resources)){
  if(!/%|\{[A-Za-z_]/.test(key)&&!staticMap.has(key))staticMap.set(key,id)
}
const generated=[]
for(const key of Object.keys(base))if(!/%|\{[A-Za-z_]/.test(key)&&!staticMap.has(key)){
  const id=`ui_generated_${createHash('sha256').update(key).digest('hex').slice(0,14)}`
  staticMap.set(key,id);generated.push([id,key])
}
const xml=value=>'"'+value.replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll("'","\\'")
  .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('\n','\\n')+'"'
for(const language of selected){
  const directory=language==='zh-Hant'?'values-b+zh+Hant':`values-${language}`
  const files={}
  for(const [id,{key,file}] of Object.entries(resources)){
    (files[file]??=[]).push([id,catalogs[language][key]??base[key]??key])
  }
  for(const [file,entries] of Object.entries(files)){
    // Newly inventoried keys share ui_generated.xml with the hash-ID entries;
    // a single merged write keeps every R.string reference defined on disk.
    if(file==='ui_generated.xml')entries.push(...generated.map(([id,key])=>[id,catalogs[language][key]]))
    // Locale overlays contain strings only; IDs/styles remain in base resources.
    write(`native/android/app/src/main/res/${directory}/${file}`,
      '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'+entries.map(([id,value])=>
        `    <string name="${id}">${xml(value)}</string>`).join('\n')+'\n</resources>\n')
  }
}
write('native/android/app/src/main/res/values/ui_generated.xml',
  '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'+[...Object.entries(resources)]
    .filter(([,{file}])=>file==='ui_generated.xml').map(([id,{key}])=>[id,key])
    .concat(generated).map(([id,key])=>
    `    <string name="${id}">${xml(key)}</string>`).join('\n')+'\n</resources>\n')
const kotlinQuote=value=>JSON.stringify(value).replaceAll('$','\\$')
write('native/android/app/src/main/java/com/nemoyu/wheretostudy/nativeapp/NativeUiTextCatalog.kt',
  'package com.nemoyu.wheretostudy.nativeapp\n\nimport android.content.Context\n\n'+
  '/** Generated static chrome only. No Activity, business records or credential data is retained. */\n'+
  'internal object NativeUiTextCatalog {\n    val resources: Map<String, Int> = mapOf(\n'+
  [...staticMap].map(([key,id])=>`        ${kotlinQuote(key)} to R.string.${id},`).join('\n')+
  '\n    )\n    fun resolve(context: Context, source: String): String? = resources[source]?.let(context::getString)\n}\n')
console.log(`Generated UI resources: ${selected.join(', ')}; ${partial?'development fallback allowed':'strict complete coverage'}`)
