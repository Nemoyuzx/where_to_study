#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// A release signing profile does not imply that ArkTS was built in release mode.
// Inspect the installed module metadata, including every HAP inside an APP.
const packagePath = process.argv[2];
if (!packagePath || !/\.(hap|app)$/i.test(packagePath)) {
  console.error("Usage: node scripts/verify-harmony-release-package.mjs PACKAGE.hap|PACKAGE.app");
  process.exit(1);
}

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
}

let temporaryDirectory;
try {
  if (/\.hap$/i.test(packagePath)) {
    verifyModule(packagePath, packagePath);
  } else {
    const entries = execFileSync("unzip", ["-Z1", packagePath], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).split(/\r?\n/).filter((entry) => /\.hap$/i.test(entry));
    if (entries.length === 0) {
      throw new Error(`${packagePath}: HarmonyOS APP contains no HAP modules`);
    }
    temporaryDirectory = mkdtempSync(path.join(tmpdir(), "wts-harmony-release-"));
    for (const [index, entry] of entries.entries()) {
      // Never extract an archive-provided path into the filesystem.
      const modulePath = path.join(temporaryDirectory, `${index}.hap`);
      writeFileSync(modulePath, unzip(packagePath, entry));
      verifyModule(modulePath, `${packagePath}/${entry}`);
    }
  }
  console.log(`HarmonyOS release build mode verified: ${packagePath}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (temporaryDirectory) rmSync(temporaryDirectory, { recursive: true, force: true });
}
