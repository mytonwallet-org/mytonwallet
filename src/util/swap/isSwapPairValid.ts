import type { ApiChain, ApiSwapVersion } from '../../api/types';
import type { AssetPairs } from '../../global/types';

import { getChainBySlug } from '../tokens';

export function isSwapPairValid(
  tokenInSlug: string,
  tokenOutSlug: string,
  pairsBySlug: Record<string, AssetPairs> | undefined,
  swapVersion: ApiSwapVersion,
  accountChains: Partial<Record<ApiChain, unknown>>,
): boolean {
  if (!isSwapPairInAccountScope(tokenInSlug, tokenOutSlug, accountChains)) {
    return false;
  }

  return !!pairsBySlug?.[tokenInSlug]?.[tokenOutSlug]
    || isWellKnownAllowedPair(getChainBySlug(tokenInSlug), getChainBySlug(tokenOutSlug), swapVersion);
}

/**
 * The app UI doesn't support cases where the "in" token is sent from an external source, and the "out" token is sent
 * to an external wallet. So, we forbid pairs where neither token's chain is in the user's account chains, even if
 * such swap is technically possible (i.e. occurs in `pairsBySlug`).
 */
export function isSwapPairInAccountScope(
  tokenInSlug: string,
  tokenOutSlug: string,
  accountChains: Partial<Record<ApiChain, unknown>>,
) {
  return getChainBySlug(tokenInSlug) in accountChains || getChainBySlug(tokenOutSlug) in accountChains;
}

// TODO: implement chainAgnostic system
function isWellKnownAllowedPair(tokenInChain: ApiChain, tokenOutChain: ApiChain, swapVersion: ApiSwapVersion) {
  return swapVersion === 3 && tokenInChain === tokenOutChain && ['ton', 'solana'].includes(tokenInChain);
}
