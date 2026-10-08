import type { TradeDirection } from '../../../global/types';
import type { TokenType } from '../../../util/tokenSearch';

export type TradeCategory = 'all' | 'fiat' | 'stablecoins' | 'tokens';

export const TRADE_CATEGORIES: { value: TradeCategory; title: string }[] = [
  { value: 'all', title: 'All' },
  { value: 'fiat', title: 'Fiat' },
  { value: 'stablecoins', title: 'Stablecoins' },
  { value: 'tokens', title: 'Tokens' },
];

/** "Pay With" lists the owned tokens only, and the category tabs appear once there are more than this many */
export const MIN_OWNED_TOKENS_FOR_CATEGORIES = 5;

interface BuildTradeSectionsInput<T extends TokenType> {
  direction: TradeDirection;
  category: TradeCategory;
  /** The token being bought or sold, which cannot be its own counterpart */
  screenTokenSlug?: string;
  /** The account tokens; those without a balance are left out */
  userTokens: T[];
  /** The popular swap tokens, or every match when searching */
  popularTokens: T[];
  /** Every swap token, the source of the stablecoin section, or every match when searching */
  swapTokens: T[];
  isStablecoin: (slug: string) => boolean;
  /** The lists are search matches: every match is listed, in the order of the search ranking */
  isSearch?: boolean;
}

interface TradeSections<T extends TokenType> {
  my: T[];
  stablecoins: T[];
  tokens: T[];
}

/**
 * Groups the Buy / Sell asset picker. "You Receive" (selling) lists the owned tokens, then the stablecoins,
 * then the popular tokens; "Pay With" (buying) lists only the owned tokens. The owned tokens go by value,
 * the rest by name.
 *
 * On the "Stablecoins" tab the owned group shrinks to stablecoins and the rest are listed separately.
 * On the "Tokens" tab the popular group includes stablecoins instead of a separate section.
 */
export function buildTradeSections<T extends TokenType>({
  direction,
  category,
  screenTokenSlug,
  userTokens,
  popularTokens,
  swapTokens,
  isStablecoin,
  isSearch,
}: BuildTradeSectionsInput<T>): TradeSections<T> {
  const byName = (a: T, b: T) => a.name.localeCompare(b.name);
  const owned = userTokens.filter((token) => token.amount > 0n && token.slug !== screenTokenSlug);
  if (!isSearch) {
    owned.sort((a, b) => Number(b.totalValue) - Number(a.totalValue) || byName(a, b));
  }

  const excludedSlugs = new Set(owned.map((token) => token.slug));
  if (screenTokenSlug) {
    excludedSlugs.add(screenTokenSlug);
  }

  const my = category === 'fiat'
    ? []
    : category === 'stablecoins'
      ? owned.filter((token) => isStablecoin(token.slug))
      : owned;

  if (direction === 'buy') {
    return { my, stablecoins: [], tokens: [] };
  }

  const stablecoins = category === 'all' || category === 'stablecoins'
    ? swapTokens.filter((token) => isStablecoin(token.slug) && !excludedSlugs.has(token.slug))
    : [];
  const tokens = category === 'all' || category === 'tokens'
    ? popularTokens.filter((token) => (
      !excludedSlugs.has(token.slug) && (category === 'tokens' || !isStablecoin(token.slug))
    ))
    : [];
  if (!isSearch) {
    stablecoins.sort(byName);
    tokens.sort(byName);
  }

  return { my, stablecoins, tokens };
}
