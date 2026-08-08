import type { GlobalState } from '../types';
import { SwapState } from '../types';

import { DEFAULT_SLIPPAGE_VALUE } from '../../config';
import { replaceActivityId } from '../helpers/misc';
import {
  doesSwapChangeRequireEstimation,
  doesSwapChangeRequireEstimationReset,
  getSwapEstimateResetParams,
} from '../helpers/swap';

function rawUpdateCurrentSwap(global: GlobalState, update: Partial<GlobalState['currentSwap']>) {
  return {
    ...global,
    currentSwap: {
      ...global.currentSwap,
      ...update,
    },
  };
}

export function updateCurrentSwap(
  global: GlobalState,
  update: Partial<GlobalState['currentSwap']>,
  // Set to true if you want to not trigger the swap estimation, and you are sure estimation is not needed
  doAvoidEstimation?: boolean,
) {
  let newGlobal = rawUpdateCurrentSwap(global, update);

  if (!doAvoidEstimation) {
    if (doesSwapChangeRequireEstimationReset(global, newGlobal)) {
      newGlobal = rawUpdateCurrentSwap(newGlobal, getSwapEstimateResetParams(newGlobal));
    }

    if (doesSwapChangeRequireEstimation(global, newGlobal)) {
      newGlobal = rawUpdateCurrentSwap(newGlobal, { isEstimating: true });
    }
  }

  // Applying the update again because the input fields should have a higher priority than the above automatic updates
  return rawUpdateCurrentSwap(newGlobal, update);
}

export function clearCurrentSwap(global: GlobalState) {
  return {
    ...global,
    currentSwap: {
      state: SwapState.None,
      slippage: DEFAULT_SLIPPAGE_VALUE,
    },
  };
}

/** replaceMap: keys - old (removed) activity ids, value - new (added) activity ids */
export function replaceCurrentSwapId(global: GlobalState, replaceMap: Record<string, string>) {
  return updateCurrentSwap(global, {
    activityId: replaceActivityId(global.currentSwap.activityId, replaceMap),
  });
}
