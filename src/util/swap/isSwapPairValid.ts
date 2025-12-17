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
  const tokenInChain = getChainBySlug(tokenInSlug);
  const tokenOutChain = getChainBySlug(tokenOutSlug);

  // The app UI doesn't support cases where the "in" token is sent from an external source, and the "out" token is sent
  // to an external wallet. So, we forbid pairs where neither token's chain is in the user's account chains, even if
  // such swap is technically possible (i.e. occurs in `pairsBySlug`).
  if (!(tokenInChain in accountChains || tokenOutChain in accountChains)) {
    return false;
  }

  return !!pairsBySlug?.[tokenInSlug]?.[tokenOutSlug]
    || isWellKnownAllowedPair(tokenInChain, tokenOutChain, swapVersion);
}

function isWellKnownAllowedPair(tokenInChain: ApiChain, tokenOutChain: ApiChain, swapVersion: ApiSwapVersion) {
  return swapVersion === 3 && tokenInChain === 'ton' && tokenOutChain === 'ton';
}
