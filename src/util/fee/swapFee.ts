import type { ApiSwapEstimateVariant, ApiToken } from '../../api/types';
import type { GlobalState } from '../../global/types';
import type { FeePrecision, FeeTerms } from './types';
import { SwapType } from '../../global/types';

import { DEFAULT_OUR_SWAP_FEE } from '../../config';
import { Big } from '../../lib/big.js';
import { bigintDivideToNumber, bigintMax } from '../bigint';
import { bigMax, bigMin } from '../bigNumber';
import { fromDecimal, toBig } from '../decimals';
import { findNativeToken, getChainBySlug, getIsNativeToken } from '../tokens';

type ExplainSwapFeeInput = Pick<GlobalState['currentSwap'],
'tokenInSlug' | 'networkFee' | 'realNetworkFee' | 'ourFee' | 'dieselStatus' | 'dieselFee'
> & {
  swapType: SwapType;
  /** The balance of the "in" token blockchain's native token. Undefined means that it's unknown. */
  nativeTokenInBalance: bigint | undefined;
};

export type ExplainedSwapFee = {
  /** Whether the result implies paying the fee with a diesel */
  isGasless: boolean;
  /**
   * The fee that will be sent with the swap. The wallet must have it on the balance to conduct the swap.
   * Show this in the swap form when the input amount is ≤ the balance, but the remaining balance can't cover the
   * full fee; show `realFee` otherwise. Undefined means that it's unknown.
   */
  fullFee?: {
    precision: FeePrecision;
    terms: FeeTerms<string>;
    /** Only the network fee terms (like `terms` but excluding our fee) */
    networkTerms: FeeTerms<string>;
  };
  /**
   * The real fee (the full fee minus the excess). Undefined means that it's unknown. There is no need to fall back to
   * `fullFee` when `realFee` is undefined (because it's undefined too in this case).
   */
  realFee?: {
    precision: FeePrecision;
    terms: FeeTerms<string>;
    /** Only the network fee terms (like `terms` but excluding our fee) */
    networkTerms: FeeTerms<string>;
  };
  /** The excess fee. Measured in the native token. It's always approximate. Undefined means that it's unknown. */
  excessFee?: string;
  shouldShowOurFee: boolean;
};

type MaxSwapAmountInput = Pick<GlobalState['currentSwap'], 'ourFeePercent'> & {
  swapType: SwapType;
  /** The balance of the "in" token. Undefined means that it's unknown. */
  tokenInBalance: bigint | undefined;
  tokenIn: Pick<ApiToken, 'slug' | 'decimals'> | undefined;
  /** The full network fee terms calculated by `explainSwapFee`. Undefined means that they're unknown. */
  fullNetworkFee: FeeTerms<string> | undefined;
  /** The maximum amount available for swap, as calculated by the backend. Undefined means it's unknown. */
  maxAmountFromBackend: bigint | undefined;
};

type BalanceSufficientForSwapInput = MaxSwapAmountInput & {
  /** The wallet balance of the native token of the "in" token chain. Undefined means that it's unknown. */
  nativeTokenInBalance: bigint | undefined;
  /** The "in" amount to swap. Undefined means that it's unspecified. */
  amountIn: string | undefined;
  /** The maximum amount available for swap, as calculated by the backend. Undefined means it's unknown. */
  maxAmountFromBackend: bigint | undefined;
};

type CanAffordSwapVariant = {
  variant: ApiSwapEstimateVariant;
  tokenIn: Pick<ApiToken, 'slug' | 'decimals'> | undefined;
  /** The balance of the "in" token. Undefined means that it's unknown. */
  tokenInBalance: bigint | undefined;
  /** The wallet balance of the native token of the "in" token chain. Undefined means that it's unknown. */
  nativeTokenInBalance: bigint | undefined;
};

/**
 * Converts the swap fee data returned from API into data that is ready to be displayed in the swap form UI.
 */
export function explainSwapFee(input: ExplainSwapFeeInput): ExplainedSwapFee {
  return shouldSwapBeGasless(input)
    ? explainGaslessSwapFee(input)
    : explainGasfullSwapFee(input);
}

/**
 * Calculates the maximum amount available for the swap.
 * Returns undefined when it can't be calculated because of insufficient input data.
 */
