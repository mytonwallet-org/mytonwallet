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
import { fetchStoredAccount } from '../../common/accounts';
import { getKnownAddressInfo } from '../../common/addresses';
import { getMnemonic } from '../../common/mnemonic';
import { bytesToHex } from '../../common/utils';
import { isValidAddress } from './address';
import { SOLANA_DERIVATION_PATHS } from './constants';

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

      const privateKey = getRawWalletFromBip39Mnemonic(network, mnemonic).rawPrivateKey;

      return bytesToHex(privateKey);
    }
  } catch (err) {
    logDebugError('fetchPrivateKeyString', err);

    return undefined;
  }
}

export function getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): ApiSolanaWallet {
  const raw = getRawWalletFromBip39Mnemonic(network, mnemonic);

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

function getRawWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]) {
  const seed = bip39.mnemonicToSeedSync(mnemonic.join(' '));

  const seedByCustomPath = HDKey.derivePath(SOLANA_DERIVATION_PATHS.phantom, seed.toString('hex')).key;

  const derivedKeypair = nacl.sign.keyPair.fromSeed(seedByCustomPath);
  const privateKeyBytes = derivedKeypair.secretKey.subarray(0, 32);

  const wallet = createNaclKeyPairSigner(new Uint8Array(privateKeyBytes));

  return { wallet, rawPrivateKey: privateKeyBytes };
}
