import type { ApiCheckTransactionDraftResult, ApiFetchEstimateDieselResult } from '../../api/types';
import type { FeePrecision, FeeTerms } from './types';

import { Big } from '../../lib/big.js';
import { bigintMax, bigintMin } from '../bigint';
import { getChainConfig } from '../chain';
import { getChainBySlug, getIsNativeToken } from '../tokens';

type ApiFee = Pick<ApiCheckTransactionDraftResult, 'fee' | 'realFee' | 'diesel'> & {
  /** The slug of the token that is being transferred */
  tokenSlug: string;
};

export type ExplainedTransferFee = {
  /** Whether the result implies paying the fee with a diesel */
  isGasless: boolean;
  /**
   * The fee that will be sent with the transfer. The wallet must have it on the balance to send the transfer.
   * Show this in the transfer form when the input amount is ≤ the balance, but the remaining balance can't cover the
   * full fee; show `realFee` otherwise. Undefined means that it's unknown.
   */
  fullFee?: {
    precision: FeePrecision;
    terms: FeeTerms<bigint>;
    /** The sum of `terms` measured in the native token */
    nativeSum: bigint;
  };
  /**
   * The real fee (the full fee minus the excess). Undefined means that it's unknown. There is no need to fall back to
   * `fullFee` when `realFee` is undefined (because it's undefined too in this case).
   */
  realFee?: {
    precision: FeePrecision;
    terms: FeeTerms<bigint>;
    /** The sum of `terms` measured in the native token */
    nativeSum: bigint;
  };
  /** The excess fee. Measured in the native token. It's always approximate. Undefined means that it's unknown. */
  excessFee?: bigint;
  /**
   * Whether the full token balance can be transferred despite the fee.
   * If yes, the fee will be taken from the transferred amount.
   */
  canTransferFullBalance: boolean;
};

type AvailableDiesel = ApiFetchEstimateDieselResult & { amount: bigint };
type ApiFeeWithDiesel = ApiFee & { diesel: AvailableDiesel };

type MaxTransferAmountInput = {
  /** The wallet balance of the transferred token. Undefined means that it's unknown. */
  tokenBalance: bigint | undefined;
  /** The slug of the token that is being transferred */
  tokenSlug: string;
  /** The full fee terms calculated by `explainApiTransferFee`. Undefined means that they're unknown. */
  fullFee: FeeTerms<bigint> | undefined;
  /** Whether the full token balance can be transferred despite the fee. */
  canTransferFullBalance: boolean;
};

type BalanceSufficientForTransferInput = Omit<MaxTransferAmountInput, 'tokenSlug'> & {
  /** The wallet balance of the native token of the transfer chain. Undefined means that it's unknown. */
  nativeTokenBalance: bigint | undefined;
  /** The transferred amount. Use 0 for NFT transfers. Undefined means that it's unspecified. */
  transferAmount: bigint | undefined;
};

/**
 * Converts the transfer fee data returned from API into data that is ready to be displayed in the transfer form UI.
 */
export function explainApiTransferFee(input: ApiFee): ExplainedTransferFee {
  return shouldUseDiesel(input)
    ? explainGaslessTransferFee(input)
    : explainGasfullTransferFee(input);
}

/**
 * Calculates the maximum amount available for the transfer.
 * Returns `undefined` when it can't be calculated because of insufficient input data.
 */
export function getMaxTransferAmount({
  tokenBalance,
  tokenSlug,
  fullFee,
  canTransferFullBalance,
}: MaxTransferAmountInput): bigint | undefined {
  if (tokenBalance === undefined) {
    return undefined;
  }

  // Returning the full balance when the fee is unknown for a better UX
  if (canTransferFullBalance || !fullFee) {
    return tokenBalance;
  }

  let fee = fullFee.token ?? 0n;
  if (getIsNativeToken(tokenSlug)) {
    // When the token is native, both `token` and `native` refer to the same currency, so they should be added
    fee += fullFee.native ?? 0n;
  }

  return bigintMax(tokenBalance - fee, 0n);
}

/**
 * Decides whether the balance is sufficient to transfer the amount and pay the fees.
 * Returns undefined when it can't be calculated because of insufficient input data.
 */
