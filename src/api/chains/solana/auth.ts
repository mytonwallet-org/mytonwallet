import type {
  MessagePartialSignerConfig,
  SignableMessage,
  Transaction,
  TransactionPartialSignerConfig,
  TransactionWithinSizeLimit,
  TransactionWithLifetime,
} from '@solana/kit';
import { getAddressDecoder } from '@solana/kit';
import * as bip39 from 'bip39';
import nacl from 'tweetnacl';

import type {
  ApiAccountWithMnemonic,
  ApiAnyDisplayError,
  ApiDerivation,
  ApiNetwork,
  ApiSolanaWallet,
} from '../../types';
import type { SolanaKeyPairSigner } from './types';
import { ApiCommonError } from '../../types';

import * as HDKey from '../../../lib/ed25519-hd-key';
import { parseAccountId } from '../../../util/account';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { logDebugError } from '../../../util/logs';
import { pause } from '../../../util/schedulers';
import { fetchStoredAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { getMnemonic } from '../../common/mnemonic';
import { bytesToHex } from '../../common/utils';
import { isValidAddress } from './address';
import { SOLANA_DERIVATION_PATHS } from './constants';
import { getWalletBalance, getWalletLastTransaction } from './wallet';

const MULTIWALLET_BY_PATH_DEFAULT_COUNT = 2;

// Mimic @solana/kit signer w/o Web Crypto API
function createNaclKeyPairSigner(privateKeyBytes: Uint8Array): SolanaKeyPairSigner {
  const naclKeyPair = nacl.sign.keyPair.fromSeed(privateKeyBytes);
  const address = getAddressDecoder().decode(naclKeyPair.publicKey);
  const { secretKey, publicKey: publicKeyBytes } = naclKeyPair;

  return Object.freeze({
    address,
    publicKeyBytes,
    secretKey,
    signMessages(messages: readonly SignableMessage[], config?: MessagePartialSignerConfig) {
      return Promise.resolve(
        messages.map((message) => Object.freeze({
          [address]: nacl.sign.detached(message.content, secretKey) as any,
        })),
      );
    },
    signTransactions(transactions: readonly (Transaction
      & TransactionWithinSizeLimit & TransactionWithLifetime)[], config?: TransactionPartialSignerConfig) {
      return Promise.resolve(
        transactions.map((transaction) => Object.freeze({
          [address]: nacl.sign.detached(transaction.messageBytes as any, secretKey) as any,
        })),
      );
    },
  });
}

export async function fetchPrivateKeyString(accountId: string, password: string, account?: ApiAccountWithMnemonic) {
  try {
    account = account ?? (await fetchStoredAccount<ApiAccountWithMnemonic>(accountId));
    const mnemonic = await getMnemonic(accountId, password, account);
    if (!mnemonic) {
      return undefined;
    }

    if (isMnemonicPrivateKey(mnemonic)) {
      return mnemonic[0];
    } else {
      const { network } = parseAccountId(accountId);

      const derivation = account.byChain.solana?.derivation;

      // If derivation is provided, its always returns array with one element
      const privateKey = (await getRawWalletFromBip39Mnemonic(network, mnemonic, derivation))[0].privateKeyBytes;

      return bytesToHex(privateKey);
    }
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);

    return undefined;
  }
}

export async function getWalletFromBip39Mnemonic(
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
  isMigration?: boolean,
): Promise<ApiSolanaWallet[]> {
  const rawWallets = await getRawWalletFromBip39Mnemonic(network, mnemonic, derivation, isMigration);

  return rawWallets.map((raw) => ({
    address: raw.wallet.address,
    publicKey: bytesToHex(raw.wallet.publicKeyBytes),
    index: 0,
    derivation: { path: raw.path, index: raw.index, label: raw.label },
  }));
}

export function getWalletFromPrivateKey(network: ApiNetwork, privateKey: string): ApiSolanaWallet {
  const privateKeyBytes = Uint8Array.from(Buffer.from(privateKey, 'hex'));
  const signer = createNaclKeyPairSigner(privateKeyBytes);

  return {
    address: signer.address,
    publicKey: bytesToHex(signer.publicKeyBytes),
    index: 0,
  };
}

