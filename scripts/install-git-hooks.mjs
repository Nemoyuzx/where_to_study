import { spawnSync } from 'node:child_process';
import * as nativeFs from 'node:fs';
import { resolve, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const OWNED_HOOK_MARKER = '#!/bin/sh\n# WTS-OWNED-PRE-PUSH-v1\n';
export function installHooks({ exec = spawnSync, fs = nativeFs } = {}) {
  const git = args => {
    const result = exec('git', args, { encoding: 'utf8' });
    if (result.error || (result.status !== 0 && !(args[0] === 'config' && args[1] === '--get' && result.status === 1))) throw new Error('Cannot inspect/configure this local Git repository.');
    return (result.stdout || '').trim();
  };
  const root = git(['rev-parse', '--show-toplevel']);
  const common = fs.realpathSync(resolve(root, git(['rev-parse', '--git-common-dir'])));
  const directory = join(common, 'wts-hooks');
  const target = join(directory, 'pre-push');
  const hooks = git(['config', '--get', 'core.hooksPath']);
  if (hooks && hooks !== 'scripts/git-hooks' && hooks !== directory) throw new Error('Existing core.hooksPath is not ours; refusing to overwrite it.');
  // --git-path hooks follows core.hooksPath; inspect the actual default directly.
  const defaultHooks = join(common, 'hooks');
  if (fs.existsSync(defaultHooks) && fs.readdirSync(defaultHooks).some(name => !name.endsWith('.sample')))
    throw new Error('Existing non-sample Git hooks; refusing to disable them by changing core.hooksPath.');
  const sourceDirectory = resolve(root, 'scripts/git-hooks');
  if (hooks === 'scripts/git-hooks' && fs.readdirSync(sourceDirectory).some(name => name !== 'pre-push' && !name.endsWith('.sample')))
    throw new Error('Existing additional hooks in migration source; refusing to hide them.');
  if (fs.existsSync(directory)) {
    if (fs.lstatSync(directory).isSymbolicLink() || !fs.lstatSync(directory).isDirectory() || fs.realpathSync(directory) !== directory ||
        fs.readdirSync(directory).some(name => name !== 'pre-push') || !fs.existsSync(target) ||
        fs.lstatSync(target).isSymbolicLink() || !fs.lstatSync(target).isFile() ||
        !fs.readFileSync(target, 'utf8').startsWith(OWNED_HOOK_MARKER))
      throw new Error('Existing wts-hooks directory/hook is not ours; refusing to overwrite it.');
  }
  const source = fs.readFileSync(join(sourceDirectory, 'pre-push'), 'utf8');
  if (!source.startsWith(OWNED_HOOK_MARKER)) throw new Error('Reviewed hook ownership marker is missing.');
  let created = false;
  let temporary;
  let ownsTemporary = false;
  try {
    if (!fs.existsSync(directory)) { fs.mkdirSync(directory); created = true; }
    // Fixed destination under this repository's canonical Git common directory.
    if (fs.realpathSync(directory) !== directory) throw new Error('Unsafe local hook destination.');
    temporary = join(directory, `.pre-push-${randomUUID()}.tmp`);
    const descriptor = fs.openSync(temporary, 'wx', 0o755);
    ownsTemporary = true;
    try { fs.writeFileSync(descriptor, source); } finally { fs.closeSync(descriptor); }
    fs.chmodSync(temporary, 0o755);
    fs.renameSync(temporary, target);
    temporary = undefined;
    // Configure only after the executable hook has been atomically installed.
    git(['config', '--local', 'core.hooksPath', directory]);
  } finally {
    if (ownsTemporary && temporary && fs.existsSync(temporary)) fs.unlinkSync(temporary);
    if (created && fs.existsSync(directory) && fs.readdirSync(directory).length === 0) fs.rmdirSync(directory);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { installHooks(); console.log('Local pre-push hook enabled for this repository only.'); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
