import type { GlobalState } from '../../global/types';

import { selectCurrentAccount, selectIsOnRampAllowed } from '../../global/selectors';
import { getChainConfig, getSupportedChains } from '../../util/chain';

const ON_RAMP_PROVIDERS = [
  { id: 'moonpay', name: 'MoonPay' },
  { id: 'avanchange', name: 'Avanchange' },
] as const;

export function buildAgentBuiltinDapps(global: GlobalState): { name: string; url: string }[] {
  const account = selectCurrentAccount(global);
  if (!account || account.type === 'view') return [];

  return getSupportedChains().flatMap((chain) => {
    if (!account.byChain[chain]?.address) return [];
    const { nativeToken } = getChainConfig(chain);
    return ON_RAMP_PROVIDERS.flatMap((provider) => (
      selectIsOnRampAllowed(global, chain, provider.id) ? [{
        name: `Buy ${nativeToken.symbol} (${nativeToken.name}, ${chain}) via ${provider.name}`,
        url: `mtw://buy-with-card?chain=${chain}&provider=${provider.id}`,
      }] : []
    ));
  });
}
