import type { ApiAnyDisplayError, ApiNetwork, ApiTronWallet } from '../../types';
import { ApiCommonError } from '../../types';

import { getTronClient } from './util/tronweb';
import { getKnownAddressInfo } from '../../common/addresses';
import { isValidAddress } from './address';

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
): { title?: string; wallet: ApiTronWallet } | { error: ApiAnyDisplayError } {
  if (!isValidAddress(network, addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    title: getKnownAddressInfo(addressOrDomain)?.name,
    wallet: {
      address: addressOrDomain,
      index: 0,
    },
  };
}
