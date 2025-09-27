import type { ApiChain } from '../../api/types';
import type { GlobalState } from '../types';

import { INITIAL_STATE } from '../initialState';

export function updateHardware(global: GlobalState, hardwareUpdate: Partial<GlobalState['hardware']>) {
  return {
    ...global,
    hardware: {
      ...global.hardware,
      ...hardwareUpdate,
    },
  };
}

export function resetHardware(global: GlobalState, chain: ApiChain, shouldLoadWallets = false) {
  return {
    ...global,
    hardware: {
      ...INITIAL_STATE.hardware,
      chain,
      shouldLoadWallets: shouldLoadWallets || undefined,
    },
  };
}
