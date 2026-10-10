import type { AgentApiChain, AgentAssetSelector } from './protocol/types';
import type { AgentV2HostAccount, AgentV2HostAsset, AgentV2HostPosition } from './types';
import type { WalletQueryMaterializationDependencies } from './walletQueryTypes';

export function resolveRequestedAsset(
  account: AgentV2HostAccount,
  selectors: AgentAssetSelector[],
  chains: AgentApiChain[],
) {
  return account.holdings.map(({ asset }) => asset)
    .find((asset) => (
      (!chains.length || chains.includes(asset.chain))
      && selectors.some((selector) => matchesSelector(asset, selector))
    ));
}

export function matchesAsset(asset: AgentV2HostAsset, chains: AgentApiChain[], selectors: AgentAssetSelector[]) {
  return (!chains.length || chains.includes(asset.chain))
    && (!selectors.length || selectors.some((selector) => matchesSelector(asset, selector)));
}

export function matchesPosition(
  position: AgentV2HostPosition,
  chains: AgentApiChain[],
  selectors: AgentAssetSelector[],
) {
  return (!chains.length || chains.includes(position.chain))
    && (!selectors.length || Boolean(position.asset
      && selectors.some((selector) => matchesSelector(position.asset!, selector))));
}

export function matchesSelector(
  asset: Pick<AgentV2HostAsset, 'chain' | 'slug' | 'symbol' | 'tokenAddress'>,
  selector: AgentAssetSelector,
) {
  return (!selector.slug || selector.slug === asset.slug)
    && (!selector.chain || selector.chain === asset.chain)
    && (!selector.tokenAddress || selector.tokenAddress === asset.tokenAddress)
    && (!selector.symbol || symbolKey(selector.symbol) === symbolKey(asset.symbol));
}

// Tether writes its tickers with `₮` (USD₮), while users and the agent write T (USDT)
function symbolKey(symbol: string) {
  return symbol.normalize('NFKC').replace(/₮/gu, 'T').toLocaleUpperCase('en-US');
}

export function resolveAsset(
  dependencies: WalletQueryMaterializationDependencies,
  account: AgentV2HostAccount,
  slug: string,
) {
  return dependencies.getTokenBySlug?.(slug)
    ?? account.holdings.find(({ asset }) => asset.slug === slug)?.asset
    ?? dependencies.session.snapshot().host?.assetCatalog?.find((asset) => asset.slug === slug);
}

export function assetKey(asset?: { chain: string; slug: string; tokenAddress?: string }) {
  return asset ? `${asset.chain}\0${asset.slug}\0${asset.tokenAddress ?? ''}` : '';
}
