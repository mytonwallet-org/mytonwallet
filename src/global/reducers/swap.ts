import type { ApiSwapAsset } from '../../api/types';
import type { ActionPayloads, GlobalState, TradeDirection } from '../types';
import { SwapInputSource, SwapState } from '../types';

import { DEFAULT_SLIPPAGE_VALUE } from '../../config';
import { Big } from '../../lib/big.js';
import { isSwapReverseProhibited } from '../../util/swap/isSwapReverseProhibited';
import { replaceActivityId } from '../helpers/misc';
import {
  doesSwapChangeRequireEstimation,
  doesSwapChangeRequireEstimationReset,
  getSwapEstimateResetParams,
} from '../helpers/swap';
import { selectCurrentAccountState, selectSwapType } from '../selectors';
import { updateCurrentAccountState } from './misc';

function rawUpdateCurrentSwap(global: GlobalState, update: Partial<GlobalState['currentSwap']>) {
  return {
    ...global,
    currentSwap: {
      ...global.currentSwap,
      ...update,
    },
  };
}

export function updateCurrentSwap(
  global: GlobalState,
  update: Partial<GlobalState['currentSwap']>,
  // Set to true if you want to not trigger the swap estimation, and you are sure estimation is not needed
  doAvoidEstimation?: boolean,
) {
  let newGlobal = rawUpdateCurrentSwap(global, update);

  if (!doAvoidEstimation) {
    if (doesSwapChangeRequireEstimationReset(global, newGlobal)) {
      newGlobal = rawUpdateCurrentSwap(newGlobal, getSwapEstimateResetParams(newGlobal));
    }

    if (doesSwapChangeRequireEstimation(global, newGlobal)) {
      newGlobal = rawUpdateCurrentSwap(newGlobal, { isEstimating: true });
    }
  }

  // Applying the update again because the input fields should have a higher priority than the above automatic updates
  return rawUpdateCurrentSwap(newGlobal, update);
}

export function clearCurrentSwap(global: GlobalState) {
  return {
    ...global,
    currentSwap: {
      state: SwapState.None,
      slippage: DEFAULT_SLIPPAGE_VALUE,
    },
  };
}

/**
 * Writes the amount entered on the Buy / Sell screen into the swap form. `tradeAmount` is always in the screen
 * token, while `amountIn` and `amountOut` are what the backend estimates.
 *
 * Sell: the screen token is the one being paid, so the amount goes to `amountIn` as is.
 *
 * Buy: the screen token is the one being bought. If the pair can be estimated by the buy amount, the amount goes
 * to `amountOut`. Otherwise the backend accepts only the paying amount, so `amountIn` is calculated from the USD
 * prices of both tokens, and the estimate then shows how much is actually bought.
 *
 * `isAmountIn` marks an amount in the paying token (the percent buttons on the Buy screen send such amounts). It
 * goes to `amountIn`, and `tradeAmount` is calculated from it by the USD prices.
 */
export function updateTradeAmount(
  global: GlobalState,
  { amount, isMaxAmount = false, isAmountIn = false }: ActionPayloads['setTradeAmount'],
) {
  const { tradeDirection, tokenInSlug, tokenOutSlug } = global.currentSwap;

  if (tradeDirection !== 'buy') {
    return updateCurrentSwap(global, {
      tradeAmount: amount,
      amountIn: amount,
      isMaxAmount,
      inputSource: SwapInputSource.In,
    });
  }

  const tokenIn = tokenInSlug ? global.swapTokenInfo.bySlug[tokenInSlug] : undefined;
  const tokenOut = tokenOutSlug ? global.swapTokenInfo.bySlug[tokenOutSlug] : undefined;

  if (isAmountIn) {
    return updateCurrentSwap(global, {
      tradeAmount: convertByUsdPrice(amount, tokenIn, tokenOut),
      amountIn: amount,
      isMaxAmount,
      inputSource: SwapInputSource.In,
    });
  }

  const canQuoteByAmountOut = tokenInSlug && tokenOutSlug && !isSwapReverseProhibited(
    tokenInSlug, tokenOutSlug, selectSwapType(global), global.swapPairs?.bySlug,
  );

  if (canQuoteByAmountOut) {
    return updateCurrentSwap(global, {
      tradeAmount: amount,
      amountOut: amount,
      isMaxAmount: false,
      inputSource: SwapInputSource.Out,
    });
  }

  return updateCurrentSwap(global, {
    tradeAmount: amount,
    amountIn: convertByUsdPrice(amount, tokenOut, tokenIn),
    isMaxAmount: false,
    inputSource: SwapInputSource.In,
  });
}

function convertByUsdPrice(amount?: string, from?: ApiSwapAsset, to?: ApiSwapAsset) {
  if (!amount || !from?.priceUsd || !to?.priceUsd) {
    return undefined;
  }

  return Big(amount).mul(from.priceUsd).div(to.priceUsd).round(to.decimals, Big.roundDown).toString();
}

export function updateTradeCounterToken(global: GlobalState, direction: TradeDirection, tokenSlug: string) {
  const { tradeCounterTokenSlugs } = selectCurrentAccountState(global) ?? {};

  return updateCurrentAccountState(global, {
    tradeCounterTokenSlugs: { ...tradeCounterTokenSlugs, [direction]: tokenSlug },
  });
}

/** replaceMap: keys - old (removed) activity ids, value - new (added) activity ids */
export function replaceCurrentSwapId(global: GlobalState, replaceMap: Record<string, string>) {
  return updateCurrentSwap(global, {
    activityId: replaceActivityId(global.currentSwap.activityId, replaceMap),
  });
}
