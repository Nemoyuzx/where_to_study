import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { HARMONY_LEGAL_FILES } from '../scripts/sync-harmony-legal-assets.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const verifier = path.join(root, "scripts/verify-harmony-release-package.mjs");

test("HarmonyOS builds release packages while keeping Hypium in test mode", () => {
  const source = readFileSync(path.join(root, "scripts/native-harmony-build.sh"), "utf8");
  assert.match(source, /"\$HVIGOR" assembleHap -p buildMode=release/);
  assert.match(source, /"\$HVIGOR" test --mode module -p module=entry -p buildMode=test/);
  assert.match(source, /"\$HVIGOR" assembleApp -p buildMode=release/);
  for (const artifact of ["SIGNED_HAP", "SIGNED_APP"]) {
    assert.ok(source.includes(`node "$ROOT_DIR/scripts/verify-harmony-release-package.mjs" "$${artifact}" --compiled-abc "$COMPILED_ABC"`));
  }
  assert.match(source, /--compiled-abc "\$COMPILED_ABC"/);
  assert.match(source, /node "\$ROOT_DIR\/scripts\/sync-harmony-legal-assets.mjs"/);
});

const packageTest = (name, run) => test(name, { skip: process.platform === "win32" }, () => {
  const directory = mkdtempSync(path.join(tmpdir(), "wts-harmony-package-test-"));
  const makeHap = (name, app, { omit, changed, abc = Buffer.from('synthetic-current-abc') } = {}) => {
    writeFileSync(path.join(directory, "module.json"), JSON.stringify({ app }));
    mkdirSync(path.join(directory, 'resources/rawfile'), { recursive: true });
    const entries = ['module.json'];
    for (const legal of HARMONY_LEGAL_FILES) {
      if (legal === omit) continue;
      const entry = `resources/rawfile/${legal}`;
      const bytes = readFileSync(path.join(root, legal));
      writeFileSync(path.join(directory, entry), legal === changed ? Buffer.concat([bytes, Buffer.from('\nchanged-synthetic')]) : bytes);
      entries.push(entry);
    }
    if (abc !== null) {
      mkdirSync(path.join(directory, 'ets'), { recursive: true });
      writeFileSync(path.join(directory, 'ets/modules.abc'), abc);
      entries.push('ets/modules.abc');
    }
    execFileSync("zip", ["-q", `${name}.hap`, ...entries], { cwd: directory });
    return path.join(directory, `${name}.hap`);
  };
  const makeApp = (names) => {
    execFileSync("zip", ["-q", "test.app", ...names], { cwd: directory });
    return path.join(directory, "test.app");
  };
  const verify = (artifact, args = []) => spawnSync(process.execPath, [verifier, artifact, ...args], { encoding: "utf8" });
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
packageTest('a leading-dash local archive name is a path, not an unzip option', ({ directory, makeHap }) => {
  renameSync(makeHap('entry', { debug: false, buildMode: 'release' }), path.join(directory, '-entry.hap'));
  const result = spawnSync(process.execPath, [verifier, '-entry.hap'], { cwd: directory, encoding: 'utf8' });
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

for (const name of HARMONY_LEGAL_FILES) packageTest(`rejects a Release HAP missing ${name}`, ({ makeHap, verify }) => {
  const result = verify(makeHap('missing', { debug: false, buildMode: 'release' }, { omit: name }));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /missing or changed exact public legal asset/);
});
packageTest('rejects changed legal bytes in a later nested APP module', ({ makeHap, makeApp, verify }) => {
  makeHap('entry', { debug: false, buildMode: 'release' });
  makeHap('feature', { debug: false, buildMode: 'release' }, { changed: 'THIRD_PARTY_NOTICES.md' });
  const result = verify(makeApp(['entry.hap', 'feature.hap']));
  assert.equal(result.status, 1); assert.match(result.stderr, /feature.hap:.*missing or changed exact public legal asset/);
});
packageTest('current compiled ArkTS matches both HAP and the actual nested APP payload', ({ directory, makeHap, makeApp, verify }) => {
  const reference = path.join(directory, 'current.abc'); writeFileSync(reference, 'synthetic-current-abc');
  const hap = makeHap('entry', { debug: false, buildMode: 'release' });
  assert.equal(verify(hap, ['--compiled-abc', reference]).status, 0);
  assert.equal(verify(makeApp(['entry.hap']), ['--compiled-abc', reference]).status, 0);
});
for (const missing of [false, true]) packageTest(`rejects ${missing ? 'missing' : 'stale'} ArkTS in an actual APP payload`,
  ({ directory, makeHap, makeApp, verify }) => {
    const reference = path.join(directory, 'current.abc'); writeFileSync(reference, 'synthetic-current-abc');
    makeHap('entry', { debug: false, buildMode: 'release' }, { abc: missing ? null : Buffer.from('synthetic-stale-abc') });
    const result = verify(makeApp(['entry.hap']), ['--compiled-abc', reference]);
    assert.equal(result.status, 1); assert.match(result.stderr, /packaged ArkTS does not match/);
  });

for (const unsafe of ['../e_.hap', '/bad_.hap', 'x\\bad.hap', '-evil.hap']) packageTest('rejects unsafe APP module archive path ' + JSON.stringify(unsafe),
  ({ directory, makeHap, makeApp, verify }) => {
    makeHap('entry', { debug: false, buildMode: 'release' });
    const archive = makeApp(['entry.hap']);
    const bytes = readFileSync(archive); const from = Buffer.from('entry.hap'), to = Buffer.from(unsafe);
    assert.equal(to.length, from.length);
    for (let offset = bytes.indexOf(from); offset >= 0; offset = bytes.indexOf(from, offset + to.length)) to.copy(bytes, offset);
    writeFileSync(archive, bytes);
    const result = verify(archive);
    assert.equal(result.status, 1); assert.match(result.stderr, /unsafe or duplicate module archive path/);
  });
packageTest('rejects duplicate APP module entries instead of validating only the first', ({ makeHap, makeApp, verify }) => {
  makeHap('entry', { debug: false, buildMode: 'release' });
  makeHap('other', { debug: false, buildMode: 'release' });
  const archive = makeApp(['entry.hap', 'other.hap']);
  const bytes = readFileSync(archive), from = Buffer.from('other.hap'), to = Buffer.from('entry.hap');
  for (let offset = bytes.indexOf(from); offset >= 0; offset = bytes.indexOf(from, offset + to.length)) to.copy(bytes, offset);
  writeFileSync(archive, bytes);
  const result = verify(archive);
  assert.equal(result.status, 1); assert.match(result.stderr, /unsafe or duplicate module archive path/);
});
