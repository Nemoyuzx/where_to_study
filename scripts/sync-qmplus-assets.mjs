// Mechanical copies of the reviewed canonical scripts, never generated auth code.
import {readFileSync, writeFileSync, existsSync} from 'node:fs'
for (const name of ['qmplus-sync.js','qmplus-auth.js']) {
  const source=new URL(`../contracts/qmplus/${name}`,import.meta.url)
  const target=new URL(`../native/harmony/entry/src/main/resources/rawfile/${name}`,import.meta.url)
  const bytes=readFileSync(source)
  if(process.argv.includes('--check')) {
    if(!existsSync(target)||!readFileSync(target).equals(bytes))throw new Error(`Stale Harmony QM asset: ${name}`)
  } else writeFileSync(target,bytes)
}
