import type { ApiTokenWithPrice } from '../../api/types';
import type { GlobalState, PriceHistoryPeriods, TokenDetailsState } from '../types';

import { updateAccountState } from './misc';

export function updateTokenPriceHistory(global: GlobalState, slug: string, partial: PriceHistoryPeriods): GlobalState {
  const { bySlug } = global.tokenPriceHistory;

  return {
    ...global,
    tokenPriceHistory: {
      ...global.tokenPriceHistory,
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

export function clearTokenPriceHistory(global: GlobalState): GlobalState {
  return {
    ...global,
    tokenPriceHistory: {
      bySlug: {},
      restoredBySlug: {},
    },
  };
}

export function updateTokenDetails(
  global: GlobalState,
  partialBySlug: Record<string, TokenDetailsState>,
): GlobalState {
  const bySlug = { ...global.tokenDetails.bySlug };
  for (const [slug, partial] of Object.entries(partialBySlug)) {
    bySlug[slug] = { ...bySlug[slug], ...partial };
  }

  return {
    ...global,
    tokenDetails: { bySlug },
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
