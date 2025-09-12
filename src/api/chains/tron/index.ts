import type { ApiNetwork, ApiTronWallet } from '../../types';
import { ApiAuthError } from '../../types';

import { getChainConfig } from '../../../util/chain';
import { getTronClient } from './util/tronweb';

export { setupActivePolling, setupInactivePolling } from './polling';
export { checkTransactionDraft, submitTransfer } from './transfer';
export { getWalletBalance, isTronAccountMultisig } from './wallet';
export { decryptComment, fetchActivityDetails, fetchActivitySlice } from './activities';

export function getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): ApiTronWallet {
  const { address, publicKey } = getTronClient(network).fromMnemonic(mnemonic.join(' '));
  return {
    address,
    publicKey,
    index: 0,
  };
}

export function getWalletFromAddress(
  network: ApiNetwork,
  addressOrDomain: string,
): { title?: string; wallet: ApiTronWallet } | { error: ApiAuthError } {
  const { addressRegex } = getChainConfig('tron');

  if (!addressRegex.test(addressOrDomain)) {
    return { error: ApiAuthError.DomainNotResolved };
  }

  return {
    wallet: {
      address: addressOrDomain,
      index: 0,
    },
  };
}

export function checkApiAvailability(network: ApiNetwork) {
  const isConnected = getTronClient(network).isConnected();
  return Boolean(isConnected);
}
