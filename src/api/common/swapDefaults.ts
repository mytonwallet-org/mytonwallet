import type { ApiSwapDefaults, ApiSwapDefaultsRequest, ApiToken } from '../types';

import { getChainConfig } from '../../util/chain';

export function resolveSwapDefaults(request: ApiSwapDefaultsRequest): ApiSwapDefaults {
  const { tokenOut, accountChains, network, balancesUsdBySlug } = request;
  let tokenIn = request.tokenIn;
  if (tokenIn && tokenOut) return { tokenIn, tokenOut };

  const defaultChain = tokenIn?.chain ?? tokenOut?.chain ?? accountChains[0];
  if (!defaultChain) return { tokenIn, tokenOut };

  const chains = [...new Set([...accountChains, defaultChain])];
  const configs = chains.map(getChainConfig);
  const stableSlugs = new Set(configs.flatMap((config) => [config.usdtSlug[network], config.usdcSlug?.[network]])
    .filter(Boolean));
  const isNative = (token: ApiToken) => token.slug === getChainConfig(token.chain).nativeToken.slug;
  const isStable = (token: ApiToken) => stableSlugs.has(token.slug);

  const ranked = configs.flatMap((config) => config.tokenInfo)
    .filter((token) => isNative(token) || isStable(token))
    .map((token) => ({
      token,
      balanceUsd: accountChains.includes(token.chain) ? balancesUsdBySlug[token.slug] ?? 0 : 0,
    }))
    .sort((a, b) => b.balanceUsd - a.balanceUsd);

  if (!tokenIn && !tokenOut) {
    const funded = ranked.filter((item) => item.balanceUsd > 0);
    tokenIn = funded[0]?.token ?? getChainConfig(defaultChain).nativeToken;
    if (funded[1]) return { tokenIn, tokenOut: funded[1].token };
  }

  const fixedToken = (tokenIn ?? tokenOut)!;
  const candidates = [
    ...ranked.filter(({ token }) => token.chain === fixedToken.chain && isStable(token) && !isStable(fixedToken)),
    ...ranked.filter(({ token }) => token.chain === fixedToken.chain && isNative(token) && !isNative(fixedToken)),
    ...ranked.filter(({ token }) => token.chain !== fixedToken.chain && isStable(token)),
    ...ranked.filter(({ token }) => token.chain !== fixedToken.chain && isNative(token)),
  ];
  const opposite = (tokenIn ? candidates[0] : candidates.find((item) => item.balanceUsd > 0) ?? candidates[0])?.token;

  return { tokenIn: tokenIn ?? opposite, tokenOut: tokenOut ?? opposite };
}
