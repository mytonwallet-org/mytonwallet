import type { ApiChain } from '../../../../api/types';

import { CHAIN_ORDER, getChainConfig } from '../../../../util/chain';
import { getOnRampProvider } from './onRamp';

const NON_RUBLE_CHAINS = CHAIN_ORDER.filter((chain) => !getChainConfig(chain).canBuyWithCardInRussia);

describe('getOnRampProvider', () => {
  test('routes RUB to the ruble provider only where it can deliver the asset', () => {
    expect(getOnRampProvider('ton', 'RUB')).toBe('avanchange');

    // The ruble provider sells a TON asset, so a RUB request leaking in from any other chain
    // must never build its URL with a foreign-chain address
    for (const chain of NON_RUBLE_CHAINS) {
      expect(getOnRampProvider(chain, 'RUB')).toBe('moonpay');
    }
  });

  test.each(CHAIN_ORDER)('routes non-RUB currencies to Moonpay on %s', (chain: ApiChain) => {
    expect(getOnRampProvider(chain, 'USD')).toBe('moonpay');
    expect(getOnRampProvider(chain, 'EUR')).toBe('moonpay');
  });
});
