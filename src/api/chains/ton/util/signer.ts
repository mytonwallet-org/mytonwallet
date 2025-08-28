import type { Address, Cell } from '@ton/core';
import type { SignDataPayload } from '@tonconnect/protocol';
import type { SignKeyPair } from 'tweetnacl';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { ApiTonConnectProof } from '../../../tonConnect/types';
import type {
  ApiAccountWithMnemonic,
  ApiAccountWithTon,
  ApiAnyDisplayError,
  ApiNetwork,
  ApiTonWallet,
} from '../../../types';
import type { ApiTonWalletVersion, PreparedTransactionToSign } from '../types';
import { ApiCommonError } from '../../../types';

import { parseAccountId } from '../../../../util/account';
import withCache from '../../../../util/withCache';
import { hexToBytes } from '../../../common/utils';
import { signDataWithPrivateKey, signTonProofWithPrivateKey } from '../../../tonConnect/signing';
import { fetchKeyPair } from '../auth';
import { buildWallet } from '../wallet';
import { decryptMessageComment, encryptMessageComment } from './encryption';

type ErrorResult = { error: ApiAnyDisplayError };

/**
 * Signs, encrypts and decrypts TON stuff.
 *
 * For all the methods: error is _returned_ only for expected errors, i.e. caused not by mistakes in the app code.
 */
export interface Signer {
  /** Whether the signer produces invalid signatures and encryption, for example for emulation */
  readonly isMock: boolean;
  signTonProof(proof: ApiTonConnectProof): MaybePromise<Buffer | ErrorResult>;
  /** The output Cell order matches the input transactions order exactly. */
  signTransactions(transactions: PreparedTransactionToSign[]): MaybePromise<Cell[] | ErrorResult>;
  /**
   * See https://docs.tonconsole.com/academy/sign-data#how-the-signature-is-built for more details.
   *
   * @params timestamp The current time in Unix seconds
   */
  signData(
    timestamp: number,
    domain: string,
    payload: SignDataPayload,
  ): MaybePromise<Buffer | ErrorResult>;
  /** @ignore This is not signing, but it's a part of this interface to eliminate excess private key fetching. */
  encryptComment(comment: string, recipientPublicKey: Uint8Array): MaybePromise<Buffer | ErrorResult>;
  decryptComment(encrypted: Uint8Array, senderAddress: string): MaybePromise<string | ErrorResult>;
}

export function getSigner(
  accountId: string,
  account: ApiAccountWithTon,
  /** Required for mnemonic accounts when the mock signing is off */
  password?: string,
  /** Set `true` if you only need to emulate the transaction */
  isMockSigning?: boolean,
  /** Used for specific transactions on vesting.ton.org */
  ledgerSubwalletId?: number,
): Signer {
  if (isMockSigning || account.type === 'view') {
    return new MockSigner(account.ton);
  }

  if (account.type === 'ledger') {
    return new LedgerSigner(parseAccountId(accountId).network, account.ton, ledgerSubwalletId);
  }

  if (password === undefined) throw new Error('Password not provided');
  return new MnemonicSigner(accountId, account, password);
}

abstract class PrivateKeySigner implements Signer {
  public abstract readonly isMock: boolean;

  constructor(
    public walletAddress: string | Address,
    public walletVersion: ApiTonWalletVersion,
  ) {}

  public abstract getKeyPair(): MaybePromise<SignKeyPair | ErrorResult>;

  async signTonProof(proof: ApiTonConnectProof) {
    const keyPair = await this.getKeyPair();
    if ('error' in keyPair) return keyPair;

    const signature = await signTonProofWithPrivateKey(this.walletAddress, keyPair.secretKey, proof);
    return Buffer.from(signature);
  }

  async signTransactions(transactions: PreparedTransactionToSign[]) {
    const keyPair = await this.getKeyPair();
    if ('error' in keyPair) return keyPair;

    return signTransactionsWithKeyPair(transactions, this.walletVersion, keyPair);
  }

