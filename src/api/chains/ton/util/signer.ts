import type { Cell } from '@ton/core';
import type { SignDataPayload } from '@tonconnect/protocol';
import { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { TonConnectProof } from '../../../dappProtocols/adapters';
import type {
  ApiAccountWithChain,
  ApiAccountWithMnemonic,
  ApiAnyDisplayError,
  ApiNetwork,
  ApiTonWallet,
} from '../../../types';
import type { PreparedTransactionToSign } from '../types';
import { ApiCommonError } from '../../../types';

import { parseAccountId } from '../../../../util/account';
import withCache from '../../../../util/withCache';
import { hexToBytes } from '../../../common/utils';
import { signDataWithPrivateKey, signTonProofWithPrivateKey } from '../../../dappProtocols/adapters/tonConnect/signing';
import { fetchPrivateKey } from '../auth';
import { getTonWallet } from '../wallet';
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
  signTonProof(proof: TonConnectProof): MaybePromise<Buffer | ErrorResult>;
  /** The output Cell order matches the input transactions order exactly. */
  signTransactions(
    transactions: PreparedTransactionToSign[],
    isTonConnect?: boolean,
  ): MaybePromise<Cell[] | ErrorResult>;
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
  account: ApiAccountWithChain<'ton'>,
  /** Required for mnemonic accounts when the mock signing is off */
  password?: string,
  /** Set `true` if you only need to emulate the transaction */
  isMockSigning?: boolean,
  /** Used for specific transactions on vesting.ton.org */
  ledgerSubwalletId?: number,
): Signer {
  if (isMockSigning || account.type === 'view') {
    return new MockSigner(account.byChain.ton);
  }

  if (account.type === 'ledger') {
    return new LedgerSigner(parseAccountId(accountId).network, account.byChain.ton, ledgerSubwalletId);
  }

  if (password === undefined) throw new Error('Password not provided');
  return new MnemonicSigner(accountId, account, password);
}

abstract class PrivateKeySigner implements Signer {
  abstract readonly isMock: boolean;

  constructor(public wallet: ApiTonWallet) {}

  abstract getPrivateKey(): MaybePromise<Uint8Array | ErrorResult>;

  async signTonProof(proof: TonConnectProof) {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    const signature = await signTonProofWithPrivateKey(this.wallet.address, privateKey, proof);
    return Buffer.from(signature);
  }

  async signTransactions(transactions: PreparedTransactionToSign[]) {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    return signTransactionsWithPrivateKey(transactions, this.wallet, privateKey);
  }

  async signData(timestamp: number, domain: string, payload: SignDataPayload) {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    const signature = await signDataWithPrivateKey(
      this.wallet.address,
      timestamp,
      domain,
      payload,
      privateKey,
    );
    return Buffer.from(signature);
  }

  async encryptComment(comment: string, recipientPublicKey: Uint8Array) {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    const encrypted = await encryptMessageComment(
      comment,
      this.getPublicKey(),
      recipientPublicKey,
      privateKey,
      this.wallet.address,
    );
    return Buffer.from(encrypted.buffer, encrypted.byteOffset, encrypted.byteLength);
  }

  async decryptComment(encrypted: Uint8Array, senderAddress: string) {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    return decryptMessageComment(encrypted, this.getPublicKey(), privateKey, senderAddress);
  }

  getPublicKey() {
    const publicKeyHex = this.wallet.publicKey;
    if (!publicKeyHex) {
      // Mnemonic wallets must always have a public key. This error happens when a developer provides a wrong wallet type.
      throw new Error('Public key is missing');
    }
    return hexToBytes(publicKeyHex);
  }
}

class MnemonicSigner extends PrivateKeySigner {
  public isMock = false;

  constructor(
    public accountId: string,
    public account: ApiAccountWithMnemonic & ApiAccountWithChain<'ton'>,
    public password: string,
  ) {
    super(account.byChain.ton);
  }

  // Obtaining the key pair from the password takes much time, so the result is cached.
  public getPrivateKey = withCache(async () => {
    const privateKey = await fetchPrivateKey(this.accountId, this.password, this.account);
    return privateKey || { error: ApiCommonError.InvalidPassword };
  });
}

class MockSigner extends PrivateKeySigner {
  public isMock = true;

  public getPrivateKey() {
    return Buffer.alloc(64);
  }
}

class LedgerSigner implements Signer {
  public readonly isMock = false;

  constructor(
    public network: ApiNetwork,
    public wallet: ApiTonWallet,
    public subwalletId?: number,
  ) {}

  async signTonProof(proof: TonConnectProof) {
    const { signTonProofWithLedger } = await import('../ledger');
    return signTonProofWithLedger(this.network, this.wallet, proof);
  }

  async signTransactions(transactions: PreparedTransactionToSign[], isTonConnect?: boolean) {
    const { signTonTransactionsWithLedger } = await import('../ledger');
    return signTonTransactionsWithLedger(this.network, this.wallet, transactions, this.subwalletId, isTonConnect);
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

function signTransactionsWithPrivateKey(
  transactions: PreparedTransactionToSign[],
  storedWallet: ApiTonWallet,
  secretKeyUint8Array: Uint8Array,
) {
  const secretKey = Buffer.from(secretKeyUint8Array);
  const wallet = getTonWallet(storedWallet);

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
      throw new Error(`${storedWallet.version} wallet doesn't support authType "${authType}"`);
    }

    return wallet.createTransfer({ ...transaction, secretKey });
  });
}
