import type { ApiNetwork, ApiTronWallet } from '../../types';
import { ApiAuthError } from '../../types';

import { getChainConfig } from '../../../util/chain';
import { getTronClient } from './util/tronweb';

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
    return { error: ApiAuthError.InvalidAddress };
  }

  return {
    wallet: {
      address: addressOrDomain,
      index: 0,
    },
  };
}
