import type { ApiStakingState, ApiTokenWithPrice } from '../../../api/types';

import { MYCOIN_MAINNET, TONCOIN } from '../../../config';
import { getStakingTokens } from './useTokenDropdown';

const tokenBySlug = {
  [MYCOIN_MAINNET.slug]: { slug: MYCOIN_MAINNET.slug } as ApiTokenWithPrice,
  [TONCOIN.slug]: { slug: TONCOIN.slug } as ApiTokenWithPrice,
};

const activeMyState = {
  id: 'my-1', type: 'jetton', tokenSlug: MYCOIN_MAINNET.slug, balance: 1n,
} as unknown as ApiStakingState;
const tonState = {
  id: 'ton-1', type: 'liquid', tokenSlug: TONCOIN.slug, balance: 0n,
} as unknown as ApiStakingState;

function getTokenIds(...args: Parameters<typeof getStakingTokens>) {
  return getStakingTokens(...args).map((token) => token.id);
}

describe('getStakingTokens', () => {
  it('keeps an active blocked position selectable in the info view even when it is not selected', () => {
    // Viewing the TON position; the active MY position must stay navigable in the dropdown
    expect(getTokenIds(tokenBySlug, [activeMyState, tonState], undefined, 'ton-1', true)).toContain('my-1');
  });

  it('excludes a blocked token from the new-stake form when it is not selected', () => {
    const ids = getTokenIds(tokenBySlug, [activeMyState, tonState], undefined, 'ton-1');
    expect(ids).not.toContain('my-1');
    expect(ids).toContain('ton-1');
  });

  it('keeps a blocked token when it is the currently selected position', () => {
    expect(getTokenIds(tokenBySlug, [activeMyState, tonState], undefined, 'my-1')).toContain('my-1');
  });
});
