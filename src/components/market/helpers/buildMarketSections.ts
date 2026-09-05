import type {
  ApiBaseCurrency,
  ApiCurrencyRates,
  ApiMarketAssetsResponseWithSlug,
  ApiMarketAssetWithSlug,
  ApiMarketSectionLayout,
  ApiToken,
  ApiTokenWithPrice,
} from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { calculateTokenPrice } from '../../../util/calculatePrice';
import { formatCurrency, getShortCurrencySymbol } from '../../../util/formatNumber';
import { getTokenName } from '../../../util/tokens';

export interface MarketToken {
  slug: string;
  /** Token from the global store when it is known there, otherwise built from the market response */
  token: ApiToken;
  name: string;
  priceText: string;
  /** Price change over the last 24 hours, in percent */
  change: number;
  sparkline?: number[];
  tintColor?: string;
}

export interface MarketSection {
  id: string;
  title: string;
  layout: ApiMarketSectionLayout;
  hasMore: boolean;
  tokens: MarketToken[];
}

export interface BuildOptions {
  tokenBySlug: Record<string, ApiTokenWithPrice>;
  baseCurrency: ApiBaseCurrency;
  currencyRates: ApiCurrencyRates;
  areTokenNamesLocalized?: boolean;
}

export function buildMarketSections(
  lang: LangFn,
  marketData: ApiMarketAssetsResponseWithSlug,
  options: BuildOptions,
): MarketSection[] {
  return marketData.sections.map((section) => ({
    id: section.id,
    title: section.title,
    layout: section.layout,
    hasMore: section.hasMore,
    tokens: section.assets.map((asset) => buildAssetMarketToken(lang, asset, options)),
  }));
}

export function buildStoredMarketToken(lang: LangFn, token: ApiTokenWithPrice, options: BuildOptions): MarketToken {
  return buildMarketToken(lang, token, token.priceUsd, token.percentChange24h, options);
}

function buildAssetMarketToken(lang: LangFn, asset: ApiMarketAssetWithSlug, options: BuildOptions): MarketToken {
  const storedToken = options.tokenBySlug[asset.slug];

  // Prices in the store are kept fresh by polling, while the market response is a snapshot that can
  // be minutes old. The response only fills in tokens the store does not know about.
  const priceUsd = storedToken?.priceUsd ?? asset.price;
  const change = storedToken?.percentChange24h ?? asset.percentChange24h;

  return {
    ...buildMarketToken(lang, storedToken ?? buildTokenFromAsset(asset), priceUsd, change, options),
    sparkline: asset.sparkline,
    tintColor: asset.tintColor,
  };
}

function buildMarketToken(
  lang: LangFn,
  token: ApiToken,
  priceUsd: number,
  change: number,
  options: BuildOptions,
): MarketToken {
  const { baseCurrency, currencyRates, areTokenNamesLocalized } = options;
  const price = calculateTokenPrice(priceUsd, baseCurrency, currencyRates);

  return {
    slug: token.slug,
    token,
    name: getTokenName(lang, token, areTokenNamesLocalized),
    priceText: formatCurrency(price, getShortCurrencySymbol(baseCurrency)),
    change,
  };
}

// The showcase shows prices only, so `decimals` never takes part in formatting here
function buildTokenFromAsset(asset: ApiMarketAssetWithSlug): ApiToken {
  return {
    slug: asset.slug,
    name: asset.name,
    symbol: asset.symbol,
    chain: asset.chain,
    image: asset.image,
    tokenAddress: asset.tokenAddress,
    label: asset.label,
    decimals: 0,
  };
}