export function getSignerFromPrivateKey(network: ApiNetwork, privateKey: string): SolanaKeyPairSigner {
  const privateKeyBytes = Uint8Array.from(Buffer.from(privateKey, 'hex'));

  return createNaclKeyPairSigner(privateKeyBytes);
}

export function getWalletFromAddress(
  network: ApiNetwork,
  addressOrDomain: string,
): { title?: string; wallet: ApiSolanaWallet } | { error: ApiAnyDisplayError } {
  if (!isValidAddress(addressOrDomain)) {
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

async function getRawWalletFromBip39Mnemonic(
  network: ApiNetwork,
  mnemonic: string[],
  derivation?: ApiDerivation,
  isMigration?: boolean,
) {
  const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));

  if (derivation) {
    const wallet = getWalletVariantByIndex(seed.toString('hex'), derivation.path, derivation.index);
    return [{ ...wallet, label: derivation.label }];
  } else {
    const bestWallets = await pickBestWallets(network, seed.toString('hex'), isMigration);
    return bestWallets;
  }
}

function getWalletVariantByIndex(seed: string, path: string, index: number) {
  const seedByCustomPath = HDKey.derivePath(path.replace('{index}', index.toString()), seed).key;

  const derivedKeypair = nacl.sign.keyPair.fromSeed(seedByCustomPath);
  const privateKeyBytes = derivedKeypair.secretKey.subarray(0, 32);

  const wallet = createNaclKeyPairSigner(new Uint8Array(privateKeyBytes));
  return {
    wallet,
    privateKeyBytes,
    path,
    index,
  };
}

function getWalletVariantsByPath(
  seed: string,
  count: number = MULTIWALLET_BY_PATH_DEFAULT_COUNT,
  offset: number = 0,
) {
  const addresses = Object.entries(SOLANA_DERIVATION_PATHS).flatMap((e) => {
    const acc: {
      wallet: SolanaKeyPairSigner;
      privateKeyBytes: Uint8Array;
      path: string;
      label?: string;
      index: number;
    }[] = [];

    for (let i = 0; i < (e[0] === 'default' ? 1 : count); i++) {
      const index = offset + i;
      const path = e[1].replace('{index}', index.toString());
      const seedByCustomPath = HDKey.derivePath(path, seed).key;

      const derivedKeypair = nacl.sign.keyPair.fromSeed(seedByCustomPath);
      const privateKeyBytes = derivedKeypair.secretKey.subarray(0, 32);

      const wallet = createNaclKeyPairSigner(new Uint8Array(privateKeyBytes));

      acc.push({
        wallet,
        privateKeyBytes,
        path: e[1],
        label: e[0],
        index,
      });
    }

    return acc;
  });

  return addresses;
}

export async function pickBestWallets(
  network: ApiNetwork,
  seed: string,
  isMigration?: boolean,
) {
  const addresses = getWalletVariantsByPath(seed);

  const defaultAddress = addresses.find((e) => e.path === SOLANA_DERIVATION_PATHS.phantom)!;

  if (isMigration) {
    return [defaultAddress];
  }

  const addressBalances = await Promise.all(addresses.map(async (e) => ({
    wallet: e.wallet,
    balance: await getWalletBalance(network, e.wallet.address),
    privateKeyBytes: e.privateKeyBytes,
    path: e.path,
    index: e.index,
    label: e.label,
  })));

  const withBalances = addressBalances.filter((e) => e.balance > 0n);

  if (withBalances.length > 0) {
    return withBalances;
  }

  // TODO: rm after API plan upgrade from 10rps, but now wait to avoid 429 error
  await pause(500);

  const addressLastTxs = await Promise.all(addresses.map(async (e) => ({
    wallet: e.wallet,
    lastTxTimestamp: (await getWalletLastTransaction(network, e.wallet.address))?.blockTime,
    privateKeyBytes: e.privateKeyBytes,
    path: e.path,
    index: e.index,
    label: e.label,
  })));

  const withLastTx = addressLastTxs.filter((e) => e.lastTxTimestamp !== undefined);

  if (withLastTx.length > 0) {
    return withLastTx;
  }

  return [defaultAddress];
}
