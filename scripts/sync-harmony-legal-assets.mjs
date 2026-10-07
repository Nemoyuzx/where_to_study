#!/usr/bin/env node
import { copyFileSync, lstatSync, mkdirSync, readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const HARMONY_LEGAL_FILES = Object.freeze(['LICENSE', 'THIRD_PARTY_LICENSES.html', 'THIRD_PARTY_NOTICES.md']);
export const HARMONY_REPOSITORY_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function harmonyLegalSources(root = HARMONY_REPOSITORY_ROOT) {
  const base = realpathSync(root);
  return HARMONY_LEGAL_FILES.map(name => {
    const source = path.join(base, name);
    const stat = lstatSync(source);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`Harmony legal source must be a regular file: ${name}`);
    const bytes = readFileSync(source);
    if (!bytes.length) throw new Error(`Harmony legal source is empty: ${name}`);
    return { name, source, bytes };
  });
}

/** Generated public assets only; no signing configuration or arbitrary destination. */
export function syncHarmonyLegalAssets(root = HARMONY_REPOSITORY_ROOT) {
  const base = realpathSync(root);
  const inputs = harmonyLegalSources(base); // Validate every input before changing any output.
  let directory = base;
  for (const part of ['native', 'harmony', 'entry', 'src', 'main', 'resources', 'rawfile']) {
    directory = path.join(directory, part);
    if (!lstatSync(directory, { throwIfNoEntry: false })) mkdirSync(directory);
    const stat = lstatSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Harmony legal output directory must not be a symlink');
  }
  let copied = 0;
  for (const { name, source, bytes } of inputs) {
    const target = path.join(directory, name);
    const stat = lstatSync(target, { throwIfNoEntry: false });
    if (stat) {
      if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`Harmony legal output must be a regular file: ${name}`);
      if (readFileSync(target).equals(bytes)) continue;
    }
    copyFileSync(source, target); copied++;
  }
  return { files: inputs.length, copied };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 2) throw new Error('Usage: sync-harmony-legal-assets.mjs');
    const result = syncHarmonyLegalAssets();
    console.log(`Harmony public legal assets synchronized: ${result.files} files, ${result.copied} changed`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
