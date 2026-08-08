import type { ApiBaseCurrency, ApiChain } from '../../../../api/types';

import { getIsRubSupported } from '../../../../util/ramp-currencies';

export type OnRampProvider = 'avanchange' | 'moonpay';

/**
 * The last-mile guard: a RUB request reaching a chain Avanchange cannot serve would build a GRAM purchase URL
 * carrying a foreign-chain address, so the provider is derived from the chain too, not from the currency alone.
 */
export function getOnRampProvider(chain: ApiChain, currency: ApiBaseCurrency): OnRampProvider {
  return currency === 'RUB' && getIsRubSupported(chain) ? 'avanchange' : 'moonpay';
}
