import type { ApiToken } from '../../../api/types';
import type { UserToken } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';

import { ARBITRUM_USDC_MAINNET, TONCOIN } from '../../../config';
import { CHAIN_ORDER } from '../../../util/chain';
import { buildSegmentsByChain, buildSegmentsByTokenKind } from './buildStackSegments';

const lang = ((key: string) => key) as LangFn;

describe('buildSegmentsByTokenKind', () => {
  it('classifies configured stablecoins independently of price and excludes lookalikes', () => {
    const tokens = [
      buildAssetToken(TONCOIN, 10),
      buildAssetToken(ARBITRUM_USDC_MAINNET, 20, 0.8),
      buildAssetToken({ ...ARBITRUM_USDC_MAINNET, slug: 'arbitrum-unlisted-usdc' }, 30),
      buildAssetToken({ ...ARBITRUM_USDC_MAINNET, slug: 'arbitrum-other', symbol: 'OTHER' }, 40),
    ];

    const segments = buildSegmentsByTokenKind(lang, tokens, 'USD');

    expect(segments.map(({ id, rawAmount }) => ({ id, rawAmount }))).toEqual([
      { id: 'native', rawAmount: 10 },
      { id: 'stablecoins', rawAmount: 20 },
      { id: 'altcoins', rawAmount: 70 },
    ]);
  });
});

describe('buildSegmentsByChain', () => {
  it('keeps the top 9 chains and collapses the rest into "Other"', () => {
    const chains = CHAIN_ORDER.slice(0, 12);
    const tokens = chains.map((chain, index) => buildToken(chain, index + 1));

    const segments = buildSegmentsByChain(lang, tokens, 'USD');

    expect(segments).toHaveLength(10);
    expect(segments[0]).toMatchObject({ id: 'other', rawAmount: 1 + 2 + 3 });
    expect(segments.slice(1).map((s) => s.id)).toEqual(chains.slice(3));
  });

  it('shows every chain when there are at most 10', () => {
    const tokens = CHAIN_ORDER.slice(0, 10).map((chain, index) => buildToken(chain, index + 1));

    const segments = buildSegmentsByChain(lang, tokens, 'USD');

    expect(segments).toHaveLength(10);
    expect(segments.some((s) => s.id === 'other')).toBe(false);
  });
});

function buildToken(chain: UserToken['chain'], totalValue: number) {
  return { chain, totalValue: String(totalValue) } as UserToken;
}

function buildAssetToken(token: ApiToken, totalValue: number, priceUsd = 1): UserToken {
  return {
    ...token,
    amount: 1000000n,
    price: priceUsd,
    priceUsd,
    change24h: 0,
    totalValue: String(totalValue),
  };
}
