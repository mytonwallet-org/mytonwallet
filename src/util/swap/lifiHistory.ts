import type { ApiSwapActivity, ApiSwapAsset, ApiTokenWithPrice } from '../../api/types';

/** LI.FI can settle into a different token that is not yet in our asset catalogue. */
export function getLifiReceivedToken(
  activity: ApiSwapActivity,
  catalogToken?: ApiSwapAsset | ApiTokenWithPrice,
): ApiSwapAsset | ApiTokenWithPrice | undefined {
  if (catalogToken) return catalogToken;
  const received = activity.lifi?.received;
  if (!received) return undefined;

  return {
    name: received.symbol || 'Token',
    symbol: received.symbol || 'Token',
    chain: received.chain,
    slug: activity.to,
    decimals: received.decimals,
    isPopular: false,
    priceUsd: 0,
    tokenAddress: received.tokenAddress,
  };
}
