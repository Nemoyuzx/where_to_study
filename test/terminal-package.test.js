import assert from 'node:assert/strict'
import {execFileSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import {chmodSync,mkdirSync,mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs'
import {tmpdir} from 'node:os'
import path from 'node:path'
import test from 'node:test'

const root=new URL('../',import.meta.url)
const legal=['LICENSE','THIRD_PARTY_LICENSES.html','THIRD_PARTY_NOTICES.md']
const hash=bytes=>createHash('sha256').update(bytes).digest('hex')
for(const kind of ['cli','tui'])test(`Linux ${kind} packaging preserves the executable, ships exact legal files and rejects an incomplete payload`,{skip:process.platform==='win32'},()=>{
  const workflow=readFileSync(new URL(`.github/workflows/build-${kind}.yml`,root),'utf8')
  const marker=`      - name: Package Linux ${kind.toUpperCase()}\n        run: |\n`
  const start=workflow.indexOf(marker),end=workflow.indexOf('\n      - name:',start+marker.length)
  assert.ok(start>=0&&end>start,'exercise the actual production packaging shell')
  const source=workflow.slice(start+marker.length,end).replace(/^          /gm,'')
  const fixture=mkdtempSync(path.join(tmpdir(),`wts-${kind}-legal-package-`))
  try{
    const bin=path.join(fixture,'tools');mkdirSync(bin)
    writeFileSync(path.join(bin,'sha256sum'),`#!${process.execPath}
const fs=require('node:fs'),crypto=require('node:crypto'),name=process.argv[2];
process.stdout.write(crypto.createHash('sha256').update(fs.readFileSync(name)).digest('hex')+'  '+name+'\\n');
`);chmodSync(path.join(bin,'sha256sum'),0o700)
    const binary=Buffer.from('synthetic executable bytes; not run\n')
    mkdirSync(path.join(fixture,`wts-${kind}/target/release`),{recursive:true})
    writeFileSync(path.join(fixture,`wts-${kind}/target/release/where-to-study-${kind}`),binary)
    const expected=new Map(legal.map(name=>[name,readFileSync(new URL(name,root))]))
    for(const [name,bytes] of expected)writeFileSync(path.join(fixture,name),bytes)
    for(const arch of ['x86_64','aarch64']){
      const shell=source.replaceAll('${{ matrix.arch }}',arch)
      const env={...process.env,PATH:`${bin}${path.delimiter}${process.env.PATH}`,TMPDIR:fixture}
      execFileSync('bash',['-n','-c',shell],{cwd:fixture,env})
      execFileSync('bash',['-c',shell],{cwd:fixture,env})
      const name=`where-to-study-${kind}-linux-${arch}.tar.gz`,archive=path.join(fixture,'release-artifacts',name)
      assert.deepEqual(execFileSync('tar',['-tzf',archive],{encoding:'utf8'}).trim().split('\n').sort(),[`where-to-study-${kind}`,...legal].sort())
      assert.equal(hash(execFileSync('tar',['-xOzf',archive,`where-to-study-${kind}`])),hash(binary))
      for(const [file,bytes] of expected)assert.equal(hash(execFileSync('tar',['-xOzf',archive,file])),hash(bytes))
      assert.equal(readFileSync(`${archive}.sha256`,'ascii'),`${hash(readFileSync(archive))}  ${name}\n`)
    }
    rmSync(path.join(fixture,'THIRD_PARTY_NOTICES.md'))
    assert.throws(()=>execFileSync('bash',['-c',source.replaceAll('${{ matrix.arch }}','x86_64')],{cwd:fixture,env:{...process.env,PATH:`${bin}${path.delimiter}${process.env.PATH}`,TMPDIR:fixture},stdio:'pipe'}),'missing legal payload must fail the packaging step')
  }finally{rmSync(fixture,{recursive:true,force:true})}
})
