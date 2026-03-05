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
import { SOLANA_DEFAULT_DERIVATION_PATH, SOLANA_DERIVATION_PATHS } from './constants';
import { getWalletBalance, getWalletLastTransaction } from './wallet';

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

      const privateKey = (await getRawWalletFromBip39Mnemonic(network, mnemonic)).rawPrivateKey;

      return bytesToHex(privateKey);
    }
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);

    return undefined;
  }
}

export async function getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): Promise<ApiSolanaWallet> {
  const raw = await getRawWalletFromBip39Mnemonic(network, mnemonic);

  return {
    address: raw.wallet.address,
    publicKey: bytesToHex(raw.wallet.publicKeyBytes),
    index: 0,
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

async function getRawWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]) {
  const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));

  const bestWallet = await pickBestWallet(network, seed.toString('hex'));

  return { wallet: bestWallet.wallet, rawPrivateKey: bestWallet.privateKeyBytes };
}

const MULTIWALLET_BY_PATH_COUNT = 2;

export async function pickBestWallet(network: ApiNetwork, seed: string) {
  const addresses = Object.entries(SOLANA_DERIVATION_PATHS).map((e) => {
    const acc: {
      wallet: SolanaKeyPairSigner;
      privateKeyBytes: Uint8Array;
      path: string;
    }[] = [];

    for (let i = 0; i < (e[0] === 'default' ? 1 : MULTIWALLET_BY_PATH_COUNT); i++) {
      const path = e[1].replace('{index}', i.toString());
      const seedByCustomPath = HDKey.derivePath(path, seed).key;

      const derivedKeypair = nacl.sign.keyPair.fromSeed(seedByCustomPath);
      const privateKeyBytes = derivedKeypair.secretKey.subarray(0, 32);

      const wallet = createNaclKeyPairSigner(new Uint8Array(privateKeyBytes));

      acc.push({ wallet, privateKeyBytes, path });
    }

    return acc;
  }).flat();

  const addressBalances = await Promise.all(addresses.map(async (e) => ({
    wallet: e.wallet,
    balance: await getWalletBalance(network, e.wallet.address),
    privateKeyBytes: e.privateKeyBytes,
    path: e.path,
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
  })));

  const bestWalletByLastTx = addressLastTxs.reduce<typeof addressLastTxs[0] | undefined>((best, current) => {
    return current?.lastTxTimestamp && current.lastTxTimestamp > (best?.lastTxTimestamp ?? 0) ? current : best;
  }, undefined);

  if (bestWalletByLastTx) {
    return bestWalletByLastTx;
  }

  const defaultAddress = addressBalances.find((e) => e.path === SOLANA_DEFAULT_DERIVATION_PATH)!;

  return defaultAddress;
}
