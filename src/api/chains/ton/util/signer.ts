import type { StateInit } from '@ton/core';
import { beginCell, type Cell, contractAddress, internal, SendMode, storeMessageRelaxed, toNano } from '@ton/core';
import { sign } from '@ton/crypto';
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
import { randomBytes } from '../../../../util/random';
import withCache from '../../../../util/withCache';
import { getBodyFromRequest, OpCode, prepareBodyWithoutSignature } from '../contracts/MfaExtension';
import { hexToBytes } from '../../../common/utils';
import { signDataWithPrivateKey, signTonProofWithPrivateKey } from '../../../dappProtocols/adapters/tonConnect/signing';
import { fetchPrivateKey } from '../auth';
import { getTonWallet } from '../wallet';
import { decryptMessageComment, encryptMessageComment } from './encryption';

type ErrorResult = { error: ApiAnyDisplayError };

export type SignedMfaRequest = { transaction: Cell; payload: Cell; signature: Buffer };
export type SignedMfaRemoveRequest = { payload: Cell; signature: Buffer };

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
  /** Sign input transactions for MFA Extension */
  signMfaTransactions(
    transactions: PreparedTransactionToSign[],
    mfaExtensionSeqno: number,
    fees: bigint[],
  ): MaybePromise<SignedMfaRequest[] | ErrorResult>;
  signInstallMfaRequest(init: StateInit, seqno: number): MaybePromise<Cell | ErrorResult>;
  signRemoveMfaRequest(mfaExtensionSeqno: number): MaybePromise<SignedMfaRemoveRequest | ErrorResult>;
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

  async signMfaTransactions(
    transactions: PreparedTransactionToSign[],
    mfaExtensionSeqno: number,
    fees: bigint[],
  ): Promise<SignedMfaRequest[] | ErrorResult> {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    return signMfaTransactionsWithPrivateKey(
      transactions,
      this.wallet,
      privateKey,
      mfaExtensionSeqno,
      fees,
    );
  }

  async signInstallMfaRequest(init: StateInit, seqno: number): Promise<Cell | ErrorResult> {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    return signMfaInstallRequestWithPrivateKey(init, seqno, privateKey, this.wallet);
  }

  async signRemoveMfaRequest(mfaExtensionSeqno: number): Promise<SignedMfaRemoveRequest | ErrorResult> {
    const privateKey = await this.getPrivateKey();
    if ('error' in privateKey) return privateKey;

    return signMfaRemoveRequestWithPrivateKey(mfaExtensionSeqno, privateKey);
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
  private readonly privateKey = randomBytes(64);

  public getPrivateKey() {
    return this.privateKey;
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
    if (process.env.NO_LEDGER === '1') throw new Error('Ledger is disabled');

    const { signTonProofWithLedger } = await import('../ledger');
    return signTonProofWithLedger(this.network, this.wallet, proof);
  }

  async signTransactions(transactions: PreparedTransactionToSign[], isTonConnect?: boolean) {
    if (process.env.NO_LEDGER === '1') throw new Error('Ledger is disabled');

    const { signTonTransactionsWithLedger } = await import('../ledger');
    return signTonTransactionsWithLedger(this.network, this.wallet, transactions, this.subwalletId, isTonConnect);
  }

  signMfaTransactions(): never {
    throw new Error('Ledger does not support signMfaTransactions');
  }

  signInstallMfaRequest(init: StateInit, seqno: number): never {
    throw new Error('Ledger does not support signInstallMfaRequest');
  }

  signRemoveMfaRequest(): never {
    throw new Error('Ledger does not support signRemoveMfaRequest');
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

function signMfaRemoveRequestWithPrivateKey(seqno: number, privateKey: Uint8Array) {
  const secretKey = Buffer.from(privateKey);

  const payload = prepareBodyWithoutSignature(
    {
      opCode: OpCode.REMOVE_EXTENSION,
      payload: beginCell().endCell(),
      seqno,
    },
  );

  const signature = sign(payload.hash(), secretKey);

  return { payload, signature };
}

function signMfaInstallRequestWithPrivateKey(
  init: StateInit,
  seqno: number,
  privateKey: Uint8Array,
  storedWallet: ApiTonWallet,
) {
  const secretKey = Buffer.from(privateKey);
  const wallet = getTonWallet(storedWallet);

  if (!(wallet instanceof WalletContractV5R1)) throw new Error('Unsupported');

  const extensionAddress = contractAddress(0, init);

  return wallet.createRequest({
    authType: 'external',
    secretKey,
    seqno,
    actions: [
      {
        type: 'addExtension',
        address: extensionAddress,
      },
      {
        type: 'sendMsg',
        mode: SendMode.PAY_GAS_SEPARATELY,
        outMsg: internal({
          to: extensionAddress,
          // TODO: make it a constant
          value: toNano('0.15'),
          body: beginCell().storeUint(OpCode.INSTALL, 32).endCell(),
          init,
        }),
      },
    ],
  });
}

function signMfaTransactionsWithPrivateKey(transactions: PreparedTransactionToSign[],
  storedWallet: ApiTonWallet,
  secretKeyUint8Array: Uint8Array,
  mfaExtensionSeqno: number,
  fees: bigint[],
) {
  const secretKey = Buffer.from(secretKeyUint8Array);
  const wallet = getTonWallet(storedWallet);

  return transactions.map((transaction, index) => {
    if (!(wallet instanceof WalletContractV5R1)) throw new Error('Unsupported');

    const message = internal(
      {
        to: wallet.address,
        value: fees[index],
        body: wallet.createRequest({
          authType: 'extension',
          seqno: transaction.seqno,
          actions: transaction.messages.map((message) => ({
            type: 'sendMsg',
            outMsg: message,
            mode: transaction.sendMode,
          })),
        }),
      },
    );

    const payload = getBodyFromRequest(
      mfaExtensionSeqno + index,
      message,
    );

    const signature = sign(payload.hash(), secretKey);

    return {
      payload,
      signature,
      transaction: beginCell().store(storeMessageRelaxed(message)).endCell(),
    };
  });
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
