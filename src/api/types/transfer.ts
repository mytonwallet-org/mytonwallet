/*
 * This file is chain-agnostic, i.e. it doesn't contain any TON or other chain types.
 */

import type { DieselStatus } from '../../global/types';
import type { ExplainedTransferFee } from '../../util/fee/transferFee';
import type { ApiAnyDisplayError } from './errors';
import type { ApiLocalTransactionParams } from './misc';

export type ApiTransferPayload =
  | { type: 'comment'; text: string; shouldEncrypt?: boolean }
  | { type: 'binary'; data: Uint8Array }
  | { type: 'base64'; data: string };

interface ApiTransactionCommonOptions {
  accountId: string;
  toAddress: string;
  /**
   * When the value is undefined, the method doesn't check the available balance. If you want only to estimate the fee,
   * don't send the amount, because:
   * - The fee doesn't depend on the amount neither in TON nor in TRON.
   * - Errors will happen in edge cases such as 0 and greater than the balance.
   */
  amount?: bigint;
  payload?: ApiTransferPayload;
  /** Base64 */
  stateInit?: string;
  // For token transfer
  tokenAddress?: string;
}

export interface ApiCheckTransactionDraftOptions extends ApiTransactionCommonOptions {
  allowGasless?: boolean;
}

export interface ApiSubmitTransferOptions extends ApiSubmitGasfullTransferOptions {
  /**
   * The real fee (from `explainedFee.realFee.nativeSum`) to show in the created local transaction.
   */
  realFee?: bigint;
  isGasless?: boolean;
  dieselAmount?: bigint;
  isGaslessWithStars?: boolean;

  /**
   * The transaction to be signed and sent. Only used for gasless transfers in Solana.
   */
  gaslessTransaction?: string;
}

export interface ApiSubmitGasfullTransferOptions extends ApiTransactionCommonOptions {
  /** Required only for mnemonic accounts */
  password?: string;
  amount: bigint;
  /** To cap the fee in TRON transfers */
  fee?: bigint;
  noFeeCheck?: boolean;
}

export interface ApiSubmitGaslessTransferOptions extends ApiSubmitGasfullTransferOptions {
  tokenAddress: string;
  dieselAmount: bigint;
  isGaslessWithStars?: boolean;
  gaslessTransaction?: string;
}

export interface ApiCheckTransactionDraftResult {
  addressName?: string;
  isScam?: boolean;
  resolvedAddress?: string;
  isToAddressNew?: boolean;
  isBounceable?: boolean;
  isMemoRequired?: boolean;
  error?: ApiAnyDisplayError;
  /**
   * Describes a possibility to use diesel for this transfer. The UI should prefer diesel when this field is defined,
   * and the diesel status is not "not-available". When the diesel is available, and the UI decides to use it, the fee
   * in `explainedFee` should be used instead.
   */
  diesel?: ApiFetchEstimateDieselResult;
  /**
   * Normalized explanation of the fee and gasless parameters for this draft, ready for UI consumption.
   * Filled by chain-specific `checkTransactionDraft` implementations.
   */
  explainedFee?: ExplainedTransferFee;
}

/**
 * "Gas" is a fee in the native token.
 * "Diesel" is a fee in the transferred token (or in Telegram stars) in gasless mode.
 */
export interface ApiFetchEstimateDieselResult {
  status: DieselStatus;
  /**
   * The amount of the diesel itself. It will be sent together with the actual transfer. None of this will return back
   * as the excess. `undefined` means that gasless transfer is not available, and the diesel shouldn't be shown as the
   * fee; nevertheless, the status should be displayed by the UI.
   *
   * - If the status is not 'stars-fee', the value is measured in the transferred token and charged on top of the
   *   transferred amount.
   * - If the status is 'stars-fee', the value is measured in Telegram stars, and the BigInt assumes 0 decimal places
   *   (i.e. the number is equal to the visible number of stars).
   */
  amount?: bigint;
  /**
   * The native token amount covered by the diesel. Guaranteed to be > 0.
   */
  nativeAmount: bigint;
  /**
   * The remaining part of the fee (the first part is `nativeAmount`) that will be taken from the existing wallet
   * balance. Guaranteed that this amount is available in the wallet. Measured in the native token.
   */
  remainingFee: bigint;
  /**
   * An approximate fee that will be actually spent. The difference between `nativeAmount+remainingFee` and this
   * number is called "excess" and will be returned back to the wallet. Measured in the native token.
   */
  realFee: bigint;

  /**
   * An approximate fee that will be actually spent. The difference between `nativeAmount+remainingFee` and this
   * number is called "excess" and will be returned back to the wallet. Measured in the native token.
   */
  transaction?: string;
}

export interface ApiSubmitGasfullTransferResult {
  txId: string;
  /**
   * The fields that are necessary to add to the local activity (`ApiTransactionActivity`), excluding fields that the
   * method caller can fill by themselves.
   */
  localActivityParams?: Partial<Omit<ApiLocalTransactionParams, 'id' | 'normalizedAddress'>>;
  /** The backend requires it when selling TON or TON tokens currently */
  msgHashForCexSwap?: string;
}

export interface ApiSubmitGaslessTransferResult extends ApiSubmitGasfullTransferResult {
  paymentLink?: string;
  withW5Gasless?: boolean;
}

export type ApiSubmitNftTransferResult = {
  transfers: { toAddress: string }[];
  msgHashNormalized: string;
} | {
  error: string;
};
