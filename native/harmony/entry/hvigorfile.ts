import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { HvigorNode } from '@ohos/hvigor';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

// Public build assets only. Run during SDK configuration so IDE and CLI agree,
// before resource inputs are discovered; unchanged bytes preserve their mtimes.
const legalAssets = {
  pluginId: 'where-to-study-public-legal-assets',
  apply(node: HvigorNode) {
    const moduleDirectory = node.getNodeDir().getPath();
    const script = path.resolve(moduleDirectory, '../../../scripts/sync-harmony-legal-assets.mjs');
    execFileSync(process.execPath, [script], { stdio: 'inherit' });
  },
};

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [legalAssets]
}
