import type { GlobalState } from '../types';
import { DappConnectState } from '../types';

import {
  clearDappConnectRequest,
  updateDappConnectRequest,
} from '../reducers';

export function resumeDappConnectAfterWalletCreation(global: GlobalState): {
  global: GlobalState;
  switchedAccountId?: string;
} {
  if (!global.dappConnectRequest?.isCreatingAccount) {
    return { global };
  }

  const { promiseId, pendingConnectAccountId } = global.dappConnectRequest;
  if (!promiseId) {
    return { global: clearDappConnectRequest(global) };
  }

  if (!pendingConnectAccountId || !global.accounts?.byId?.[pendingConnectAccountId]) {
    return { global };
  }

  return {
    global: updateDappConnectRequest(global, {
      accountId: pendingConnectAccountId,
      pendingConnectAccountId: undefined,
      isCreatingAccount: undefined,
      multichainResolution: undefined,
      state: DappConnectState.Info,
      error: undefined,
    }),
    switchedAccountId: pendingConnectAccountId,
  };
}
