import * as tonWebMnemonic from 'tonweb-mnemonic';
import * as bip39 from 'bip39';
import nacl from 'tweetnacl';

import type {
  ApiDerivation } from '../../types';
import type { ApiTonWalletVersion } from './types';
import {
  type ApiAccountWithMnemonic,
  type ApiAnyDisplayError,
  type ApiNetwork,
  type ApiTonWallet,
} from '../../types';

import { DEFAULT_WALLET_VERSION } from '../../../config';
import * as HDKey from '../../../lib/ed25519-hd-key';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { extractKey, omitUndefined } from '../../../util/iteratees';
import { logDebugError } from '../../../util/logs';
import { getWalletPublicKey, toBase64Address } from './util/tonCore';
import { fetchStoredAccount } from '../../common/accounts';
import { getMnemonic } from '../../common/mnemonic';
import { bytesToHex, hexToBytes } from '../../common/utils';
import { resolveAddress } from './address';
import { TON_BIP39_PATH } from './constants';
import { getWalletInfos } from './toncenter';
import { getWalletInfo, pickBestWallet, pickBestWalletVersion, publicKeyToAddress } from './wallet';

const MULTIWALLET_BY_PATH_DEFAULT_COUNT = 2;

export function generateMnemonic() {
  return tonWebMnemonic.generateMnemonic();
}

export function validateMnemonic(mnemonic: string[]) {
  return tonWebMnemonic.validateMnemonic(mnemonic);
}

export function privateKeyHexToKeyPair(privateKeyHex: string) {
  return nacl.sign.keyPair.fromSeed(hexToBytes(privateKeyHex));
}

export async function fetchPrivateKeyString(accountId: string, password: string, account?: ApiAccountWithMnemonic) {
  const privateKey = await fetchPrivateKey(accountId, password, account);
  return privateKey && bytesToHex(privateKey);
}

export async function fetchPrivateKey(accountId: string, password: string, account?: ApiAccountWithMnemonic) {
  try {
    const { secretKey: privateKey } = await fetchKeyPair(accountId, password, account) || {};

    return privateKey;
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(err);

    return undefined;
  }
}

export async function fetchKeyPair(accountId: string, password: string, account?: ApiAccountWithMnemonic) {
  try {
    account = account ?? await fetchStoredAccount<ApiAccountWithMnemonic>(accountId);
    const mnemonic = await getMnemonic(accountId, password, account);
    if (!mnemonic) {
      return undefined;
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return privateKeyHexToKeyPair(mnemonic[0]);
    } else if (account.type === 'bip39') {
      const derivation = account.byChain.ton?.derivation;

      if (!derivation) {
        throw new Error(`No TON derivation found for account ${accountId}`);
      }

      const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));

      const keypair = getWalletVariantByIndex(seed.toString('hex'), derivation.index);

      if (!keypair) {
        throw new Error(`No TON keypair found for derivation ${derivation.index} on account ${accountId}`);
      }

      return keypair;
    } else {
      return await tonWebMnemonic.mnemonicToKeyPair(mnemonic);
    }
  } catch (err) {
    logDebugError('fetchKeyPair', err);

    return undefined;
  }
}

export async function rawSign(accountId: string, password: string, dataHex: string) {
  const privateKey = await fetchPrivateKey(accountId, password);
  if (!privateKey) {
    return undefined;
  }

  const signature = nacl.sign.detached(hexToBytes(dataHex), privateKey);

  return bytesToHex(signature);
}

export async function getWalletFromBip39Mnemonic(
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
): Promise<ApiTonWallet[]> {
  if (derivation) {
    const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));
    const keypair = getWalletVariantByIndex(seed.toString('hex'), derivation.index, derivation.path);
    const { wallet, version } = await pickBestWalletVersion(network, keypair.publicKey);
    return [{
      address: toBase64Address(wallet.address, false, network),
      publicKey: bytesToHex(wallet.publicKey),
      version,
      index: 0,
      derivation: { path: derivation.path, index: derivation.index },
    }];
  }

  const variants = bip39MnemonicToKeyPairs(mnemonic);

  const walletResults = await Promise.all(
    variants.map(async ({ publicKey, derivation: variantDerivation }) => {
      const { wallet, version, balance } = await pickBestWalletVersion(network, publicKey);

      return {
        address: toBase64Address(wallet.address, false, network),
        publicKey: bytesToHex(wallet.publicKey),
        version,
        index: 0,
        derivation: variantDerivation,
        balance,
      };
    }),
  );

  const withBalances = walletResults.filter((w) => w.balance > 0n);

  const results = withBalances.length > 0
    ? withBalances
    : [walletResults.find(({ derivation: d }) => d?.index === 0) ?? walletResults[0]];

  return results.map(({ balance: _balance, ...wallet }) => wallet);
}

export async function getWalletFromMnemonic(
  network: ApiNetwork,
  mnemonic: string[],
): Promise<ApiTonWallet & { lastTxId?: string }> {
  const { publicKey } = await tonWebMnemonic.mnemonicToKeyPair(mnemonic);
  return getWalletFromKeys(
    network,
    [{ publicKey }],
  );
}

