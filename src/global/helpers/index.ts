import type { ApiChain, ApiSwapAsset, ApiTokenWithPrice, ApiTransaction } from '../../api/types';
import type { Account, UserSwapToken } from '../types';

import { TINY_TRANSFER_MAX_COST, TONCOIN } from '../../config';
import { isScamTransaction } from '../../util/activities';
import { getIsSupportedChain } from '../../util/chain';
import { toBig } from '../../util/decimals';

export function getIsTinyOrScamTransaction(transaction: ApiTransaction, token?: ApiTokenWithPrice) {
  if (isScamTransaction(transaction)) return true;
  if (!token || transaction.nft || transaction.type) return false;

  const cost = toBig(transaction.amount, token.decimals).abs().mul(token.priceUsd ?? 0);
  return cost.lt(TINY_TRANSFER_MAX_COST);
}

export function resolveSwapAssetId(asset: ApiSwapAsset) {
  return asset.slug === TONCOIN.slug ? asset.symbol : (asset.tokenAddress ?? asset.slug);
}

export function resolveSwapAsset(bySlug: Record<string, ApiSwapAsset>, anyId: string) {
  return bySlug[anyId] ?? Object.values(bySlug).find(({ tokenAddress }) => tokenAddress === anyId);
}

export function getIsInternalSwap({
  from,
  to,
  toAddress,
  accountChains,
}: {
  from?: UserSwapToken | ApiSwapAsset;
  to?: UserSwapToken | ApiSwapAsset;
  toAddress?: string;
  accountChains?: Account['byChain'];
}) {
  const isMultichain = Boolean(accountChains?.tron);
  return (from?.chain === 'ton' && to?.chain === 'ton') || (
    isMultichain && from && to && accountChains
    && getIsSupportedChain(from.chain)
    && accountChains[to.chain as ApiChain]?.address === toAddress
  );
}
