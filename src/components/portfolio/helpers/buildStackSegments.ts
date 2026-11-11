import type { ApiBaseCurrency, ApiChain } from '../../../api/types';
import type { UserToken } from '../../../global/types';
import type { LangFn } from '../../../hooks/useLang';

import { getChainConfig, getChainTitle, getStablecoinSlugs } from '../../../util/chain';
import { toBig } from '../../../util/decimals';
import { formatCurrency, getShortCurrencySymbol } from '../../../util/formatNumber';
import { clamp } from '../../../util/math';
import { getIsNativeToken } from '../../../util/tokens';

const TOKEN_TYPE_COLORS = {
  native: '#2C92F0',
  stablecoins: '#E49329',
  altcoins: '#10B853',
} as const;

const MAX_CHAIN_SEGMENTS = 10;
const OTHER_CHAINS_COLOR = '#8E8E93';

const STAKED_COLORS = {
  staked: '#6875E9',
  notStaked: '#2C92F0',
} as const;

export type PortfolioStackSegment = {
  id: string;
  title: string;
  value: string;
  rawAmount: number;
  colorHex: string;
};

type TokenKind = 'native' | 'stablecoins' | 'altcoins';

export function buildSegmentsByTokenKind(
  lang: LangFn,
  tokens: UserToken[],
  baseCurrency: ApiBaseCurrency,
) {
  const stablecoinSlugs = getStablecoinSlugs();
  const totals: Record<TokenKind, number> = { native: 0, stablecoins: 0, altcoins: 0 };

  for (const token of tokens) {
    const value = getTokenValue(token);
    if (value <= 0) continue;

    if (getIsNativeToken(token.slug)) {
      totals.native += value;
    } else if (stablecoinSlugs.has(token.slug)) {
      totals.stablecoins += value;
    } else {
      totals.altcoins += value;
    }
  }

  const shortSymbol = getShortCurrencySymbol(baseCurrency);
  const segments: PortfolioStackSegment[] = [];

  if (totals.native > 0) {
    segments.push({
      id: 'native',
      title: lang('Native'),
      rawAmount: totals.native,
      colorHex: TOKEN_TYPE_COLORS.native,
      value: formatCurrency(totals.native, shortSymbol),
    });
  }
  if (totals.stablecoins > 0) {
    segments.push({
      id: 'stablecoins',
      title: lang('Stablecoins'),
      rawAmount: totals.stablecoins,
      colorHex: TOKEN_TYPE_COLORS.stablecoins,
      value: formatCurrency(totals.stablecoins, shortSymbol),
    });
  }
  if (totals.altcoins > 0) {
    segments.push({
      id: 'altcoins',
      title: lang('Altcoins'),
      rawAmount: totals.altcoins,
      colorHex: TOKEN_TYPE_COLORS.altcoins,
      value: formatCurrency(totals.altcoins, shortSymbol),
    });
  }

  return sortBottomHeavy(segments);
}

export function buildSegmentsByChain(
  lang: LangFn,
  tokens: UserToken[],
  baseCurrency: ApiBaseCurrency,
) {
  const totalsByChain = new Map<ApiChain, number>();

  for (const token of tokens) {
    const value = getTokenValue(token);
    if (value <= 0) continue;

    totalsByChain.set(token.chain, (totalsByChain.get(token.chain) ?? 0) + value);
  }

  const shortSymbol = getShortCurrencySymbol(baseCurrency);
  const result: PortfolioStackSegment[] = [];

  for (const [chain, rawAmount] of totalsByChain) {
    if (rawAmount <= 0) continue;

    result.push({
      id: chain,
      title: getChainTitle(chain),
      rawAmount,
      colorHex: getChainConfig(chain).displayColor,
      value: formatCurrency(rawAmount, shortSymbol),
    });
  }

  const sorted = sortBottomHeavy(result);
  if (sorted.length <= MAX_CHAIN_SEGMENTS) return sorted;

  const topChains = sorted.slice(-(MAX_CHAIN_SEGMENTS - 1));
  const otherAmount = sorted
    .slice(0, sorted.length - topChains.length)
    .reduce((sum, segment) => sum + segment.rawAmount, 0);

  // "Other" stays on top regardless of its amount, as in the iOS and Android apps
  return [
    {
      id: 'other',
      title: lang('$portfolio_other_chains'),
      rawAmount: otherAmount,
      colorHex: OTHER_CHAINS_COLOR,
      value: formatCurrency(otherAmount, shortSymbol),
    },
    ...topChains,
  ];
}

export function buildSegmentsByStacked(
  lang: LangFn,
  totalAmount: number,
  stakedAmount: number,
  baseCurrency: ApiBaseCurrency,
) {
  const shortSymbol = getShortCurrencySymbol(baseCurrency);
  // `totalAmount` and `stakedAmount` come from different price sources, so clamp to keep the bar within 100%
  const clampedStaked = clamp(stakedAmount, 0, totalAmount);
  const notStakedAmount = Math.max(totalAmount - clampedStaked, 0);

  const segments: PortfolioStackSegment[] = [];
  if (clampedStaked > 0) {
    segments.push({
      id: 'staked',
      title: lang('Staked'),
      rawAmount: clampedStaked,
      colorHex: STAKED_COLORS.staked,
      value: formatCurrency(clampedStaked, shortSymbol),
    });
  }

  if (notStakedAmount > 0) {
    segments.push({
      id: 'notStaked',
      title: lang('Not staked'),
      rawAmount: notStakedAmount,
      colorHex: STAKED_COLORS.notStaked,
      value: formatCurrency(notStakedAmount, shortSymbol),
    });
  }

  return sortBottomHeavy(segments);
}

// Ascending by amount so the chart stacks the largest segment at the bottom (smallest on top)
function sortBottomHeavy(segments: PortfolioStackSegment[]) {
  return segments.sort((a, b) => a.rawAmount - b.rawAmount);
}

function getTokenValue(token: UserToken): number {
  if (token.totalValue) {
    const parsed = Number(token.totalValue);
    if (!Number.isNaN(parsed)) return parsed;
  }

  return toBig(token.amount, token.decimals).mul(token.price).toNumber();
}
