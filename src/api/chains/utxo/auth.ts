import { secp256k1 } from '@noble/curves/secp256k1';
import { HDKey } from '@scure/bip32';
import * as bip39 from 'bip39';

import type {
  ApiAccountWithMnemonic,
  ApiAnyDisplayError,
  ApiDerivation,
  ApiNetwork,
  ApiUTXOWallet,
  UTXOChain,
} from '../../types';
import { ApiCommonError } from '../../types';

import { parseAccountId } from '../../../util/account';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { fetchStoredAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { getMnemonic } from '../../common/mnemonic';
import { bytesToHex, hexToBytes } from '../../common/utils';
import { isValidAddress, normalizeAddress } from './address';
import {
  getDefaultUtxoAddressType,
  getDefaultUtxoDerivationPath,
  getUtxoImportPathTemplates,
  UTXO_ADDRESS_TYPES,
  type UtxoAddressType,
} from './constants';
import {
  createUtxoPayment,
  getAddressTypeFromPathTemplate,
} from './payment';
import { getWalletBalance, getWalletLastTransaction } from './wallet';

const MULTIWALLET_BY_PATH_DEFAULT_COUNT = 2;

type UtxoWalletRaw = {
  address: string;
  publicKey: string;
  privateKeyBytes: Uint8Array;
  path: string;
  label: UtxoAddressType;
  index: number;
};

function derivePath(pathTemplate: string, index: number) {
  return pathTemplate.replace('{index}', String(index));
}

function getWalletVariantForPath(
  chain: UTXOChain,
  network: ApiNetwork,
  mnemonic: string[],
  pathTemplate: string,
  index: number,
  label?: string,
): UtxoWalletRaw {
  const path = derivePath(pathTemplate, index);
  const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));
  const hd = HDKey.fromMasterSeed(seed);
  const child = hd.derive(path);

  if (!child.publicKey || !child.privateKey) {
    throw new Error('Failed to derive UTXO wallet');
  }

  const addressType = (label && UTXO_ADDRESS_TYPES.includes(label as UtxoAddressType)
    ? label
    : getAddressTypeFromPathTemplate(pathTemplate)) as UtxoAddressType;
  const payment = createUtxoPayment(chain, network, child.publicKey, child.privateKey, addressType);

  return {
    address: payment.address,
    publicKey: payment.publicKey,
    privateKeyBytes: payment.privateKeyBytes,
    path: pathTemplate,
    label: addressType,
    index,
  };
}

function toApiWallet(raw: UtxoWalletRaw): ApiUTXOWallet {
  return {
    address: raw.address,
    publicKey: raw.publicKey,
    index: 0,
    derivation: {
      path: raw.path,
      index: raw.index,
      label: raw.label,
    },
  };
}

function getWalletVariantsByPath(
  chain: UTXOChain,
  network: ApiNetwork,
  mnemonic: string[],
  count: number = MULTIWALLET_BY_PATH_DEFAULT_COUNT,
  offset: number = 0,
): UtxoWalletRaw[] {
  const pathTemplates = getUtxoImportPathTemplates(chain);

  return pathTemplates.flatMap(({ label, pathTemplate }) => {
    const acc: UtxoWalletRaw[] = [];

    for (let i = 0; i < count; i++) {
      const index = offset + i;

      acc.push(getWalletVariantForPath(chain, network, mnemonic, pathTemplate, index, label));
    }

    return acc;
  });
}

type UtxoImportCandidate<T> = T & {
  path: string;
  index: number;
  label: string;
  balance: bigint;
  lastTxBlock?: number;
};

function omitDiscoveryFields<T extends { path: string; index: number; label: string }>(
  variant: UtxoImportCandidate<T>,
): T {
  const { balance: _balance, lastTxBlock: _lastTxBlock, ...raw } = variant;
  return raw as T;
}

