import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import vm from 'node:vm';
import { transformSync } from 'esbuild';
import { HARMONY_LEGAL_FILES, syncHarmonyLegalAssets } from '../scripts/sync-harmony-legal-assets.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'wts-harmony-legal-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const name of HARMONY_LEGAL_FILES) writeFileSync(path.join(root, name), `synthetic public ${name}\n`);
  return { root, output: path.join(root, 'native/harmony/entry/src/main/resources/rawfile') };
}
test('build asset step copies exact public bytes and preserves mtimes on identical rebuilds', t => {
  const { root, output } = fixture(t);
  assert.deepEqual(syncHarmonyLegalAssets(root), { files: 3, copied: 3 });
  const times = HARMONY_LEGAL_FILES.map(name => statSync(path.join(output, name)).mtimeMs);
  assert.deepEqual(syncHarmonyLegalAssets(root), { files: 3, copied: 0 });
  HARMONY_LEGAL_FILES.forEach((name, index) => {
    assert.deepEqual(readFileSync(path.join(output, name)), readFileSync(path.join(root, name)));
    assert.equal(statSync(path.join(output, name)).mtimeMs, times[index]);
  });
  writeFileSync(path.join(root, 'LICENSE'), 'synthetic changed public license');
  assert.deepEqual(syncHarmonyLegalAssets(root), { files: 3, copied: 1 });
});
test('a missing or empty public input fails before generating any output', t => {
  for (const missing of [true, false]) {
    const { root, output } = fixture(t);
    if (missing) rmSync(path.join(root, 'THIRD_PARTY_NOTICES.md'));
    else writeFileSync(path.join(root, 'THIRD_PARTY_NOTICES.md'), '');
    assert.throws(() => syncHarmonyLegalAssets(root));
    assert.equal(existsSync(output), false);
  }
});
test('symlinked source, parent or output cannot read/write outside the fixed asset destination', { skip: process.platform === 'win32' }, t => {
  const source = fixture(t);
  rmSync(path.join(source.root, 'LICENSE'));
  symlinkSync(path.join(source.root, 'THIRD_PARTY_NOTICES.md'), path.join(source.root, 'LICENSE'));
  assert.throws(() => syncHarmonyLegalAssets(source.root), /regular file/);
  const parent = fixture(t);
  mkdirSync(path.join(parent.root, 'outside')); symlinkSync(path.join(parent.root, 'outside'), path.join(parent.root, 'native'));
  assert.throws(() => syncHarmonyLegalAssets(parent.root), /symlink/);
  assert.deepEqual([...HARMONY_LEGAL_FILES].filter(name => existsSync(path.join(parent.root, 'outside', name))), []);
  const output = fixture(t); syncHarmonyLegalAssets(output.root);
  rmSync(path.join(output.output, 'LICENSE'));
  const outside = path.join(output.root, 'not-created');
  symlinkSync(outside, path.join(output.output, 'LICENSE'));
  assert.throws(() => syncHarmonyLegalAssets(output.root), /regular file/);
  assert.equal(existsSync(outside), false);
});
test('IDE and CLI both use the reviewed legal-asset step, with no private profile inputs', () => {
  const plugin = readFileSync(new URL('../native/harmony/entry/hvigorfile.ts', import.meta.url), 'utf8');
  assert.match(plugin, /sync-harmony-legal-assets.mjs/);
  assert.match(plugin, /execFileSync\(process\.execPath, \[script\]/);
  assert.match(plugin, /getNodeDir\(\)\.getPath\(\)/);
  assert.doesNotMatch(plugin, /build-profile|signingConfigs|storePassword|keyPassword/);
  const calls = [], module = { exports: {} }, builtin = {};
  vm.runInNewContext(transformSync(plugin, { loader: 'ts', format: 'cjs' }).code, {
    module, exports: module.exports, process: { execPath: '/runtime/node' },
    require: name => {
      if (name === '@ohos/hvigor-ohos-plugin') return { hapTasks: builtin };
      if (name === 'node:path') return path;
      if (name === 'node:child_process') return { execFileSync: (...args) => calls.push(args) };
      throw Error('Unexpected SDK dependency');
    },
  });
  const entry = module.exports.default;
  assert.equal(entry.system, builtin);
  const fixtureRoot = path.resolve('/fixture');
  entry.plugins[0].apply({ getNodeDir: () => ({ getPath: () => path.join(fixtureRoot, 'native/harmony/entry') }) });
  assert.equal(calls.length, 1); assert.equal(calls[0][0], '/runtime/node');
  assert.deepEqual([...calls[0][1]], [path.join(fixtureRoot, 'scripts/sync-harmony-legal-assets.mjs')]);
});
