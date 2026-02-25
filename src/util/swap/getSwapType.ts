import type { ApiChain, ApiSwapAsset, ApiTokenWithPrice } from '../../api/types';
import { type Account, SwapType, type UserSwapToken } from '../../global/types';

import { getChainBySlug } from '../tokens';

export function getSwapType(
  tokenInSlug: string,
  tokenOutSlug: string,
  accountChains: Partial<Record<ApiChain, unknown>>,
): SwapType {
  const tokenInChain = getChainBySlug(tokenInSlug);
  const tokenOutChain = getChainBySlug(tokenOutSlug);

  if (isOnChainSwap(tokenInChain, tokenOutChain)) {
    return SwapType.OnChain;
  }

  if (!(tokenInChain in accountChains)) {
    return SwapType.CrosschainToWallet;
  }

  return tokenOutChain in accountChains
    ? SwapType.CrosschainInsideWallet
    : SwapType.CrosschainFromWallet;
}

/** Returns `true` if the swap goes from and to the wallets inside the given account */
export function getIsInternalSwap({
  from,
  to,
  toAddress,
  accountChains,
}: {
  from?: UserSwapToken | ApiSwapAsset | ApiTokenWithPrice;
  to?: UserSwapToken | ApiSwapAsset | ApiTokenWithPrice;
  toAddress?: string;
  accountChains?: Account['byChain'];
}) {
  if (!from || !to) {
    return false;
  }

  const isOnchainSwap = isOnChainSwap(from.chain as ApiChain, to.chain as ApiChain);
  const isInternalCrosschainSwap = !isOnchainSwap
    && !!accountChains
    && !!toAddress
    && from.chain in accountChains
    && accountChains[to.chain as ApiChain]?.address === toAddress;

  return isOnchainSwap || isInternalCrosschainSwap;
}

function isOnChainSwap(tokenInChain: ApiChain, tokenOutChain: ApiChain) {
  return tokenInChain === tokenOutChain && tokenInChain === 'ton';
}
