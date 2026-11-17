import type { MarketToken } from './buildMarketSections';

import { searchMarketTokens } from './searchTokens';

const BTC = buildToken('BTC', 'Bitcoin');
const WBTC = buildToken('WBTC', 'Wrapped Bitcoin');
const ETH = buildToken('ETH', 'Ethereum');

describe('searchMarketTokens', () => {
  it('finds tokens by the ticker or the name regardless of the case and puts the exact ticker first', () => {
    expect(searchMarketTokens('btc', [WBTC, ETH, BTC])).toEqual([BTC, WBTC]);
    expect(searchMarketTokens('  ETHER ', [WBTC, ETH, BTC])).toEqual([ETH]);
  });

  it('finds nothing for an empty query or an unknown token', () => {
    expect(searchMarketTokens(' ', [BTC])).toEqual([]);
    expect(searchMarketTokens('doge', [BTC, ETH])).toEqual([]);
  });
});

function buildToken(symbol: string, name: string): MarketToken {
  return {
    slug: symbol,
    token: {
      slug: symbol, name, symbol, chain: 'hyperliquid', decimals: 0,
    },
    name,
    priceText: '$1',
    change: 0,
    withChainIcon: false,
  };
}