  async signData(timestamp: number, domain: string, payload: SignDataPayload) {
    const keyPair = await this.getKeyPair();
    if ('error' in keyPair) return keyPair;

    const signature = await signDataWithPrivateKey(
      this.walletAddress,
      timestamp,
      domain,
      payload,
      keyPair.secretKey,
    );
    return Buffer.from(signature);
  }

  async encryptComment(comment: string, recipientPublicKey: Uint8Array) {
    const keyPair = await this.getKeyPair();
    if ('error' in keyPair) return keyPair;

    const encrypted = await encryptMessageComment(
      comment,
      keyPair.publicKey,
      recipientPublicKey,
      keyPair.secretKey,
      this.walletAddress,
    );
    return Buffer.from(encrypted.buffer, encrypted.byteOffset, encrypted.byteLength);
  }

  async decryptComment(encrypted: Uint8Array, senderAddress: string) {
    const keyPair = await this.getKeyPair();
    if ('error' in keyPair) return keyPair;

    return decryptMessageComment(encrypted, keyPair.publicKey, keyPair.secretKey, senderAddress);
  }
}

class MnemonicSigner extends PrivateKeySigner {
  public isMock = false;

  constructor(
    public accountId: string,
    public account: ApiAccountWithMnemonic,
    public password: string,
  ) {
    const { address, version } = account.ton;
    super(address, version);
  }

  // Obtaining the key pair from the password takes much time, so the result is cached.
  public getKeyPair = withCache(async () => {
    const keyPair = await fetchKeyPair(this.accountId, this.password, this.account);
    return keyPair || { error: ApiCommonError.InvalidPassword };
  });
}

class MockSigner extends PrivateKeySigner {
  public isMock = true;
  public publicKeyHex?: string;

  constructor({ address, version, publicKey }: ApiTonWallet) {
    super(address, version);
    this.publicKeyHex = publicKey;
  }

  public getKeyPair() {
    const { publicKeyHex } = this;
    return {
      publicKey: publicKeyHex ? hexToBytes(publicKeyHex) : Buffer.alloc(64),
      secretKey: Buffer.alloc(64),
    };
  }
}

class LedgerSigner implements Signer {
  public readonly isMock = false;

  constructor(
    public network: ApiNetwork,
    public wallet: ApiTonWallet,
    public subwalletId?: number,
  ) {}

  async signTonProof(proof: ApiTonConnectProof) {
    const { signTonProofWithLedger } = await import('./ledger');
    return signTonProofWithLedger(this.network, this.wallet, proof);
  }

  async signTransactions(transactions: PreparedTransactionToSign[]) {
    const { signTonTransactionsWithLedger } = await import('./ledger');
    return signTonTransactionsWithLedger(this.network, this.wallet, transactions, this.subwalletId);
  }

  signData(): never {
    throw new Error('Ledger does not support SignData');
  }

  encryptComment(): never {
    throw new Error('Ledger does not support comment encryption');
  }

  decryptComment(): never {
    throw new Error('Ledger does not support comment decryption');
  }
}

function signTransactionsWithKeyPair(
  transactions: PreparedTransactionToSign[],
  walletVersion: ApiTonWalletVersion,
  keyPair: SignKeyPair,
) {
  const secretKey = Buffer.from(keyPair.secretKey);
  const wallet = buildWallet(keyPair.publicKey, walletVersion);

  return transactions.map((transaction) => {
    if (wallet instanceof WalletContractV5R1) {
      return wallet.createTransfer({
        ...transaction,
        // TODO Remove it. There is bug in @ton/ton library that causes transactions to be executed in reverse order.
        messages: [...transaction.messages].reverse(),
        secretKey,
      });
    }

    const { authType = 'external' } = transaction;
    if (authType !== 'external') {
      throw new Error(`${walletVersion} wallet doesn't support authType "${authType}"`);
    }

    return wallet.createTransfer({ ...transaction, secretKey });
  });
}
