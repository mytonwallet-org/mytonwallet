import type { ApiNetwork, ApiTronWallet } from '../../types';

import { getTronClient } from './util/tronweb';

export { setupActivePolling, setupInactivePolling } from './polling';
export { checkTransactionDraft, submitTransfer } from './transfer';
export { getWalletBalance, isTronAccountMultisig } from './wallet';
export { getAllTransactionSlice, getTokenTransactionSlice } from './transactions';

export function getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): ApiTronWallet {
  const { address, publicKey } = getTronClient(network).fromMnemonic(mnemonic.join(' '));
  return {
    type: 'tron',
    address,
    publicKey,
    index: 0,
  };
}

export function checkApiAvailability(network: ApiNetwork) {
  const isConnected = getTronClient(network).isConnected();
  return Boolean(isConnected);
}
