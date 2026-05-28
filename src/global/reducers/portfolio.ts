import type { ApiBaseCurrency, ApiPriceHistoryPeriod } from '../../api/types';
import type {
  GlobalState, PortfolioHistoryBundle, PortfolioHistoryByAccountId, PortfolioState,
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

export function writeHistoryBundle(
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