export function getMaxSwapAmount({
  swapType,
  tokenInBalance,
  tokenIn,
  fullNetworkFee,
  ourFeePercent,
  maxAmountFromBackend,
}: MaxSwapAmountInput): bigint | undefined {
  if (maxAmountFromBackend) {
    return maxAmountFromBackend;
  }

  if (swapType === SwapType.CrosschainToWallet || tokenInBalance === undefined) {
    return undefined;
  }

  let maxAmount = tokenInBalance;

  // For a better UX, assuming the fee is 0 when it's unknown
  if (fullNetworkFee) {
    if (!tokenIn) {
      return undefined;
    }

    maxAmount -= fromDecimal(fullNetworkFee.token ?? '0', tokenIn.decimals);

    if (getIsNativeToken(tokenIn.slug)) {
      // When the "in" token is native, both `token` and `native` refer to the same currency, so we consider them both
      maxAmount -= fromDecimal(fullNetworkFee.native ?? '0', tokenIn.decimals);
    }
  }

  ourFeePercent ??= swapType === SwapType.OnChain ? DEFAULT_OUR_SWAP_FEE : 0;
  maxAmount = bigintDivideToNumber(maxAmount, 1 + (ourFeePercent / 100));

  return bigintMax(maxAmount, 0n);
}

/**
 * Decides whether the balance is sufficient to swap the amount and pay the fees.
 * Returns undefined when it can't be calculated because of insufficient input data.
 */
export function isBalanceSufficientForSwap(input: BalanceSufficientForSwapInput) {
  const {
    swapType,
    amountIn,
    tokenInBalance,
    nativeTokenInBalance,
    tokenIn,
    fullNetworkFee,
  } = input;

  if (swapType === SwapType.CrosschainToWallet) {
    return true;
  }

  if (
    amountIn === undefined
    || !tokenIn
    || tokenInBalance === undefined
    || nativeTokenInBalance === undefined
    || !fullNetworkFee
  ) {
    return undefined;
  }

  const nativeTokenIn = findNativeToken(getChainBySlug(tokenIn.slug));
  if (!nativeTokenIn) {
    return undefined;
  }

  const maxAmount = getMaxSwapAmount(input);
  if (maxAmount === undefined) {
    return undefined;
  }

  const swapAmountInBigint = fromDecimal(amountIn, tokenIn.decimals);
  const networkNativeFeeBigint = fromDecimal(fullNetworkFee.native ?? '0', nativeTokenIn.decimals);

  return swapAmountInBigint <= maxAmount && networkNativeFeeBigint <= nativeTokenInBalance;
}

/**
 * Decides whether the balance is sufficient for the given swap estimate variant (DEX).
 * Returns undefined when it can't be calculated because of insufficient input data.
 */
export function canAffordSwapEstimateVariant(input: CanAffordSwapVariant) {
  if (!input.tokenIn || input.nativeTokenInBalance === undefined) {
    return undefined;
  }

  const nativeTokenIn = findNativeToken(getChainBySlug(input.tokenIn.slug));
  if (!nativeTokenIn) {
    return undefined;
  }

  // Try to pay with gas
  const networkFeeBigint = fromDecimal(input.variant.networkFee, nativeTokenIn.decimals);
  if (input.nativeTokenInBalance >= networkFeeBigint) {
    return true;
  }

  // Otherwise, try to pay with diesel
  if (input.variant.dieselFee) {
    if (input.tokenInBalance === undefined) {
      return undefined;
    }
    const dieselFeeBigint = fromDecimal(input.variant.dieselFee, input.tokenIn.decimals);
    if (input.tokenInBalance >= dieselFeeBigint) {
      return true;
    }
  }

  return false;
}

export function shouldSwapBeGasless(
  input: Pick<ExplainSwapFeeInput, 'tokenInSlug' | 'nativeTokenInBalance' | 'networkFee' | 'dieselStatus' | 'swapType'>,
) {
  const isNativeIn = getIsNativeToken(input.tokenInSlug);
  const nativeTokenBalance = getBigNativeTokenInBalance(input);
  const isInsufficientNative = input.networkFee !== undefined && nativeTokenBalance !== undefined
    && nativeTokenBalance.lt(input.networkFee);

  return (
    input.swapType === SwapType.OnChain
    && isInsufficientNative
    && !isNativeIn
    && Boolean(input.dieselStatus) && input.dieselStatus !== 'not-available'
  );
}

/**
 * Converts the data of a swap not involving diesel
 */
