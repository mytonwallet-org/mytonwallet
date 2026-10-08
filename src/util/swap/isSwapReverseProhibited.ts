import type { AssetPairs } from '../../global/types';
import { SwapType } from './types';

import { getChainConfig } from '../chain';
import { getChainBySlug } from '../tokens';

/**
 * Whether the swap can be estimated only from the "in" amount. This happens with swaps between chains,
 * with chains that cannot estimate by the buy amount, and with pairs the backend marks as `isReverseProhibited`.
 */
export function isSwapReverseProhibited(
  tokenInSlug: string,
  tokenOutSlug: string,
  swapType: SwapType,
  pairsBySlug?: Record<string, AssetPairs>,
) {
  const tokenInChain = getChainBySlug(tokenInSlug);
  const tokenOutChain = getChainBySlug(tokenOutSlug);
  const isOnchainBuyAmountUnsupported = Boolean(tokenInChain
    && tokenInChain === tokenOutChain
    && !getChainConfig(tokenInChain).canSwapByBuyAmount);

  return swapType !== SwapType.OnChain
    || isOnchainBuyAmountUnsupported
    || Boolean(pairsBySlug?.[tokenInSlug]?.[tokenOutSlug]?.isReverseProhibited);
}
