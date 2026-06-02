import type { ApiBaseCurrency, ApiPriceHistoryPeriod } from '../../api/types';
import type {
  GlobalState, PortfolioHistoryBundle, PortfolioHistoryByAccountId, PortfolioNetChange, PortfolioState,
} from '../types';

export function updatePortfolio(global: GlobalState, partial: Partial<PortfolioState>): GlobalState {
  return {
    ...global,
    portfolio: {
      ...global.portfolio,
      ...partial,
    },
  };
}

export function updateHistoryBundle(
  slice: PortfolioHistoryByAccountId,
  accountId: string,
  baseCurrency: ApiBaseCurrency,
  range: ApiPriceHistoryPeriod,
  bundle: PortfolioHistoryBundle,
): PortfolioHistoryByAccountId {
  const byAccount = slice[accountId] ?? {};
  const byCurrency = byAccount[baseCurrency] ?? {};

  return {
    ...slice,
    [accountId]: {
      ...byAccount,
      [baseCurrency]: {
        ...byCurrency,
        [range]: bundle,
      },
    },
  };
}

export function updateNetChangeByAccountId(
  byAccountId: Record<string, PortfolioNetChange> | undefined,
  accountId: string,
  netChange?: PortfolioNetChange,
): Record<string, PortfolioNetChange> {
  if (!netChange) {
    if (!byAccountId?.[accountId]) return byAccountId ?? {};

    const next = { ...byAccountId };
    delete next[accountId];
    return next;
  }

  return { ...byAccountId, [accountId]: netChange };
}
