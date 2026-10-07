import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const oid = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/i;
const zero = /^0+$/;
export function withoutLocalGitEnvironment(environment, names) {
  const local = new Set(names.map(name => name.toUpperCase()));
  return Object.fromEntries(Object.entries(environment).filter(([name]) =>
    !local.has(name.toUpperCase()) && !/^GIT_CONFIG_(?:KEY|VALUE)_\d+$/i.test(name)));
}
export function parseUpdates(input) {
  return input.split(/\r?\n/).filter(Boolean).map(line => {
    const fields = line.trim().split(/\s+/);
    if (fields.length !== 4 || !oid.test(fields[1]) || !oid.test(fields[3]) || fields[1].length !== fields[3].length)
      throw new Error('Invalid pre-push ref record (expected four fields and 40/64 hex IDs).');
    return { local: fields[1], remote: fields[3] };
  }).filter(update => !zero.test(update.local));
}

export function runPreflight({ hook = false, input = '', checkOnly = false, platform = process.platform, exec = spawnSync, log = console.log, environment = process.env } = {}) {
  let childEnvironment = environment;
  let childRoot;
  const run = (command, args, options = {}) => {
    // Windows requires a command shell for npm.cmd; all npm arguments below are fixed.
    const result = exec(command, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, shell: platform === 'win32' && command === 'npm.cmd', env: command === 'git' ? environment : childEnvironment, ...(command === 'git' ? {} : { cwd: childRoot }), ...options });
    if (result.error || result.status !== 0) throw new Error(`${command} ${args[0] || ''} failed${result.error ? `: ${result.error.message}` : ` (exit ${result.status})`}. Install required tools or fix the reported check; nothing was skipped.`);
    return (result.stdout || '').trim();
  };
  const updates = hook ? parseUpdates(input) : [];
  if (hook && !updates.length) { log('No non-deletion refs to check.'); return; }
  if (hook && checkOnly) throw new Error('--check-only is not allowed in the pre-push hook.');
  const npm = platform === 'win32' ? 'npm.cmd' : 'npm';
  childRoot = run('git', ['rev-parse', '--show-toplevel']);
  const localNames = run('git', ['rev-parse', '--local-env-vars']).split(/\r?\n/).filter(Boolean);
  if (!localNames.length || localNames.some(name => !/^GIT_[A-Z0-9_]+$/.test(name))) throw new Error('Cannot identify Git local environment variables.');
  // Keep repository selectors for outgoing-ref checks, but never leak them into
  // tools/tests that create their own repositories or invoke Git internally.
  childEnvironment = withoutLocalGitEnvironment(environment, localNames);
  const version = run('gitleaks', ['version']);
  if (!/^v?8\./.test(version)) throw new Error('gitleaks version 8 is required.');
  run(npm, ['--version']);
  run('cargo', ['--version']);
  run('cargo', ['fmt', '--version']);
  run('cargo', ['clippy', '--version']);
  if (checkOnly) { log('Required tools available; no quality checks or full CodeQL analysis performed.'); return; }
  if (hook) {
    const head = run('git', ['rev-parse', 'HEAD']);
    for (const update of updates) {
      const commit = run('git', ['rev-parse', '--verify', `${update.local}^{commit}`]);
      if (commit !== head) throw new Error('Outgoing commit is not this worktree HEAD; test its own clean worktree before pushing.');
      if (!zero.test(update.remote)) run('git', ['cat-file', '-e', `${update.remote}^{commit}`]);
    }
    const dirty = [...run('git', ['diff', '--name-only', 'HEAD', '-z']).split('\0'), ...run('git', ['ls-files', '--others', '--exclude-standard', '-z']).split('\0')].filter(Boolean);
    if (dirty.some(path => !/\.md$/i.test(path))) throw new Error('Source/config worktree is dirty; refusing to test different content from the outgoing commit (only Markdown changes allowed).');
  }
  const redact = ['--redact=100', '--no-banner', '--no-color', '--ignore-gitleaks-allow'];
  if (hook) {
    for (const update of updates) {
      // A new remote ref has no trustworthy base: scan its entire reachable history.
      const range = zero.test(update.remote) ? update.local : `${update.remote}..${update.local}`;
      run('gitleaks', ['git', '.', '--log-opts', range, ...redact], { stdio: 'inherit' });
    }
  } else {
    run('gitleaks', ['git', '.', '--log-opts', '-1 HEAD', ...redact], { stdio: 'inherit' });
    const diff = run('git', ['diff', '--no-ext-diff', '--no-textconv', '--binary', 'HEAD', '--']);
    run('gitleaks', ['stdin', ...redact], { input: diff, stdio: ['pipe', 'inherit', 'inherit'] });
  }
  for (const [command, args] of [
    [process.execPath, ['scripts/check-test-credentials.mjs']],
    [npm, ['test']], [npm, ['run', 'build']],
    ['cargo', ['fmt', '--manifest-path', 'src-tauri/Cargo.toml', '--all', '--', '--check']],
    ['cargo', ['test', '--manifest-path', 'src-tauri/Cargo.toml', '--lib', '--locked', '-j', '2']],
    ['cargo', ['clippy', '--manifest-path', 'src-tauri/Cargo.toml', '--locked', '--all-targets', '-j', '2', '--', '-D', 'warnings']],
  ]) run(command, args, { stdio: 'inherit' });
  log('Local secret scan, Node tests/build and Rust checks passed. This is not a full CodeQL scan.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => !['--hook', '--check-only'].includes(arg))) throw new Error('Usage: security-preflight.mjs [--hook | --check-only]');
    runPreflight({ hook: args.includes('--hook'), checkOnly: args.includes('--check-only'), input: args.includes('--hook') ? readFileSync(0, 'utf8') : '' });
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
