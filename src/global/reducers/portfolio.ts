import type { ApiBaseCurrency, ApiPriceHistoryPeriod } from '../../api/types';
import type {
  GlobalState, PortfolioHistoryBundle, PortfolioHistoryByAccountId, PortfolioPnlChange, PortfolioState,
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

export function updatePnlChangeByAccountId(
  byAccountId: Record<string, PortfolioPnlChange> | undefined,
  accountId: string,
  pnlChange?: PortfolioPnlChange,
): Record<string, PortfolioPnlChange> {
  if (!pnlChange) {
    if (!byAccountId?.[accountId]) return byAccountId ?? {};

    const next = { ...byAccountId };
    delete next[accountId];
    return next;
  }

  return { ...byAccountId, [accountId]: pnlChange };
}
