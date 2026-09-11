import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, chmodSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

test('Linux bundles remap checkout paths without dropping explicit Rust flags', { skip: process.platform === 'win32' }, () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'wts build flags '))
  try {
    mkdirSync(path.join(directory, 'scripts'))
    writeFileSync(path.join(directory, 'scripts', 'linux-build.sh'), readFileSync(path.join(root, 'scripts', 'linux-build.sh')))
    const tools = path.join(directory, 'tools')
    mkdirSync(tools)
    writeFileSync(path.join(tools, 'npm'), '#!/bin/sh\nprintf "%s" "$CARGO_ENCODED_RUSTFLAGS"\n')
    chmodSync(path.join(tools, 'npm'), 0o700)
    const common = { ...process.env, PATH: `${tools}:${process.env.PATH}`, RUSTFLAGS: '-C opt-level=3 -C strip=symbols' }
    delete common.CARGO_ENCODED_RUSTFLAGS
    const run = (env) => execFileSync('bash', [path.join(directory, 'scripts', 'linux-build.sh')], { env, encoding: 'utf8' }).split('\x1f')
    // macOS may canonicalize its temporary directory through /private.
    const flags = run(common)
    assert.deepEqual(flags.slice(0, 4), ['-C', 'opt-level=3', '-C', 'strip=symbols'])
    assert.match(flags.at(-1), /--remap-path-prefix=.*wts build flags .*=\.$/)
    assert.equal(flags.length, 5)
    assert.deepEqual(run({ ...common, CARGO_ENCODED_RUSTFLAGS: '-C\x1fdebuginfo=0' }).slice(0, 2), ['-C', 'debuginfo=0'])
    assert.equal(run({ ...common, CARGO_ENCODED_RUSTFLAGS: '' }).length, 1)
  } finally { rmSync(directory, { recursive: true, force: true }) }
})
