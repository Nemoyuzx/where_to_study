import assert from 'node:assert/strict'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { verifyGlibSource, verifyResolvedGlib } from '../scripts/verify-glib-patch.mjs'

test('glib backport retains the complete reviewed source and the Cargo override', () => {
  assert.equal(verifyGlibSource().files, 121)
})

test('glib verification rejects the vulnerable registry source even at the expected version', () => {
  const manifestPath = fileURLToPath(new URL('../vendor/glib-0.18.5/Cargo.toml', import.meta.url))
  const glib = { id: 'glib-test', name: 'glib', version: '0.18.5', source: null, manifest_path: manifestPath }
  const metadata = { packages: [glib], resolve: { nodes: [{ id: glib.id }] } }
  assert.doesNotThrow(() => verifyResolvedGlib(metadata))
  assert.throws(() => verifyResolvedGlib({
    ...metadata,
    packages: [{ ...glib, source: 'registry+https://github.com/rust-lang/crates.io-index' }],
  }), /unpatched remote glib/)
  assert.throws(() => verifyResolvedGlib({
    ...metadata,
    packages: [{ ...glib, manifest_path: path.join(path.dirname(manifestPath), '..', 'other', 'Cargo.toml') }],
  }))
})