function explainGasfullSwapFee(input: ExplainSwapFeeInput) {
  const result: ExplainedSwapFee = {
    isGasless: false,
    excessFee: getExcessFee(input),
    shouldShowOurFee: shouldShowOurFee(input),
  };

  const isNativeIn = getIsNativeToken(input.tokenInSlug);
  const isExact = result.excessFee === '0';

  if (input.networkFee !== undefined) {
    const networkTerms = { native: input.networkFee };
    result.fullFee = {
      precision: isExact ? 'exact' : 'lessThan',
      terms: addOurFeeToTerms(networkTerms, input.ourFee ?? '0', isNativeIn),
      networkTerms,
    };
    result.realFee = result.fullFee;
  }

  if (input.realNetworkFee !== undefined) {
    const networkTerms = { native: input.realNetworkFee };
    result.realFee = {
      precision: isExact ? 'exact' : 'approximate',
      terms: addOurFeeToTerms(networkTerms, input.ourFee ?? '0', isNativeIn),
      networkTerms,
    };
  }

  return result;
}

/**
 * Converts the diesel of semi-diesel swap data
 */
function explainGaslessSwapFee(input: ExplainSwapFeeInput): ExplainedSwapFee {
  const nativeTokenBalance = getBigNativeTokenInBalance(input);
  const result: ExplainedSwapFee = {
    isGasless: true,
    excessFee: getExcessFee(input),
    shouldShowOurFee: shouldShowOurFee(input),
  };

  if (input.networkFee === undefined || input.dieselFee === undefined || nativeTokenBalance === undefined) {
    return result;
  }

  const isExact = result.excessFee === '0';
  const isStarsDiesel = input.dieselStatus === 'stars-fee';
  const dieselKey = isStarsDiesel ? 'stars' : 'token';

  const networkTerms = {
    [dieselKey]: input.dieselFee,
    native: nativeTokenBalance.toString(),
  };
  result.fullFee = {
    precision: isExact ? 'exact' : 'lessThan',
    terms: addOurFeeToTerms(networkTerms, input.ourFee ?? '0', false),
    networkTerms,
  };
  result.realFee = result.fullFee;

  if (input.realNetworkFee !== undefined) {
    // We are sure this amount is > 0 because `shouldBeGasless` would return `false` otherwise and this function
    // wouldn't be called.
    const networkFeeCoveredByDiesel = Big(input.networkFee).sub(nativeTokenBalance);
    const realFeeInDiesel = Big(input.dieselFee).div(networkFeeCoveredByDiesel).mul(input.realNetworkFee);
    // Cover as much displayed real fee as possible with diesel, because in the excess it will return as the native token.
    const dieselRealFee = bigMin(input.dieselFee, realFeeInDiesel);
    // Cover the remaining real fee with the native token.
    const nativeRealFee = bigMax(0, Big(input.realNetworkFee).sub(networkFeeCoveredByDiesel));

    const realNetworkTerms = {
      [dieselKey]: dieselRealFee.toString(),
      native: nativeRealFee.toString(),
    };
    result.realFee = {
      precision: isExact ? 'exact' : 'approximate',
      terms: addOurFeeToTerms(realNetworkTerms, input.ourFee ?? '0', false),
      networkTerms: realNetworkTerms,
    };
  }

  return result;
}

function getBigNativeTokenInBalance(input: Pick<ExplainSwapFeeInput, 'tokenInSlug' | 'nativeTokenInBalance'>) {
  if (!input.tokenInSlug || input.nativeTokenInBalance === undefined) {
    return undefined;
  }

  const nativeToken = findNativeToken(getChainBySlug(input.tokenInSlug));
  return nativeToken ? toBig(input.nativeTokenInBalance, nativeToken.decimals) : undefined;
}

function getExcessFee({ networkFee, realNetworkFee }: Pick<ExplainSwapFeeInput, 'networkFee' | 'realNetworkFee'>) {
  return networkFee !== undefined && realNetworkFee !== undefined
    ? Big(networkFee).sub(realNetworkFee).toString()
    : undefined;
}

function addOurFeeToTerms(terms: FeeTerms<string>, ourFee: string, isOurFeeNative: boolean) {
  return {
    ...terms,
    native: isOurFeeNative ? Big(terms.native ?? '0').add(ourFee).toString() : terms.native,
    token: isOurFeeNative ? terms.token : Big(terms.token ?? '0').add(ourFee).toString(),
  };
}

function shouldShowOurFee(input: Pick<ExplainSwapFeeInput, 'swapType'>) {
  return input.swapType === SwapType.OnChain;
}
