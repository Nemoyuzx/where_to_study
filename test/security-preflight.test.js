import test from 'node:test';
import assert from 'node:assert/strict';
import { parseUpdates, runPreflight } from '../scripts/security-preflight.mjs';
import { installHooks } from '../scripts/install-git-hooks.mjs';

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
test('installer preserves every default non-sample hook, is idempotent and local only', () => {
  for (const [hooks, entries, rejects] of [
    ['custom', [], true], ['', ['pre-push'], true], ['', ['pre-commit'], true],
    ['', ['post-checkout'], true], ['', ['custom-directory'], true],
    ['', ['pre-commit.sample', 'pre-push.sample'], false], ['', [], false],
    ['scripts/git-hooks', ['pre-commit'], false],
  ]) {
    const calls = [];
    const exec = (_, args) => { calls.push(args); return { status: args[0] === 'config' && args[1] === '--get' && !hooks ? 1 : 0, stdout: args[0] === 'config' && args[1] === '--get' ? hooks : '/repo' }; };
    const action = () => installHooks({ exec, exists: () => entries.length > 0, readdir: () => entries, chmod() {} });
    if (rejects) assert.throws(action); else action();
    assert.equal(calls.some(args => args.includes('--local')), !rejects);
    assert.ok(!calls.some(args => args.includes('--global')));
    if (!hooks) assert.ok(calls.some(args => args.join(' ') === 'rev-parse --git-path hooks'));
  }
});
