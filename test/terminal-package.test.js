import assert from 'node:assert/strict'
import {execFileSync,spawnSync} from 'node:child_process'
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
  assert.match(source,/set -euo pipefail/)
  assert.equal((source.match(/tar -tzf/g)||[]).length,1,'read the archive listing exactly once')
  assert.doesNotMatch(source,/tar -tzf[^\n]*\|/,'no early-exiting consumer may SIGPIPE the archive reader')
  const fixture=mkdtempSync(path.join(tmpdir(),`wts-${kind}-legal-package-`))
  try{
    const bin=path.join(fixture,'tools');mkdirSync(bin)
    writeFileSync(path.join(bin,'sha256sum'),`#!${process.execPath}
const fs=require('node:fs'),crypto=require('node:crypto'),name=process.argv[2];
process.stdout.write(crypto.createHash('sha256').update(fs.readFileSync(name)).digest('hex')+'  '+name+'\\n');
`);chmodSync(path.join(bin,'sha256sum'),0o700)
    // A deliberately large streaming listing exposes early-consumer SIGPIPE on
    // any host, without depending on whether its tar buffers like GNU or BSD.
    const realTar=execFileSync('which',['tar'],{encoding:'utf8'}).trim()
    const listingReads=path.join(fixture,'listing-reads')
    writeFileSync(path.join(bin,'tar'),`#!${process.execPath}
const fs=require('node:fs'),cp=require('node:child_process');
const args=process.argv.slice(2),result=cp.spawnSync(${JSON.stringify(realTar)},args);
if(result.status!==0){process.stderr.write(result.stderr);process.exit(result.status??1)}
if(args[0]==='-tzf'){
  fs.appendFileSync(${JSON.stringify(listingReads)},'read\\n');
  let output=result.stdout;
  if(process.env.WTS_MISSING_LISTING_ENTRY==='1')output=Buffer.from(output.toString().split('\\n').filter(line=>line!=='THIRD_PARTY_NOTICES.md').join('\\n'));
  try{fs.writeSync(1,output);for(let i=0;i<128;i++)fs.writeSync(1,Buffer.alloc(8192,10))}
  catch(error){process.stderr.write('listing producer '+error.code+'\\n');process.exit(error.code==='EPIPE'?141:1)}
}else process.stdout.write(result.stdout);
`);chmodSync(path.join(bin,'tar'),0o700)
    const binary=Buffer.from('synthetic executable bytes; not run\n')
    mkdirSync(path.join(fixture,`wts-${kind}/target/release`),{recursive:true})
    writeFileSync(path.join(fixture,`wts-${kind}/target/release/where-to-study-${kind}`),binary)
    const expected=new Map(legal.map(name=>[name,readFileSync(new URL(name,root))]))
    for(const [name,bytes] of expected)writeFileSync(path.join(fixture,name),bytes)
    for(const arch of ['x86_64','aarch64']){
      const shell=source.replaceAll('${{ matrix.arch }}',arch)
      const env={...process.env,PATH:`${bin}${path.delimiter}${process.env.PATH}`,TMPDIR:fixture}
      execFileSync('bash',['-n','-c',shell],{cwd:fixture,env})
      const result=spawnSync('bash',['-c',shell],{cwd:fixture,env,encoding:'utf8'})
      assert.equal(result.status,0,`packaging status=${result.status} signal=${result.signal}; stderr=${result.stderr}`)
      assert.equal(readFileSync(listingReads,'utf8').trim().split('\n').length,arch==='x86_64'?1:2)
      const name=`where-to-study-${kind}-linux-${arch}.tar.gz`,archive=path.join(fixture,'release-artifacts',name)
      assert.deepEqual(execFileSync('tar',['-tzf',archive],{encoding:'utf8'}).trim().split('\n').sort(),[`where-to-study-${kind}`,...legal].sort())
      assert.equal(hash(execFileSync('tar',['-xOzf',archive,`where-to-study-${kind}`])),hash(binary))
      for(const [file,bytes] of expected)assert.equal(hash(execFileSync('tar',['-xOzf',archive,file])),hash(bytes))
      assert.equal(readFileSync(`${archive}.sha256`,'ascii'),`${hash(readFileSync(archive))}  ${name}\n`)
      if(arch==='x86_64'){
        const broken=spawnSync('bash',['-c','set -euo pipefail; tar -tzf "$1" | grep -qx "$2"','fixture',archive,`where-to-study-${kind}`],{cwd:fixture,env,encoding:'utf8'})
        assert.equal(broken.status,141,`old streaming pipeline status=${broken.status}; stderr=${broken.stderr}`)
        assert.match(broken.stderr,/listing producer EPIPE/)
        // Keep the one-read-per-production-package counter independent of the
        // deliberately failing old pipeline above.
        writeFileSync(listingReads,'read\n')
      }
    }
    const missingEntry=spawnSync('bash',['-c',source.replaceAll('${{ matrix.arch }}','x86_64')],{cwd:fixture,env:{...process.env,PATH:`${bin}${path.delimiter}${process.env.PATH}`,TMPDIR:fixture,WTS_MISSING_LISTING_ENTRY:'1'},encoding:'utf8'})
    assert.notEqual(missingEntry.status,0,'an archive missing a required legal entry must still fail')
    rmSync(path.join(fixture,'THIRD_PARTY_NOTICES.md'))
    assert.throws(()=>execFileSync('bash',['-c',source.replaceAll('${{ matrix.arch }}','x86_64')],{cwd:fixture,env:{...process.env,PATH:`${bin}${path.delimiter}${process.env.PATH}`,TMPDIR:fixture},stdio:'pipe'}),'missing legal payload must fail the packaging step')
  }finally{rmSync(fixture,{recursive:true,force:true})}
})
