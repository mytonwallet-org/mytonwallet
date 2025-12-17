import type { ApiTokenWithPrice } from '../../api/types';
import type { GlobalState, PriceHistoryPeriods } from '../types';

import { updateAccountState } from './misc';

export function updateTokenPriceHistory(global: GlobalState, slug: string, partial: PriceHistoryPeriods): GlobalState {
  const { bySlug } = global.tokenPriceHistory;

  return {
    ...global,
    tokenPriceHistory: {
      bySlug: {
        ...bySlug,
        [slug]: {
          ...bySlug[slug],
          ...partial,
        },
      },
    },
  };
}

export function updateTokenNetWorthHistory(
  global: GlobalState,
  accountId: string,
  slug: string,
  partial: PriceHistoryPeriods,
): GlobalState {
  const { byAccountId } = global;
  const accountState = byAccountId[accountId];
  if (!accountState) {
    return global;
  }

  const bySlug = accountState.tokenNetWorthHistory || {};

  return updateAccountState(global, accountId, {
    tokenNetWorthHistory: {
      ...bySlug,
      [slug]: {
        ...bySlug[slug],
        ...partial,
      },
    },
  });
}

export function updateTokenInfo(global: GlobalState, partial: Record<string, ApiTokenWithPrice>): GlobalState {
  return {
    ...global,
    tokenInfo: {
      ...global.tokenInfo,
      bySlug: {
        ...global.tokenInfo.bySlug,
        ...partial,
      },
    },
  };
}
