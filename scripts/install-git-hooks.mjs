import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, chmodSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function installHooks({ exec = spawnSync, exists = existsSync, readdir = readdirSync, chmod = chmodSync } = {}) {
  const git = args => {
    const result = exec('git', args, { encoding: 'utf8' });
    if (result.error || (result.status !== 0 && !(args[0] === 'config' && args[1] === '--get' && result.status === 1))) throw new Error('Cannot inspect/configure this local Git repository.');
    return (result.stdout || '').trim();
  };
  const root = git(['rev-parse', '--show-toplevel']);
  const hooks = git(['config', '--get', 'core.hooksPath']);
  if (hooks && hooks !== 'scripts/git-hooks') throw new Error('Existing core.hooksPath is not ours; refusing to overwrite it.');
  if (!hooks) {
    const defaultHooks = git(['rev-parse', '--git-path', 'hooks']);
    // Changing hooksPath would disable every default hook, not just pre-push.
    // Conservatively reject any non-sample entry, including directories/symlinks.
    if (exists(defaultHooks) && readdir(defaultHooks).some(name => !name.endsWith('.sample')))
      throw new Error('Existing non-sample Git hooks; refusing to disable them by changing core.hooksPath.');
  }
  chmod(resolve(root, 'scripts/git-hooks/pre-push'), 0o755);
  git(['config', '--local', 'core.hooksPath', 'scripts/git-hooks']);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { installHooks(); console.log('Local pre-push hook enabled for this repository only.'); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
