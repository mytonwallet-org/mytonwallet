import type { GlobalState } from '../types';
import { WalletConnectPayState } from '../types';

export function updateCurrentWalletConnectPay(
  global: GlobalState,
  update: Partial<GlobalState['currentWalletConnectPay']>,
): GlobalState {
  return {
    ...global,
    currentWalletConnectPay: {
      ...global.currentWalletConnectPay,
      ...update,
    },
  };
}

export function clearCurrentWalletConnectPay(global: GlobalState): GlobalState {
  return {
    ...global,
    currentWalletConnectPay: {
      state: WalletConnectPayState.None,
    },
  };
}

export function updateWalletConnectPayDataCollection(
  global: GlobalState,
  update: Partial<NonNullable<GlobalState['walletConnectPayDataCollection']>>,
): GlobalState {
  if (!global.walletConnectPayDataCollection) {
    return global;
  }

  return {
    ...global,
    walletConnectPayDataCollection: {
      ...global.walletConnectPayDataCollection,
      ...update,
    },
  };
}

export function clearWalletConnectPayDataCollection(global: GlobalState): GlobalState {
  return {
    ...global,
    walletConnectPayDataCollection: undefined,
  };
}

export function clearWalletConnectPayOptionSelection(global: GlobalState): GlobalState {
  return {
    ...global,
    walletConnectPayOptionSelection: undefined,
  };
}
