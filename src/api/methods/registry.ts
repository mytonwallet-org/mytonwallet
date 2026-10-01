import type { Methods } from './types';

import * as agentV2Methods from './agentV2';
import * as extraMethods from './extra';
import * as commonMethods from '.';

/**
 * The dispatch table every provider indexes by method name.
 *
 * The optional halves are kept out of `methods/index`. The connector dispatches with `methods[fnName]`, and a
 * dynamic lookup on a namespace pins every export in it, so nothing re-exported from `methods/index` can be
 * tree-shaken.
 */
export const methods = { ...commonMethods } as Methods;

// In a `NO_EXTRA_FEATURES` build `plugins/disabledImports.ts` replaces `./extra` and `./agentV2` with stubs, so
// nothing they pull is bundled. `process.env` is read inline rather than through `config` to make this branch
// statically false there. If the branch survived, the stubs would reach the bundle and the build would fail.
if (process.env.NO_EXTRA_FEATURES !== '1') {
  Object.assign(methods, extraMethods, agentV2Methods);
}
