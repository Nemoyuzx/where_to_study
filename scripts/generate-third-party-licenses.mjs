#!/usr/bin/env node

import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'
import spdxLicenseList from 'spdx-license-list/full.js'

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const OUTPUT_PATH = path.join(ROOT_DIR, 'THIRD_PARTY_LICENSES.html')
const CARGO_MANIFEST = path.join(ROOT_DIR, 'src-tauri', 'Cargo.toml')
const CARGO_PLATFORMS = [
  'aarch64-apple-darwin',
  'x86_64-apple-darwin',
  'x86_64-pc-windows-msvc',
]
const LICENSE_FILE_PATTERN = /^(license|licence|copying|copyright|notice|unlicense)([._-].*)?$/i
const MAX_LICENSE_FILE_BYTES = 2 * 1024 * 1024

function cargoMetadata(platform) {
  return JSON.parse(execFileSync('cargo', [
    'metadata',
    '--manifest-path', CARGO_MANIFEST,
    '--locked',
    '--format-version', '1',
    '--filter-platform', platform,
  ], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  }))
}

function runtimeCargoPackages() {
  const packages = new Map()
  for (const platform of CARGO_PLATFORMS) {
    const metadata = cargoMetadata(platform)
    const packageById = new Map(metadata.packages.map((item) => [item.id, item]))
    const nodeById = new Map(metadata.resolve.nodes.map((item) => [item.id, item]))
    const visited = new Set()

    function visit(packageId) {
      if (visited.has(packageId)) return
      visited.add(packageId)
      const current = packageById.get(packageId)
      if (current?.name !== 'where_to_study') packages.set(packageId, current)

      for (const dependency of nodeById.get(packageId)?.deps || []) {
        const isRuntimeDependency = dependency.dep_kinds.some((kind) => kind.kind === null)
        if (isRuntimeDependency) visit(dependency.pkg)
      }
    }

    visit(metadata.resolve.root)
  }
  return [...packages.values()].sort(packageSort)
}

function runtimeNpmPackages() {
  const lock = JSON.parse(fs.readFileSync(path.join(ROOT_DIR, 'package-lock.json'), 'utf8'))
  return Object.entries(lock.packages)
    .filter(([packagePath, item]) => packagePath && !item.dev)
    .map(([packagePath, item]) => ({
      name: packagePath.replace(/^node_modules\//, ''),
      version: item.version,
      license: item.license || 'UNKNOWN',
      directory: path.join(ROOT_DIR, packagePath),
      authors: [],
      ecosystem: 'npm',
    }))
    .sort(packageSort)
}

function packageSort(left, right) {
  return left.name.localeCompare(right.name, 'en') || left.version.localeCompare(right.version, 'en')
}

function packageLicenseFiles(item) {
  const directory = item.directory || path.dirname(item.manifest_path)
  const candidates = new Set()
  if (item.license_file) candidates.add(path.resolve(directory, item.license_file))
  for (const name of fs.readdirSync(directory)) {
    if (LICENSE_FILE_PATTERN.test(name)) candidates.add(path.join(directory, name))
  }

  return [...candidates]
    .filter((candidate) => {
      try {
        const stat = fs.statSync(candidate)
        return stat.isFile() && stat.size > 0 && stat.size <= MAX_LICENSE_FILE_BYTES
      } catch {
        return false
      }
    })
    .sort((left, right) => path.basename(left).localeCompare(path.basename(right), 'en'))
}

function normalizeLicenseText(value) {
  return value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replace(/[ \t]+$/gm, '')
    .trim()
}

function packageLabel(item) {
  return `${item.name}@${item.version} (${item.license || 'UNKNOWN'})`
}

function collectLicenses(packages, ecosystem, documents, missing) {
  for (const item of packages) {
    const descriptor = {
      label: packageLabel(item),
      ecosystem,
      authors: item.authors || [],
      license: item.license || 'UNKNOWN',
      repository: item.repository || '',
    }
    const files = packageLicenseFiles(item)
    if (files.length === 0) {
      missing.push(descriptor)
      continue
    }

    for (const file of files) {
      const text = normalizeLicenseText(fs.readFileSync(file, 'utf8'))
      if (!text) continue
      const hash = createHash('sha256').update(text).digest('hex')
      const document = documents.get(hash) || { text, packages: new Map() }
      document.packages.set(descriptor.label, descriptor)
      documents.set(hash, document)
    }
  }
}

function parseSpdxLicenseIds(expression) {
  if (/\bWITH\b/i.test(expression)) return []
  return [...new Set(expression
    .replaceAll('/', ' OR ')
    .replace(/[()]/g, ' ')
    .split(/\s+(?:AND|OR)\s+/i)
    .map((value) => value.trim())
    .filter(Boolean))]
}

function resolveMissingLicenseFiles(missing, documents) {
  const unresolved = []
  const resolved = []

  for (const descriptor of missing) {
    const licenseIds = parseSpdxLicenseIds(descriptor.license)
    if (licenseIds.length === 0) {
      unresolved.push(descriptor.label)
      continue
    }

    const entries = licenseIds.map((licenseId) => ({
      licenseId,
      entry: spdxLicenseList[licenseId],
    }))
    if (entries.some(({ entry }) => !entry?.licenseText)) {
      unresolved.push(descriptor.label)
      continue
    }

    for (const { licenseId, entry } of entries) {
      const text = normalizeLicenseText(entry.licenseText)
      const hash = createHash('sha256').update(`SPDX:${licenseId}\n${text}`).digest('hex')
      const document = documents.get(hash) || { text, packages: new Map() }
      document.packages.set(descriptor.label, descriptor)
      documents.set(hash, document)
    }
    resolved.push({ ...descriptor, licenseIds })
  }

  if (unresolved.length > 0) {
    throw new Error(`Missing packaged or SPDX license text for: ${unresolved.join(', ')}`)
  }
  return resolved
}

function addAndroidRuntimeLicenses(documents, missing) {
  const apacheDocument = [...documents.values()].find(({ text }) =>
    text.includes('Apache License') && text.includes('Version 2.0, January 2004'))
  const androidPackages = [
    'org.jetbrains.kotlin:kotlin-stdlib@1.9.25 (Apache-2.0)',
    'org.jetbrains:annotations@13.0 (Apache-2.0)',
  ]
  if (!apacheDocument) {
    for (const label of androidPackages) missing.push({ label, ecosystem: 'Gradle', authors: [] })
    return
  }
  for (const label of androidPackages) {
    apacheDocument.packages.set(label, { label, ecosystem: 'Gradle', authors: [] })
  }
}

function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
}