export function isBalanceSufficientForTransfer({
  tokenBalance,
  nativeTokenBalance,
  transferAmount,
  fullFee,
  canTransferFullBalance,
}: BalanceSufficientForTransferInput) {
  if (transferAmount === undefined || tokenBalance === undefined || nativeTokenBalance === undefined || !fullFee) {
    return undefined;
  }

  const isFullTokenTransfer = transferAmount === tokenBalance && canTransferFullBalance;
  const tokenRequiredAmount = (fullFee.token ?? 0n) + (isFullTokenTransfer ? 0n : transferAmount);
  const nativeTokenRequiredAmount = fullFee.native ?? 0n;

  return tokenRequiredAmount <= tokenBalance && nativeTokenRequiredAmount <= nativeTokenBalance;
}

export function isDieselAvailable(diesel: ApiFetchEstimateDieselResult): diesel is AvailableDiesel {
  return diesel.status !== 'not-available' && diesel.amount !== undefined;
}

export function getDieselTokenAmount(diesel: ApiFetchEstimateDieselResult) {
  return diesel.status === 'stars-fee' ? 0n : (diesel.amount ?? 0n);
}

function shouldUseDiesel(input: ApiFee): input is ApiFeeWithDiesel {
  return input.diesel !== undefined && isDieselAvailable(input.diesel);
}

/**
 * Converts the data of a transfer not involving diesel
 */
function explainGasfullTransferFee(input: ApiFee) {
  const result: ExplainedTransferFee = {
    isGasless: false,
    canTransferFullBalance: getIsNativeToken(input.tokenSlug)
      && getChainConfig(getChainBySlug(input.tokenSlug)).canTransferFullNativeBalance,
  };

  if (input.fee !== undefined) {
    result.fullFee = {
      precision: input.realFee === input.fee ? 'exact' : 'lessThan',
      terms: { native: input.fee },
      nativeSum: input.fee,
    };
    result.realFee = result.fullFee;
  }

  if (input.realFee !== undefined) {
    result.realFee = {
      precision: input.realFee === input.fee ? 'exact' : 'approximate',
      terms: { native: input.realFee },
      nativeSum: input.realFee,
    };
  }

  if (input.fee !== undefined && input.realFee !== undefined) {
    result.excessFee = input.fee - input.realFee;
  }

  return result;
}

/**
 * Converts the diesel of semi-diesel transfer data
 */
function explainGaslessTransferFee({ diesel }: ApiFeeWithDiesel) {
  const isStarsDiesel = diesel.status === 'stars-fee';
  const dieselKey = isStarsDiesel ? 'stars' : 'token';
  const realFeeInDiesel = convertFee(diesel.realFee, diesel.nativeAmount, diesel.amount);
  // Cover as much displayed real fee as possible with diesel, because in the excess it will return as the native token.
  const dieselRealFee = bigintMin(diesel.amount, realFeeInDiesel);
  // Cover the remaining real fee with the native token.
  const nativeRealFee = bigintMax(0n, diesel.realFee - diesel.nativeAmount);

  return {
    isGasless: true,
    canTransferFullBalance: false,
    fullFee: {
      precision: 'lessThan',
      terms: {
        [dieselKey]: diesel.amount,
        native: diesel.remainingFee,
      },
      nativeSum: diesel.nativeAmount + diesel.remainingFee,
    },
    realFee: {
      precision: 'approximate',
      terms: {
        [dieselKey]: dieselRealFee,
        native: nativeRealFee,
      },
      nativeSum: diesel.realFee,
    },
    excessFee: diesel.nativeAmount + diesel.remainingFee - diesel.realFee,
  } satisfies ExplainedTransferFee;
}

/**
 * `exampleFromAmount` and `exampleToAmount` define the exchange rate used to convert `amount`.
 * `exampleFromAmount` is defined in the same currency as `amount`. Mustn't be 0.
 * `exampleToAmount` is defined in the currency you want to get.
 */
function convertFee(
  amount: bigint,
  exampleFromAmount: bigint,
  exampleToAmount: bigint,
) {
  const exchangeRate = Big(exampleToAmount.toString()).div(exampleFromAmount.toString());
  return BigInt(Big(amount.toString()).mul(exchangeRate).round().toString());
}
