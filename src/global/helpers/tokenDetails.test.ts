import type { TokenDetailsState, UserToken } from '../types';

import { MINUTE } from '../../util/dateFormat';
import { pickTokenDetailsSlugsToPreload } from './tokenDetails';

const NOW = 1_800_000_000_000;

function makeTokens(count: number): UserToken[] {
  return Array.from({ length: count }, (_, index) => ({ slug: `token${index}` } as UserToken));
}

describe('pickTokenDetailsSlugsToPreload', () => {
  it('takes the top 50 tokens of the visible list', () => {
    const tokens = [{ slug: 'hidden', isDisabled: true } as UserToken, ...makeTokens(60)];

    const slugs = pickTokenDetailsSlugsToPreload(tokens, {}, 'en', NOW);

    expect(slugs).toHaveLength(50);
    expect(slugs).not.toContain('hidden');
    expect(slugs[0]).toBe('token0');
    expect(slugs[49]).toBe('token49');
  });

  it('skips only the details that are fresh and in the current language', () => {
    const detailsBySlug: Record<string, TokenDetailsState> = {
      token0: { langCode: 'en', fetchedAt: NOW - MINUTE },
      token1: { langCode: 'en', fetchedAt: NOW - 20 * MINUTE },
      token2: { langCode: 'ru', fetchedAt: NOW - MINUTE },
      token3: { hasError: true },
    };

    expect(pickTokenDetailsSlugsToPreload(makeTokens(4), detailsBySlug, 'en', NOW))
      .toEqual(['token1', 'token2', 'token3']);
  });
});
