#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { lstatSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { harmonyLegalSources } from './sync-harmony-legal-assets.mjs';

// A release signing profile does not imply that ArkTS was built in release mode.
// Inspect the installed module metadata, including every HAP inside an APP.
const [packagePath, option, compiledPath, ...extra] = process.argv.slice(2);
if (!packagePath || !/\.(hap|app)$/i.test(packagePath) || extra.length ||
    (option !== undefined && (option !== '--compiled-abc' || !compiledPath))) {
  console.error("Usage: node scripts/verify-harmony-release-package.mjs PACKAGE.hap|PACKAGE.app [--compiled-abc modules.abc]");
  process.exit(1);
}
// A valid local filename may start with '-'; never let archive tools parse it as an option.
const archivePath = path.resolve(packagePath);

function unzip(archive, entry) {
  return execFileSync("unzip", ["-p", archive, entry], {
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function verifyModule(archive, label) {
  const { app } = JSON.parse(unzip(archive, "module.json").toString("utf8"));
  if (app?.debug !== false || app?.buildMode !== "release") {
    throw new Error(
      `${label}: HarmonyOS release package requires app.debug=false and app.buildMode=release`,
    );
  }
  const entries = archiveEntries(archive);
  for (const { name, bytes } of harmonyLegalSources()) {
    const entry = `resources/rawfile/${name}`;
    if (entries.filter(value => value === entry).length !== 1 || !unzip(archive, entry).equals(bytes))
      throw new Error(`${label}: missing or changed exact public legal asset ${name}`);
  }
  if (compiledPath) {
    const stat = lstatSync(compiledPath);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('Compiled ArkTS reference must be a regular file');
    const expected = readFileSync(compiledPath);
    if (!expected.length || entries.filter(value => value === 'ets/modules.abc').length !== 1 ||
        !unzip(archive, 'ets/modules.abc').equals(expected))
      throw new Error(`${label}: packaged ArkTS does not match the current compiled modules.abc`);
  }
}

function archiveEntries(archive) {
  return execFileSync('unzip', ['-Z1', archive], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
    .split(/\r?\n/).filter(Boolean);
}
function safeModuleEntry(entry) {
  return !entry.startsWith('-') && !path.posix.isAbsolute(entry) && !/[\\:\x00-\x1f\x7f]/u.test(entry) &&
    entry.split('/').every(part => part && part !== '.' && part !== '..');
}

let temporaryDirectory;
try {
  if (/\.hap$/i.test(packagePath)) {
    verifyModule(archivePath, packagePath);
  } else {
    const entries = archiveEntries(archivePath).filter(entry => /\.hap$/i.test(entry));
    if (entries.length === 0) {
      throw new Error(`${packagePath}: HarmonyOS APP contains no HAP modules`);
    }
    if (new Set(entries).size !== entries.length || entries.some(entry => !safeModuleEntry(entry)))
      throw new Error('HarmonyOS APP contains an unsafe or duplicate module archive path');
    temporaryDirectory = mkdtempSync(path.join(tmpdir(), "wts-harmony-release-"));
    for (const [index, entry] of entries.entries()) {
      // Never extract an archive-provided path into the filesystem.
      const modulePath = path.join(temporaryDirectory, `${index}.hap`);
      writeFileSync(modulePath, unzip(archivePath, entry));
      verifyModule(modulePath, `${packagePath}/${entry}`);
    }
  }
  console.log(`HarmonyOS Release mode and exact legal assets${compiledPath ? ' and current ArkTS' : ''} verified: ${packagePath}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (temporaryDirectory) rmSync(temporaryDirectory, { recursive: true, force: true });
}
