import type { ApiSwapAsset, ApiTokenWithPrice, ApiTransaction } from '../../api/types';

import { TINY_TRANSFER_MAX_COST, TONCOIN } from '../../config';
import { isScamTransaction } from '../../util/activities';
import { toBig } from '../../util/decimals';

export function getIsTinyOrScamTransaction(transaction: ApiTransaction, token?: ApiTokenWithPrice) {
  if (isScamTransaction(transaction)) return true;
  if (!token || transaction.nft) return false;

  const isOutgoingBouncedSpam = transaction.type === 'bounced' && !transaction.isIncoming;

  if (transaction.type && !isOutgoingBouncedSpam) return false;

  const cost = toBig(transaction.amount, token.decimals).abs().mul(token.priceUsd ?? 0);
  return cost.lt(TINY_TRANSFER_MAX_COST);
}

export function resolveSwapAssetId(asset: ApiSwapAsset) {
  return asset.slug === TONCOIN.slug ? asset.symbol : (asset.tokenAddress ?? asset.slug);
}

export function resolveSwapAsset(
  bySlug: Record<string, ApiSwapAsset> | Record<string, ApiTokenWithPrice>,
  anyId: string,
) {
  return bySlug[anyId] ?? Object.values(bySlug).find(({ tokenAddress }) => tokenAddress === anyId);
}
