#!/usr/bin/env node

import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const VENDOR_PATH = path.join(ROOT, 'vendor', 'glib-0.18.5')
const PATCHED_TREE_SHA256 = 'f22fab2b2dfb31cee274824539dce5b1f601dc80eab177fbbf56eb72834bb356'

function sourceFiles(directory, prefix = '') {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name
    assert.ok(!entry.isSymbolicLink(), `Unexpected vendored symlink: ${relative}`)
    if (entry.isDirectory()) return sourceFiles(path.join(directory, entry.name), relative)
    assert.ok(entry.isFile(), `Unexpected vendored entry: ${relative}`)
    return [relative]
  })
}

export function verifyGlibSource() {
  const files = sourceFiles(VENDOR_PATH).sort()
  assert.equal(files.length, 121, 'The glib archive file inventory changed')
  const digest = createHash('sha256')
  for (const relative of files) {
    digest.update(relative).update('\0')
    digest.update(fs.readFileSync(path.join(VENDOR_PATH, relative))).update('\0')
  }
  assert.equal(digest.digest('hex'), PATCHED_TREE_SHA256, 'The reviewed glib backport source changed')

  const manifest = fs.readFileSync(path.join(ROOT, 'src-tauri', 'Cargo.toml'), 'utf8')
  assert.match(manifest, /\[patch\.crates-io\]\s+glib\s*=\s*\{\s*path\s*=\s*"\.\.\/vendor\/glib-0\.18\.5"\s*\}/)
  const lockfile = fs.readFileSync(path.join(ROOT, 'src-tauri', 'Cargo.lock'), 'utf8')
  const glibPackages = lockfile.split('[[package]]').filter((entry) => /\bname = "glib"\r?\n/.test(entry))
  assert.equal(glibPackages.length, 1, 'The Tauri lockfile must contain exactly one glib package')
  assert.match(glibPackages[0], /\bversion = "0\.18\.5"\r?\n/)
  assert.doesNotMatch(glibPackages[0], /\b(?:source|checksum) =/, 'The Tauri lockfile resolves registry glib instead of the backport')
  return { files: files.length, sha256: PATCHED_TREE_SHA256 }
}

export function verifyResolvedGlib(metadata) {
  const glibPackages = metadata.packages.filter((item) => item.name === 'glib')
  assert.equal(glibPackages.length, 1, 'The Linux dependency graph must contain exactly one glib package')
  const glib = glibPackages[0]
  assert.equal(glib.version, '0.18.5')
  assert.equal(glib.source, null, 'The Linux dependency graph uses an unpatched remote glib')
  assert.equal(path.resolve(glib.manifest_path), path.join(VENDOR_PATH, 'Cargo.toml'))
  assert.ok(metadata.resolve.nodes.some((node) => node.id === glib.id), 'The backport is not in the resolved Linux graph')
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = verifyGlibSource()
  if (process.argv.includes('--resolve')) {
    const metadata = JSON.parse(execFileSync('cargo', [
      'metadata', '--manifest-path', path.join(ROOT, 'src-tauri', 'Cargo.toml'),
      '--locked', '--format-version', '1', '--filter-platform', 'x86_64-unknown-linux-gnu',
    ], { cwd: ROOT, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }))
    verifyResolvedGlib(metadata)
  }
  console.log(`Verified glib 0.18.5 upstream backport: ${result.files} files, SHA-256 ${result.sha256}`)
}
