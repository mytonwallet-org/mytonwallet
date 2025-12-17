import type { ApiAccountWithMnemonic, ApiAnyDisplayError, ApiNetwork, ApiTronWallet } from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { logDebugError } from '../../../util/logs';
import { getTronClient } from './util/tronweb';
import { fetchStoredAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { getMnemonic } from '../../common/mnemonic';
import { bytesToHex, hexToBytes } from '../../common/utils';
import { isValidAddress } from './address';

export async function fetchPrivateKeyString(accountId: string, password: string, account?: ApiAccountWithMnemonic) {
  try {
    account = account ?? await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);
    const mnemonic = await getMnemonic(accountId, password, account);
    if (!mnemonic) {
      return undefined;
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return mnemonic[0];
    } else {
      const { network } = parseAccountId(accountId);
      return getRawWalletFromBip39Mnemonic(network, mnemonic).privateKey.slice(2);
    }
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);

    return undefined;
  }
}

export function getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): ApiTronWallet {
  const { address, publicKey } = getRawWalletFromBip39Mnemonic(network, mnemonic);
  return {
    address,
    publicKey,
    index: 0,
  };
}

export function getWalletFromPrivateKey(
  network: ApiNetwork,
  privateKey: string,
): ApiTronWallet {
  const tronClient = getTronClient(network);
  const publicKey = tronClient.utils.crypto.getPubKeyFromPriKey(hexToBytes(privateKey));
  const address = tronClient.utils.crypto.computeAddress(publicKey);

  return {
    address: tronClient.utils.crypto.getBase58CheckAddress(address),
    publicKey: bytesToHex(publicKey),
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

function getRawWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]) {
  return getTronClient(network).fromMnemonic(mnemonic.join(' '));
}
