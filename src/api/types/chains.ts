/*
 * This file is meant to describe the interface of the chains exported from `src/api/chains`.
 */

import type { ChainDappSupport } from '../dappProtocols/types';
import type {
  ApiActivity,
  ApiDecryptCommentOptions,
  ApiFetchActivitySliceOptions,
  ApiFetchTransactionByIdOptions,
} from './activities';
import type { ApiAnyDisplayError } from './errors';
import type {
  ApiActivityTimestamps,
  ApiChain,
  ApiNetwork,
  ApiNft,
  ApiToken,
  OnUpdatingStatusChange,
} from './misc';
import type { ApiAccountWithChain, ApiWalletByChain } from './storage';
import type {
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiFetchEstimateDieselResult,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiSubmitGaslessTransferOptions,
  ApiSubmitGaslessTransferResult,
  ApiSubmitNftTransferResult,
} from './transfer';
import type { OnApiUpdate } from './updates';
import type { ApiAddressInfo } from './wallet';

export interface ChainSdk<T extends ApiChain> {
  //
  // Activity history
  //

  /** Must return activities sorted in accordance with `sortActivities` */
  fetchActivitySlice(options: ApiFetchActivitySliceOptions): Promise<ApiActivity[]>;

  /** May return `undefined` if the activity doesn't change and there are no unexpected errors */
  fetchActivityDetails(accountId: string, activity: ApiActivity): MaybePromise<ApiActivity | undefined>;

  decryptComment(options: ApiDecryptCommentOptions): Promise<string | { error: ApiAnyDisplayError }>;

  //
  // Address
  //

  /**
   * Converts an address to the normalized form (to fill the `normalizedAddress` field of `ApiTransactionActivity`).
   */
  normalizeAddress(network: ApiNetwork, address: string): string;

  //
  // Authentication
  //

  getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): MaybePromise<ApiWalletByChain[T]>;

  getWalletFromPrivateKey(network: ApiNetwork, privateKey: string): MaybePromise<ApiWalletByChain[T]>;

  getWalletFromAddress(
    network: ApiNetwork,
    addressOrDomain: string,
  ): MaybePromise<{ title?: string; wallet: ApiWalletByChain[T] } | { error: ApiAnyDisplayError }>;

  /**
   * Loads wallets with the given indices from the Ledger device and fetches their balances.
   * Should run the actions in parallel and/or batches to achieve the smallest latency.
   */
  getWalletsFromLedgerAndLoadBalance(
    network: ApiNetwork,
    accountIndices: number[],
  ): Promise<{ wallet: ApiWalletByChain[T]; balance: bigint }[] | { error: ApiAnyDisplayError }>;

  //
  // Realtime updates
  //

  /**
   * Starts continuously updating the data of the given account. That includes but not limited to:
   *  - activity history
   *  - balance
   *  - staking
   *  - NFT
   *  - is multisig
   *  - etc...
   *
   * Returns a function that permanently stops updating the data when called.
   */
  setupActivePolling(
    accountId: string,
    account: ApiAccountWithChain<T>,
    onUpdate: OnApiUpdate,
    onUpdatingStatusChange: OnUpdatingStatusChange,
    newestActivityTimestamps: ApiActivityTimestamps,
  ): NoneToVoidFunction;

  /**
   * Starts continuously updating the balance of the given account. It may update other data but only if it doesn't
   * require extra API calls or CPU load.
   *
   * Returns a function that permanently stops updating the data when called.
   */
  setupInactivePolling(accountId: string, account: ApiAccountWithChain<T>, onUpdate: OnApiUpdate): NoneToVoidFunction;

  //
  // Tokens
  //

  /** Fetches the token info and only returns it */
  fetchToken(network: ApiNetwork, tokenAddress: string): Promise<ApiToken | { error: ApiAnyDisplayError }>;

  /** Fetches the token info, puts it into the SDK cache and calls `sendTokensUpdate` if the token list changes */
  importToken(network: ApiNetwork, tokenAddress: string, sendTokensUpdate: NoneToVoidFunction): Promise<void>;

  //
  // Sending transfers
  //

  checkTransactionDraft(options: ApiCheckTransactionDraftOptions): Promise<ApiCheckTransactionDraftResult>;

  /** The goal of the function is acting like `checkTransactionDraft` but return only the diesel information */
  fetchEstimateDiesel(accountId: string, tokenAddress: string): MaybePromise<ApiFetchEstimateDieselResult>;

  /** Builds, signs and sends a transfer with the fee paid from the current wallet */
  submitGasfullTransfer(
    options: ApiSubmitGasfullTransferOptions,
  ): Promise<ApiSubmitGasfullTransferResult | { error: string }>;

  /**
   * Builds, signs and sends a transfer with the fee paid by MyTonWallet in exchange to diesel, i.e. a small amount
   * of the transferred token. If the chain doesn't support gasless transfers, it mustn't add `diesel` to the
   * `checkTransactionDraft` result.
   */
  submitGaslessTransfer(
    options: ApiSubmitGaslessTransferOptions,
  ): Promise<ApiSubmitGaslessTransferResult | { error: string }>;

  //
  // Wallet info
  //

  /** Validates the given address and fetches information about it */
  getAddressInfo(
    network: ApiNetwork,
    addressOrDomain: string,
  ): MaybePromise<ApiAddressInfo | { error: ApiAnyDisplayError }>;

  /**
   * Opens the verification screen of the chain's app on the Ledger device.
   * Returns the wallet address if the user accepts the verification.
   */
  verifyLedgerWalletAddress(accountId: string): Promise<string | { error: ApiAnyDisplayError }>;

  /**
   * Returns the private key of the given account in the format used by `getWalletFromPrivateKey`, even if it's a
   * mnemonic account. Returns `undefined` if the account doesn't exist.
   */
  fetchPrivateKeyString(accountId: string, password: string): Promise<string | undefined>;

  //
  // Other
  //

  /**
   * Checks once whether this chain's app is open on the Ledger device.
   * Should return an error if the connection with Ledger is broken.
   */
  getIsLedgerAppOpen(): Promise<boolean | { error: ApiAnyDisplayError }>;

  /**
   * Fetches transaction/trace info by hash or trace ID for deeplink viewing.
   * Returns all activities from a transaction, regardless of which wallet initiated it.
   * `walletAddress` is only used for determining the isIncoming perspective.
   * For TON, `txId` can be either a trace_id or msg_hash. For TRON, `txId` is a transaction hash.
   */
  fetchTransactionById(options: ApiFetchTransactionByIdOptions): Promise<ApiActivity[]>;

  /**
   * SDK submodule responsible for unified dApp workflow. Omitted if no dApp connection expected (TRON)
   */
  dapp?: ChainDappSupport<T>;

  //
  // NFT
  //

  /** Synchronous fetch for UI pagination and collection filtering. No streaming. */
  getAccountNfts: (
    accountId: string,
    options?: {
      collectionAddress?: string;
      offset?: number;
      limit?: number;
    }) => Promise<ApiNft[]>;

  /**
   * Streaming full load of all account NFTs. Data arrives via `onBatch` callbacks.
   * The returned `Promise<void>` resolves when loading is complete.
   * Supports cooperative cancellation via `signal`.
   */
  streamAllAccountNfts: (
    accountId: string,
    options: {
      signal?: AbortSignal;
      onBatch: (nfts: ApiNft[]) => void;
    }) => Promise<void>;

  /**
   * Emulates NFT transfer transaction to show preview with tx fee, etc
   */
  checkNftTransferDraft: (options: {
    accountId: string;
    nfts: ApiNft[];
    toAddress: string;
    comment?: string;
    isNftBurn?: boolean;
  }) => Promise<ApiCheckTransactionDraftResult>;

  submitNftTransfers: (options: {
    accountId: string;
    password: string | undefined;
    nfts: ApiNft[];
    toAddress: string;
    comment?: string;
    isNftBurn?: boolean;
  }) => Promise<ApiSubmitNftTransferResult>;

  /**
   * Checks ownership of NFT, currently used in MTW NFT-cards flow
   */
  checkNftOwnership: (accountId: string, nftAddress: string) => Promise<boolean>;
}
