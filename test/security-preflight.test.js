import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseUpdates, runPreflight } from '../scripts/security-preflight.mjs';
import { installHooks, OWNED_HOOK_MARKER } from '../scripts/install-git-hooks.mjs';

const head = 'a'.repeat(40), base = 'b'.repeat(40), nil = '0'.repeat(40);
function harness({ dirty = '', untracked = '', commit = head, fail = '', version = '8.30.1' } = {}) {
  const calls = [];
  const exec = (command, args, options) => {
    calls.push({ command, args, options });
    let stdout = '';
    if (command === 'gitleaks' && args[0] === 'version') stdout = version;
    if (command === 'git') {
      if (args[0] === 'rev-parse') stdout = args.includes('--show-toplevel') ? '/repo' : args.includes('--verify') ? commit : head;
      if (args[0] === 'diff') stdout = args.includes('--name-only') ? dirty : 'tracked diff';
      if (args[0] === 'ls-files') stdout = untracked;
    }
    return { status: command === fail ? 1 : 0, stdout };
  };
  return { exec, calls };
}
const record = (local = head, remote = base) => `refs/heads/main ${local} refs/heads/main ${remote}\n`;
test('strict ref parsing supports sha1/sha256 and deletes only', () => {
  assert.equal(parseUpdates(record()).length, 1);
  assert.equal(parseUpdates(record('a'.repeat(64), '0'.repeat(64))).length, 1);
  assert.deepEqual(parseUpdates(record(nil)), []);
  for (const value of ['bad', record('x'.repeat(40)), record(head, '0'.repeat(64)), record() + 'extra']) assert.throws(() => parseUpdates(value));
});
test('hook scans actual outgoing range and all proportional checks', () => {
  const h = harness(); runPreflight({ ...h, hook: true, input: record(), log() {} });
  assert.ok(h.calls.some(c => c.command === 'gitleaks' && c.args.includes(`${base}..${head}`) && c.args.includes('--redact=100')));
  assert.ok(h.calls.some(c => c.command === 'npm' && c.args[0] === 'test'));
  assert.ok(h.calls.findIndex(c => c.args[0] === 'scripts/check-test-credentials.mjs') < h.calls.findIndex(c => c.command === 'npm' && c.args[0] === 'test'));
  assert.ok(h.calls.some(c => c.command === 'npm' && c.args.join(' ') === 'run build'));
  const rust = h.calls.filter(c => c.command === 'cargo' && c.args.includes('--manifest-path'));
  assert.equal(rust.length, 3);
  assert.ok(rust.slice(1).every(c => c.args.includes('--locked') && c.args.includes('2')));
  assert.ok(rust[2].args.includes('warnings'));
});
test('new refs scan full reachable history; delete refs perform no work', () => {
  const h = harness(); runPreflight({ ...h, hook: true, input: record(head, nil), log() {} });
  assert.ok(h.calls.some(c => c.command === 'gitleaks' && c.args.includes(head)));
  const deleted = harness(); runPreflight({ ...deleted, hook: true, input: record(nil), log() {} }); assert.equal(deleted.calls.length, 0);
});
test('wrong outgoing worktree and dirty source fail closed; Markdown only allowed', () => {
  for (const config of [{ commit: base }, { dirty: 'src/a.js\0' }, { untracked: 'new.rs\0' }]) {
    const h = harness(config); assert.throws(() => runPreflight({ ...h, hook: true, input: record(), log() {} }));
    assert.ok(!h.calls.some(c => c.command === 'npm' && c.args[0] === 'test'));
  }
  runPreflight({ ...harness({ dirty: 'docs/notes.md\0' }), hook: true, input: record(), log() {} });
});
test('manual scans HEAD plus only tracked diff, Windows uses npm.cmd', () => {
  const h = harness(); runPreflight({ ...h, platform: 'win32', log() {} });
  assert.ok(h.calls.some(c => c.command === 'gitleaks' && c.args.includes('-1 HEAD')));
  assert.equal(h.calls.find(c => c.command === 'gitleaks' && c.args[0] === 'stdin').options.input, 'tracked diff');
  assert.ok(h.calls.some(c => c.command === 'npm.cmd' && c.args[0] === 'test'));
  assert.ok(h.calls.filter(c => c.command === 'npm.cmd').every(c => c.options.shell === true));
  assert.ok(!h.calls.some(c => c.args[0] === 'ls-files'));
});
test('missing tools/old scanner fail, tool-only never silently runs as hook', () => {
  for (const fail of ['git', 'gitleaks', 'npm', 'cargo']) assert.throws(() => runPreflight({ ...harness({ fail }), log() {} }));
  assert.throws(() => runPreflight({ ...harness({ version: '7.0' }), log() {} }));
  assert.throws(() => runPreflight({ ...harness(), hook: true, input: record(), checkOnly: true, log() {} }));
  const h = harness(); runPreflight({ ...h, checkOnly: true, log() {} });
  assert.ok(!h.calls.some(c => c.command === 'npm' && c.args[0] === 'test'));
});
function hookFixture(t, initialHooks = '') {
  const temporary = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'wts-hook-policy-')));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const root = join(temporary, 'checkout');
  const common = join(temporary, 'common.git');
  const defaults = join(common, 'hooks');
  const directory = join(common, 'wts-hooks');
  const target = join(directory, 'pre-push');
  fs.mkdirSync(join(root, 'scripts/git-hooks'), { recursive: true });
  fs.mkdirSync(defaults, { recursive: true });
  const source = fs.readFileSync(new URL('../scripts/git-hooks/pre-push', import.meta.url), 'utf8');
  fs.writeFileSync(join(root, 'scripts/git-hooks/pre-push'), source);
  const calls = []; let hooks = initialHooks;
  const exec = (_, args) => {
    calls.push(args);
    if (args[0] === 'config') {
      if (args[1] === '--get') return { status: hooks ? 0 : 1, stdout: hooks };
      hooks = args.at(-1); return { status: 0, stdout: '' };
    }
    return { status: 0, stdout: args.includes('--show-toplevel') ? root : args.includes('--git-common-dir') ? common : defaults };
  };
  return { root, common, defaults, directory, target, source, calls, exec, hooks: () => hooks };
}
test('installer writes identical executable hook to stable common-dir path, is idempotent and local only', t => {
  const h = hookFixture(t, 'scripts/git-hooks');
  installHooks({ exec: h.exec }); installHooks({ exec: h.exec });
  assert.equal(h.hooks(), h.directory);
  assert.equal(fs.readFileSync(h.target, 'utf8'), h.source);
  assert.ok(h.source.startsWith(OWNED_HOOK_MARKER));
  assert.equal(fs.statSync(h.target).mode & 0o777, 0o755);
  assert.deepEqual(fs.readdirSync(h.directory), ['pre-push']);
  assert.ok(h.calls.filter(args => args[0] === 'config' && args[1] !== '--get').every(args => args[1] === '--local' && args.at(-1) === h.directory));
});
test('installer refuses foreign hooksPath, foreign destination and any default non-sample hook', t => {
  const foreign = hookFixture(t, '/foreign/hooks');
  assert.throws(() => installHooks({ exec: foreign.exec }), /not ours/u);
  for (const name of ['pre-push', 'pre-commit', 'post-checkout', 'custom-directory']) {
    const h = hookFixture(t);
    if (name === 'custom-directory') fs.mkdirSync(join(h.defaults, name)); else fs.writeFileSync(join(h.defaults, name), 'foreign');
    assert.throws(() => installHooks({ exec: h.exec }), /non-sample/u);
    assert.equal(h.hooks(), '');
    assert.ok(!fs.existsSync(h.directory));
  }
  for (const kind of ['empty', 'foreign', 'extra', 'symlink']) {
    const h = hookFixture(t, 'scripts/git-hooks');
    if (kind === 'symlink') fs.symlinkSync(h.defaults, h.directory, 'dir');
    else {
      fs.mkdirSync(h.directory);
      if (kind !== 'empty') fs.writeFileSync(h.target, kind === 'foreign' ? '#!/bin/sh\nforeign' : h.source);
      if (kind === 'extra') fs.writeFileSync(join(h.directory, 'pre-commit'), 'foreign');
    }
    assert.throws(() => installHooks({ exec: h.exec }), /not ours/u);
    assert.equal(h.hooks(), 'scripts/git-hooks');
  }
  const samples = hookFixture(t);
  fs.writeFileSync(join(samples.defaults, 'pre-push.sample'), 'sample');
  installHooks({ exec: samples.exec });
  assert.equal(fs.readFileSync(join(samples.defaults, 'pre-push.sample'), 'utf8'), 'sample');
  const migration = hookFixture(t, 'scripts/git-hooks');
  fs.writeFileSync(join(migration.root, 'scripts/git-hooks/pre-commit'), 'foreign');
  assert.throws(() => installHooks({ exec: migration.exec }), /refusing to hide/u);
  const hiddenDefault = hookFixture(t, 'scripts/git-hooks');
  fs.writeFileSync(join(hiddenDefault.defaults, 'pre-commit'), 'foreign');
  assert.throws(() => installHooks({ exec: hiddenDefault.exec }), /non-sample/u);
});
test('atomic hook generation failures never switch config or replace the existing hook', t => {
  for (const operation of ['writeFileSync', 'chmodSync', 'renameSync']) {
    const h = hookFixture(t, 'scripts/git-hooks');
    const adapter = { ...fs, [operation]() { throw new Error('simulated atomic failure'); } };
    assert.throws(() => installHooks({ exec: h.exec, fs: adapter }), /simulated/u);
    assert.equal(h.hooks(), 'scripts/git-hooks');
    assert.ok(!fs.existsSync(h.directory));
  }
  const h = hookFixture(t, 'scripts/git-hooks');
  installHooks({ exec: h.exec });
  const before = fs.readFileSync(h.target, 'utf8');
  assert.throws(() => installHooks({ exec: h.exec, fs: { ...fs, renameSync() { throw new Error('simulated'); } } }), /simulated/u);
  assert.equal(fs.readFileSync(h.target, 'utf8'), before);
  assert.deepEqual(fs.readdirSync(h.directory), ['pre-push']);
  const configFailure = hookFixture(t, 'scripts/git-hooks');
  const failingExec = (command, args, options) => args[0] === 'config' && args[1] === '--local'
    ? { status: 1, stdout: '' } : configFailure.exec(command, args, options);
  assert.throws(() => installHooks({ exec: failingExec }), /Cannot inspect/u);
  assert.equal(configFailure.hooks(), 'scripts/git-hooks');
  assert.equal(fs.readFileSync(configFailure.target, 'utf8'), configFailure.source);
  assert.deepEqual(fs.readdirSync(configFailure.directory), ['pre-push']);
  const collision = hookFixture(t, 'scripts/git-hooks');
  let foreignTemporary;
  assert.throws(() => installHooks({ exec: collision.exec, fs: { ...fs, openSync(file) {
    foreignTemporary = file; fs.writeFileSync(file, 'foreign'); throw new Error('simulated collision');
  } } }), /collision/u);
  assert.equal(fs.readFileSync(foreignTemporary, 'utf8'), 'foreign');
  assert.equal(collision.hooks(), 'scripts/git-hooks');
});
test('stable generated hook blocks old branches missing preflight instead of silently bypassing', t => {
  const h = hookFixture(t);
  installHooks({ exec: h.exec });
  assert.equal(spawnSync('git', ['init', '-q', h.root]).status, 0);
  fs.rmSync(join(h.root, 'scripts'), { recursive: true });
  const result = spawnSync('sh', [h.target], { cwd: h.root, encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /this branch has no security preflight/u);
  assert.ok(fs.existsSync(h.target));
});
