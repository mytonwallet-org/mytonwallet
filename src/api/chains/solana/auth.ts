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
  ApiAccountWithChain,
  ApiAccountWithMnemonic,
  ApiAnyDisplayError,
  ApiDerivation,
  ApiNetwork,
  ApiSolanaWallet,
  ApiWalletVariant,
} from '../../types';
import type { SolanaKeyPairSigner } from './types';
import { ApiCommonError } from '../../types';

import * as HDKey from '../../../lib/ed25519-hd-key';
import { parseAccountId } from '../../../util/account';
import isMnemonicPrivateKey from '../../../util/isMnemonicPrivateKey';
import { split } from '../../../util/iteratees';
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
const WALLET_DERIVATIONS_BATCH_SIZE = 6;
const SETTINGS_MULTIWALLET_BY_PATH_COUNT = 4;
const MAX_NON_EMPTY_WALLETS_TO_SCAN = 20;

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

      const privateKey = (await getRawWalletFromBip39Mnemonic(network, mnemonic, derivation)).privateKeyBytes;

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
  isMigration?: boolean,
): Promise<ApiSolanaWallet> {
  const raw = await getRawWalletFromBip39Mnemonic(network, mnemonic, undefined, isMigration);

  return {
    address: raw.wallet.address,
    publicKey: bytesToHex(raw.wallet.publicKeyBytes),
    index: 0,
    derivation: { path: raw.path, index: raw.index, label: raw.label },
  };
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

export async function createSubWalletFromDerivation(
  network: ApiNetwork,
  account: ApiAccountWithChain<'solana'>,
  mnemonic: string[],
): Promise<ApiSolanaWallet | { error: ApiAnyDisplayError }> {
  const current = account.byChain.solana;
  if (!current) {
    return { error: ApiCommonError.Unexpected };
  }

  const { derivation } = current;

  const defaultLabel = 'phantom';

  const pathTemplate = derivation?.path ?? SOLANA_DERIVATION_PATHS[defaultLabel];
  const startIndex = derivation?.index ?? 0;

  const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));
  const seedHex = seed.toString('hex');

  let offset = startIndex + 1;
  let scannedNonEmptyWallets = 0;

  let emptySubwallet: {
    wallet: SolanaKeyPairSigner;
    privateKeyBytes: Uint8Array<ArrayBufferLike>;
    path: string;
    index: number;
  } | undefined;

  while (emptySubwallet === undefined) {
    const batch = Array.from({ length: SETTINGS_MULTIWALLET_BY_PATH_COUNT }, (_, indexInBatch) =>
      getWalletVariantByIndex(seedHex, pathTemplate, offset + indexInBatch));

    const balances = await Promise.all(batch.map(({ wallet }) => getWalletBalance(network, wallet.address)));

    for (const [i, subwallet] of batch.entries()) {
      if (balances[i] === 0n) {
        emptySubwallet = subwallet;
        break;
      }

      scannedNonEmptyWallets += 1;
      if (scannedNonEmptyWallets >= MAX_NON_EMPTY_WALLETS_TO_SCAN) {
        break;
      }
    }

    if (scannedNonEmptyWallets >= MAX_NON_EMPTY_WALLETS_TO_SCAN) {
      break;
    }

    offset += SETTINGS_MULTIWALLET_BY_PATH_COUNT;

    if (emptySubwallet === undefined) {
      await pause(500);
    }
  }

  if (emptySubwallet === undefined) {
    return { error: ApiCommonError.Unexpected };
  }

  const signer = emptySubwallet.wallet;

  return {
    address: signer.address,
    publicKey: bytesToHex(signer.publicKeyBytes),
    index: current.index,
    derivation: {
      path: pathTemplate,
      index: emptySubwallet.index,
      label: derivation?.label || defaultLabel,
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
    return { ...wallet, label: derivation.label };
  } else {
    const bestWallet = await pickBestWallet(network, seed.toString('hex'), isMigration);
    return bestWallet;
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

export async function getWalletVariants(
  network: ApiNetwork,
  account: ApiAccountWithChain<'solana'>,
  page: number,
  isTestnetSubwalletId?: boolean,
  mnemonic?: string[],
): Promise<ApiWalletVariant<'solana'>[] | { error: ApiAnyDisplayError }> {
  if (!mnemonic) {
    return { error: ApiCommonError.Unexpected };
  }

  const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));

  const offset = page * SETTINGS_MULTIWALLET_BY_PATH_COUNT;

  const addreses = getWalletVariantsByPath(seed.toString('hex'), SETTINGS_MULTIWALLET_BY_PATH_COUNT, offset);

  const batches = split(addreses, WALLET_DERIVATIONS_BATCH_SIZE);

  const addressesWithBalances: {
    wallet: SolanaKeyPairSigner;
    balance: bigint;
    privateKeyBytes: Uint8Array<ArrayBufferLike>;
    path: string;
    label: string | undefined;
    index: number;
  }[] = [];

  for (const batch of batches) {
    const addressBalances = await Promise.all(batch.map(async (e) => ({
      wallet: e.wallet,
      balance: await getWalletBalance(network, e.wallet.address),
      privateKeyBytes: e.privateKeyBytes,
      path: e.path,
      label: e.label,
      index: e.index,
    })));
    addressesWithBalances.push(...addressBalances);

    await pause(500);
  }

  return addressesWithBalances.map((e) => ({
    chain: 'solana',
    wallet: {
      address: e.wallet.address,
      publicKey: bytesToHex(e.wallet.publicKeyBytes),
      index: account.byChain.solana.index,
      derivation: { path: e.path, index: e.index, label: e.label },
    },
    balance: e.balance,
    metadata: {
      type: 'path',
      path: e.path.replace('{index}', e.index.toString()),
      label: e.label,
    },
  }));
}

export async function pickBestWallet(network: ApiNetwork, seed: string, isMigration?: boolean) {
  const addresses = getWalletVariantsByPath(seed);

  const defaultAddress = addresses.find((e) => e.path === SOLANA_DERIVATION_PATHS.phantom)!;

  if (isMigration) {
    return defaultAddress;
  }

  const addressBalances = await Promise.all(addresses.map(async (e) => ({
    wallet: e.wallet,
    balance: await getWalletBalance(network, e.wallet.address),
    privateKeyBytes: e.privateKeyBytes,
    path: e.path,
    index: e.index,
    label: e.label,
  })));

  const bestWalletByBalance = addressBalances.reduce<typeof addressBalances[0] | undefined>((best, current) => {
    return current.balance > (best?.balance ?? 0n) ? current : best;
  }, undefined);

  if (bestWalletByBalance) {
    return bestWalletByBalance;
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

  const bestWalletByLastTx = addressLastTxs.reduce<typeof addressLastTxs[0] | undefined>((best, current) => {
    return current?.lastTxTimestamp && current.lastTxTimestamp > (best?.lastTxTimestamp ?? 0) ? current : best;
  }, undefined);

  if (bestWalletByLastTx) {
    return bestWalletByLastTx;
  }

  return defaultAddress;
}
