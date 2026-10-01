/**
 * Accessors for the optional half of the API, used by the code that stays in a `NO_EXTRA_FEATURES` build
 * but can still reach into it.
 *
 * In such a build `plugins/disabledImports.ts` replaces every namespace below with a stub, which keeps the modules
 * and their dependencies out of the bundle. `process.env` is read inline rather than through `config`, so the
 * branches are statically false there and the stubs are never reached. Every caller sits behind a condition that is
 * unreachable in such a build, and the throw makes it obvious if one ever is not.
 */

import * as agentV2Lifecycle from './agentV2Lifecycle';
import * as mfaMethods from './mfa';
import * as stakingMethods from './staking';
import * as swapMethods from './swap';

export function requireMfaMethods() {
  if (process.env.NO_EXTRA_FEATURES !== '1') {
    return mfaMethods;
  }

  throw new Error('MFA is not supported in this build');
}

export function requireSwapMethods() {
  if (process.env.NO_EXTRA_FEATURES !== '1') {
    return swapMethods;
  }

  throw new Error('Swap is not supported in this build');
}

export function requireStakingMethods() {
  if (process.env.NO_EXTRA_FEATURES !== '1') {
    return stakingMethods;
  }

  throw new Error('Staking is not supported in this build');
}

export function requireAgentV2Lifecycle() {
  if (process.env.NO_EXTRA_FEATURES !== '1') {
    return agentV2Lifecycle;
  }

  throw new Error('Agent V2 is not supported in this build');
}
