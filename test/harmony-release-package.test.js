import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const verifier = path.join(root, "scripts/verify-harmony-release-package.mjs");

test("HarmonyOS builds release packages while keeping Hypium in test mode", () => {
  const source = readFileSync(path.join(root, "scripts/native-harmony-build.sh"), "utf8");
  assert.match(source, /"\$HVIGOR" assembleHap -p buildMode=release/);
  assert.match(source, /"\$HVIGOR" test --mode module -p module=entry -p buildMode=test/);
  assert.match(source, /"\$HVIGOR" assembleApp -p buildMode=release/);
  for (const artifact of ["SIGNED_HAP", "SIGNED_APP"]) {
    assert.ok(source.includes(`node "$ROOT_DIR/scripts/verify-harmony-release-package.mjs" "$${artifact}"`));
  }
});

const packageTest = (name, run) => test(name, { skip: process.platform === "win32" }, () => {
  const directory = mkdtempSync(path.join(tmpdir(), "wts-harmony-package-test-"));
  const makeHap = (name, app) => {
    writeFileSync(path.join(directory, "module.json"), JSON.stringify({ app }));
    execFileSync("zip", ["-q", `${name}.hap`, "module.json"], { cwd: directory });
    return path.join(directory, `${name}.hap`);
  };
  const makeApp = (names) => {
    execFileSync("zip", ["-q", "test.app", ...names], { cwd: directory });
    return path.join(directory, "test.app");
  };
  const verify = (artifact) => spawnSync(process.execPath, [verifier, artifact], { encoding: "utf8" });
  try {
    run({ directory, makeHap, makeApp, verify });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

packageTest("accepts an actual Release HAP", ({ makeHap, verify }) => {
  const result = verify(makeHap("release", { debug: false, buildMode: "release" }));
  assert.equal(result.status, 0, result.stderr);
});

for (const [name, app] of [
  ["debug enabled", { debug: true, buildMode: "release" }],
  ["debug mode", { debug: false, buildMode: "debug" }],
  ["test mode", { debug: false, buildMode: "test" }],
  ["missing debug flag", { buildMode: "release" }],
]) {
  packageTest(`rejects a HAP with ${name}`, ({ makeHap, verify }) => {
    const result = verify(makeHap("invalid", app));
    assert.equal(result.status, 1);
    assert.match(result.stderr, /requires app.debug=false and app.buildMode=release/);
  });
}

packageTest("accepts an APP whose nested HAPs are all Release", ({ makeHap, makeApp, verify }) => {
  makeHap("entry", { debug: false, buildMode: "release" });
  makeHap("feature", { debug: false, buildMode: "release" });
  const result = verify(makeApp(["entry.hap", "feature.hap"]));
  assert.equal(result.status, 0, result.stderr);
});

packageTest("rejects an APP when a later nested HAP is Debug", ({ makeHap, makeApp, verify }) => {
  makeHap("entry", { debug: false, buildMode: "release" });
  makeHap("feature", { debug: true, buildMode: "debug" });
  const result = verify(makeApp(["entry.hap", "feature.hap"]));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /feature.hap:.*requires app.debug=false/);
});

packageTest("rejects an APP without an installable module", ({ directory, makeApp, verify }) => {
  writeFileSync(path.join(directory, "pack.info"), "{}");
  const result = verify(makeApp(["pack.info"]));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /contains no HAP modules/);
});
