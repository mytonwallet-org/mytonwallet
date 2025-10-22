/*
 * This file is meant to describe the interface of the chains exported from `src/api/chains`.
 */

import type { ApiActivity, ApiDecryptCommentOptions, ApiFetchActivitySliceOptions } from './activities';
import type { ApiAnyDisplayError, ApiAuthError } from './errors';
import type { ApiActivityTimestamps, ApiChain, ApiNetwork, OnUpdatingStatusChange } from './misc';
import type { ApiAccountWithChain, ApiWalletByChain } from './storage';
import type {
  ApiCheckTransactionDraftOptions,
  ApiCheckTransactionDraftResult,
  ApiFetchEstimateDieselResult,
  ApiSubmitGasfullTransferOptions,
  ApiSubmitGasfullTransferResult,
  ApiSubmitGaslessTransferOptions,
  ApiSubmitGaslessTransferResult,
} from './transfer';
import type { OnApiUpdate } from './updates';

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
  normalizeAddress(address: string, network: ApiNetwork): string;

  //
  // Authentication
  //

  getWalletFromBip39Mnemonic(network: ApiNetwork, mnemonic: string[]): MaybePromise<ApiWalletByChain[T]>;

  getWalletFromAddress(
    network: ApiNetwork,
    addressOrDomain: string,
  ): MaybePromise<{ title?: string; wallet: ApiWalletByChain[T] } | { error: ApiAuthError }>;

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

  /**
   * Opens the verification screen of the chain's app on the Ledger device.
   * Returns the wallet address if the user accepts the verification.
   */
  verifyLedgerWalletAddress(accountId: string): Promise<string | { error: ApiAnyDisplayError }>;

  //
  // Other
  //

  /**
   * Checks once whether this chain's app is open on the Ledger device.
   * Should return an error if the connection with Ledger is broken.
   */
  getIsLedgerAppOpen(): Promise<boolean | { error: ApiAnyDisplayError }>;
}