function renderInventory(title, packages) {
  const items = packages.map((item) => `<li>${escapeHtml(packageLabel(item))}</li>`).join('\n')
  return `<h2>${escapeHtml(title)}</h2>\n<ul>\n${items}\n</ul>`
}

function renderDocument(document, index) {
  const packages = [...document.packages.values()]
    .sort((left, right) => left.label.localeCompare(right.label, 'en'))
    .map((item) => {
      const details = []
      if (item.authors.length) details.push(`authors: ${item.authors.join(', ')}`)
      if (item.repository) details.push(`source: ${item.repository}`)
      const suffix = details.length ? `; ${details.join('; ')}` : ''
      return `<li>${escapeHtml(item.ecosystem)}: ${escapeHtml(item.label + suffix)}</li>`
    })
    .join('\n')
  return [
    `<section id="license-${index}">`,
    `<h2>License document ${index}</h2>`,
    '<ul>',
    packages,
    '</ul>',
    `<pre>${escapeHtml(document.text)}</pre>`,
    '</section>',
  ].join('\n')
}

function renderSpdxFallbacks(resolved) {
  if (resolved.length === 0) return ''
  const items = resolved
    .sort((left, right) => left.label.localeCompare(right.label, 'en'))
    .map((item) => {
      const authors = item.authors.length ? `; authors: ${item.authors.join(', ')}` : ''
      const repository = item.repository ? `; source: ${item.repository}` : ''
      const mappings = `; SPDX texts: ${item.licenseIds.join(', ')}`
      return `<li>${escapeHtml(item.ecosystem)}: ${escapeHtml(item.label + mappings + authors + repository)}</li>`
    })
    .join('\n')
  return [
    '<section>',
    '<h2>SPDX fallback mappings</h2>',
    '<p>These dependency archives omit a top-level license file. Their declared license expressions are mapped to the complete standard texts from the pinned SPDX License List; package authors and source repositories are retained below.</p>',
    '<ul>',
    items,
    '</ul>',
    '</section>',
  ].join('\n')
}

function generate() {
  const cargoPackages = runtimeCargoPackages()
  const npmPackages = runtimeNpmPackages()
  const documents = new Map()
  const missing = []
  collectLicenses(cargoPackages, 'Cargo', documents, missing)
  collectLicenses(npmPackages, 'npm', documents, missing)
  addAndroidRuntimeLicenses(documents, missing)
  const spdxFallbacks = resolveMissingLicenseFiles(missing, documents)

  const renderedDocuments = [...documents.values()]
    .sort((left, right) => {
      const leftLabel = [...left.packages.keys()].sort()[0]
      const rightLabel = [...right.packages.keys()].sort()[0]
      return leftLabel.localeCompare(rightLabel, 'en')
    })
    .map((document, index) => renderDocument(document, index + 1))
    .join('\n')

  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<title>Where To Study - Third-Party Licenses</title>',
    '<style>body{font:14px/1.5 system-ui,sans-serif;max-width:960px;margin:32px auto;padding:0 20px;color:#17201b}h1,h2{line-height:1.25}section{border-top:1px solid #d9dfda;padding-top:16px;margin-top:24px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f7f5;padding:16px}</style>',
    '</head>',
    '<body>',
    '<h1>Where To Study - Third-Party Licenses</h1>',
    '<p>This file is generated from the locked runtime dependency graphs. The Where To Study source itself is licensed separately under GPL-3.0-only. Data-source notices are in THIRD_PARTY_NOTICES.md.</p>',
    '<p>Standard fallback texts are supplied by spdx-license-list@6.12.0 (SPDX License List 3.28.0, CC0-1.0). Generation fails when a dependency has neither a packaged license file nor a resolvable SPDX text.</p>',
    renderInventory('Cargo runtime dependency inventory', cargoPackages),
    renderInventory('npm runtime dependency inventory', npmPackages),
    '<h2>Gradle runtime dependency inventory</h2>',
    '<ul><li>org.jetbrains.kotlin:kotlin-stdlib@1.9.25 (Apache-2.0)</li><li>org.jetbrains:annotations@13.0 (Apache-2.0)</li></ul>',
    renderSpdxFallbacks(spdxFallbacks),
    renderedDocuments,
    '</body>',
    '</html>',
    '',
  ].join('\n')
}

const generated = generate()
if (process.argv.includes('--check')) {
  const existing = fs.existsSync(OUTPUT_PATH) ? fs.readFileSync(OUTPUT_PATH, 'utf8') : ''
  if (existing !== generated) {
    console.error('THIRD_PARTY_LICENSES.html is stale. Run npm run licenses:generate.')
    process.exit(1)
  }
} else {
  fs.writeFileSync(OUTPUT_PATH, generated)
  console.log(`Wrote ${path.relative(ROOT_DIR, OUTPUT_PATH)}.`)
}
