import type { ApiToken } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';
import type { BuildOptions, MarketToken } from './buildMarketSections';

import { buildStoredMarketToken } from './buildMarketSections';

const MAX_RESULTS = 20;

/**
 * Searches the whole token catalogue rather than the showcase. The showcase holds a few dozen
 * positions, so a query for a token missing from it would otherwise return nothing.
 */
export function searchTokens(lang: LangFn, query: string, options: BuildOptions): MarketToken[] {
  return findMatches(Object.values(options.tokenBySlug), query, (token) => token)
    .map((token) => buildStoredMarketToken(lang, token, options));
}

export function searchMarketTokens(query: string, tokens: MarketToken[]): MarketToken[] {
  return findMatches(tokens, query, ({ token }) => token);
}

function findMatches<T>(items: T[], query: string, getToken: (item: T) => ApiToken) {
  const normalizedQuery = query.trim().toLowerCase();
  if (!normalizedQuery) {
    return [];
  }

  return items
    .filter((item) => doesTokenMatch(getToken(item), normalizedQuery))
    .sort((left, right) => (
      getMatchRank(getToken(left), normalizedQuery) - getMatchRank(getToken(right), normalizedQuery)
    ))
    .slice(0, MAX_RESULTS);
}

function doesTokenMatch(token: ApiToken, query: string) {
  return token.symbol.toLowerCase().includes(query)
    || token.name.toLowerCase().includes(query)
    || Boolean(token.localizedName?.toLowerCase().includes(query))
    || Boolean(token.keywords?.some((keyword) => keyword.toLowerCase().includes(query)));
}

// An exact ticker is what the user means most often, then a ticker or a name starting with the query
function getMatchRank(token: ApiToken, query: string) {
  const symbol = token.symbol.toLowerCase();

  if (symbol === query) return 0;
  if (symbol.startsWith(query)) return 1;
  if (token.name.toLowerCase().startsWith(query) || token.localizedName?.toLowerCase().startsWith(query)) return 2;

  return 3;
}
