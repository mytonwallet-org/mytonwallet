import type { ApiAccountWithMnemonic, ApiAnyDisplayError, ApiDerivation, ApiNetwork, ApiTronWallet } from '../../types';
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
import { TRON_BIP39_PATH } from './constants';

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
      const derivation = account.byChain.tron?.derivation;
      const raw = getRawWalletFromBip39Mnemonic(network, mnemonic, derivation);

      return raw.privateKey.replace(/^0x/i, '');
    }
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);

    return undefined;
  }
}

export function getWalletFromBip39Mnemonic(
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
): ApiTronWallet[] {
  const raw = getRawWalletFromBip39Mnemonic(network, mnemonic, derivation);

  const pathTemplate = derivation?.path ?? TRON_BIP39_PATH;
  const index = derivation?.index ?? 0;

  const publicKey = raw.publicKey.replace(/^0x/i, '');

  return [{
    address: raw.address,
    publicKey,
    index: 0,
    derivation: {
      path: pathTemplate,
      index,
      ...(derivation?.label !== undefined && { label: derivation.label }),
    },
  }];
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

function buildResolvedTronPath(derivation?: ApiDerivation) {
  const pathTemplate = derivation?.path ?? TRON_BIP39_PATH;
  const index = derivation?.index ?? 0;

  return pathTemplate.replace('{index}', String(index));
}

function getRawWalletFromBip39Mnemonic(
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
) {
  return getTronClient(network).fromMnemonic(mnemonic.join(' '), buildResolvedTronPath(derivation));
}