export async function getWalletFromPrivateKey(
  network: ApiNetwork,
  privateKey: string,
): Promise<ApiTonWallet> {
  const { publicKey } = privateKeyHexToKeyPair(privateKey);
  return getWalletFromKeys(
    network,
    [{ publicKey }],
  );
}

async function getWalletFromKeys(
  network: ApiNetwork,
  variants: { publicKey: Uint8Array; derivation?: { path: string; index: number } }[],
): Promise<(ApiTonWallet & { lastTxId?: string })> {
  const { wallet, version, lastTxId, derivation } = await pickBestWallet(network, variants);

  const address = toBase64Address(wallet.address, false, network);
  const publicKeyHex = bytesToHex(wallet.publicKey);

  return {
    publicKey: publicKeyHex,
    address,
    version,
    index: 0,
    lastTxId,
    derivation,
  };
}

export function getWalletVariantsByPath(
  seed: string,
  count: number = MULTIWALLET_BY_PATH_DEFAULT_COUNT,
  offset: number = 0,
) {
  const keypairs: { publicKey: Uint8Array; secretKey: Uint8Array; path: string; index: number }[] = [];

  for (let i = 0; i < count; i++) {
    const index = offset + i;
    const path = TON_BIP39_PATH.replace('{index}', index.toString());
    const { key: privateKey } = HDKey.derivePath(path, seed);
    const keypair = nacl.sign.keyPair.fromSeed(privateKey);

    keypairs.push({ ...keypair, path: TON_BIP39_PATH, index });
  };

  return keypairs;
}

function getWalletVariantByIndex(seed: string, index: number, pathTemplate: string = TON_BIP39_PATH) {
  const path = pathTemplate.replace('{index}', index.toString());
  const { key: privateKey } = HDKey.derivePath(path, seed);
  const keypair = nacl.sign.keyPair.fromSeed(privateKey);

  return { ...keypair, path: pathTemplate, index };
}

function bip39MnemonicToKeyPairs(mnemonic: string[]) {
  const hexSeed = bip39.mnemonicToSeedSync(mnemonic.join(' '));

  const variants = getWalletVariantsByPath(hexSeed.toString('hex'));
  return variants.map((e) => ({
    publicKey: e.publicKey,
    secretKey: e.secretKey,
    derivation: { path: e.path, index: e.index },
  }));
}

export function getOtherVersionWallet(
  network: ApiNetwork,
  wallet: ApiTonWallet,
  otherVersion: ApiTonWalletVersion,
  isTestnetSubwalletId?: boolean,
): ApiTonWallet {
  if (!wallet.publicKey) {
    throw new Error('The wallet has no public key');
  }

  const publicKey = hexToBytes(wallet.publicKey);
  const newAddress = publicKeyToAddress(network, publicKey, otherVersion, isTestnetSubwalletId);

  return {
    address: newAddress,
    publicKey: wallet.publicKey,
    version: otherVersion,
    index: wallet.index,
    derivation: wallet.derivation,
  };
}

// Used for View-account flow
export async function getWalletFromAddress(
  network: ApiNetwork,
  addressOrDomain: string,
): Promise<{ title?: string; wallet: ApiTonWallet } | { error: ApiAnyDisplayError }> {
  const resolvedAddress = await resolveAddress(network, addressOrDomain, true);
  if ('error' in resolvedAddress) return resolvedAddress;
  const rawAddress = resolvedAddress.address;

  const [walletInfo, publicKey] = await Promise.all([
    getWalletInfo(network, rawAddress),
    getWalletPublicKey(network, rawAddress),
  ]);

  return {
    title: resolvedAddress.name,
    wallet: omitUndefined<ApiTonWallet>({
      publicKey: publicKey ? bytesToHex(publicKey) : undefined,
      address: walletInfo.address,
      // The wallet has no version until it's initialized as a wallet. Using the default version just for the type
      // compliance, it plays no role for view wallets anyway.
      version: walletInfo?.version ?? DEFAULT_WALLET_VERSION,
      index: 0,
      isInitialized: walletInfo?.isInitialized ?? false,
    }),
  };
}

export async function getWalletsFromLedgerAndLoadBalance(
  network: ApiNetwork,
  accountIndices: number[],
): Promise<{ wallet: ApiTonWallet; balance: bigint }[] | { error: ApiAnyDisplayError }> {
  const { getLedgerTonWallet } = await import('./ledger');
  const wallets: ApiTonWallet[] = [];

  // Load the wallets from Ledger
  for (const accountIndex of accountIndices) {
    const wallet = await getLedgerTonWallet(network, accountIndex);
    if ('error' in wallet) return { error: wallet.error };
    wallets.push(wallet);
  }

  // Fetch the wallets' balances
  const walletInfos = await getWalletInfos(network, extractKey(wallets, 'address'));

  return wallets.map((wallet) => ({
    wallet,
    balance: walletInfos[wallet.address].balance,
  }));
}