async function pickBestWallets(
  chain: UTXOChain,
  network: ApiNetwork,
  mnemonic: string[],
  shouldSkipDiscovery?: boolean,
): Promise<UtxoWalletRaw[]> {
  const defaultPath = getDefaultUtxoDerivationPath(chain);
  const variants = getWalletVariantsByPath(chain, network, mnemonic);
  const defaultWallet = variants.find((v) => v.path === defaultPath && v.index === 0);

  if (!defaultWallet) {
    throw new Error('UTXO: no wallet variants');
  }

  if (shouldSkipDiscovery) {
    return [defaultWallet];
  }

  try {
    const withBalances = await Promise.all(
      variants.map(async (v) => ({
        ...v,
        balance: await getWalletBalance(chain, network, v.address),
      })),
    );

    const withPositive = withBalances.filter((v) => v.balance > 0n);

    if (withPositive.length > 0) {
      return withPositive.map(omitDiscoveryFields);
    }

    await pause(500);

    const withLastTx = await Promise.all(
      variants.map(async (v) => ({
        ...v,
        balance: 0n,
        lastTxBlock: (await getWalletLastTransaction(chain, network, v.address))?.blockTime,
      })),
    );

    const withActivity = withLastTx.filter((v) => v.lastTxBlock !== undefined);

    if (withActivity.length > 0) {
      return withActivity.map(omitDiscoveryFields);
    }
  } catch (err) {
    logDebugError(`utxo:${chain}:pickBestWallets`, err);
  }

  return [defaultWallet];
}

function getRawWalletFromBip39Mnemonic(
  chain: UTXOChain,
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
) {
  const pathTemplate = derivation?.path ?? getDefaultUtxoDerivationPath(chain);
  const index = derivation?.index ?? 0;

  return getWalletVariantForPath(chain, network, mnemonic, pathTemplate, index, derivation?.label);
}

export async function fetchPrivateKeyString(
  chain: UTXOChain,
  accountId: string,
  enclaveToken: string,
  account?: ApiAccountWithMnemonic,
) {
  try {
    account = account ?? await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);
    const mnemonic = await getMnemonic(accountId, enclaveToken);

    if (!mnemonic) {
      return undefined;
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return mnemonic[0];
    }

    const { network } = parseAccountId(accountId);
    const derivation = account.byChain[chain]?.derivation;
    const raw = getRawWalletFromBip39Mnemonic(chain, network, mnemonic, derivation);

    return bytesToHex(raw.privateKeyBytes);
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);

    return undefined;
  }
}

export async function getWalletFromBip39Mnemonic(
  chain: UTXOChain,
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
  shouldSkipDiscovery?: boolean,
): Promise<ApiUTXOWallet[]> {
  if (derivation) {
    return [toApiWallet(getRawWalletFromBip39Mnemonic(chain, network, mnemonic, derivation))];
  }

  const raws = await pickBestWallets(chain, network, mnemonic, shouldSkipDiscovery);

  return raws.map(toApiWallet);
}

export function getWalletFromPrivateKey(
  chain: UTXOChain,
  network: ApiNetwork,
  privateKey: string,
): ApiUTXOWallet {
  const privateKeyBytes = hexToBytes(privateKey.replace(/^0x/i, ''));
  const publicKey = secp256k1.getPublicKey(privateKeyBytes, true);
  const defaultAddressType = getDefaultUtxoAddressType(chain);
  const derivationPaths = getUtxoImportPathTemplates(chain).filter((p) => p.label === defaultAddressType);
  const payment = createUtxoPayment(chain, network, publicKey, privateKeyBytes, defaultAddressType);

  return {
    address: payment.address,
    publicKey: payment.publicKey,
    index: 0,
    derivation: {
      path: derivationPaths[0]?.pathTemplate ?? getDefaultUtxoDerivationPath(chain),
      index: 0,
      label: defaultAddressType,
    },
  };
}

export function getWalletFromAddress(
  chain: UTXOChain,
  network: ApiNetwork,
  addressOrDomain: string,
): { title?: string; wallet: ApiUTXOWallet } | { error: ApiAnyDisplayError } {
  if (!isValidAddress(chain, network, addressOrDomain)) {
    return { error: ApiCommonError.InvalidAddress };
  }

  return {
    title: getKnownAddressInfo(addressOrDomain)?.name,
    wallet: {
      address: normalizeAddress(chain, addressOrDomain, network),
      index: 0,
    },
  };
}

export function getSignerFromPrivateKey(_network: ApiNetwork, privateKeyHex: string) {
  return hexToBytes(privateKeyHex.replace(/^0x/i, ''));
}
