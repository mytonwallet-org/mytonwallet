import type { ApiPerpsMarketAsset, ApiPerpsMarketSection, ApiToken } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';
import type { MarketSection, MarketToken } from '../../market/helpers/buildMarketSections';

import { formatCurrency } from '../../../util/formatNumber';
import { getPerpsAssetName, PERPS_CURRENCY_SYMBOL } from './formatPerps';

export const MOVERS_SECTION_ID = 'movers';
export const POSITIONS_SECTION_ID = 'positions';
export const POSITIONS_PREVIEW_LIMIT = 5;

const MOVERS_TITLE_KEY = 'Today\'s Movers';

/**
 * Builds the Futures showcase from the sections the backend curates. Delisted markets drop out, and a section left
 * without markets is skipped.
 */
export function buildPerpsSections(
  lang: LangFn,
  marketSections: ApiPerpsMarketSection[],
  isPortrait?: boolean,
): MarketSection[] {
  return marketSections
    .map(({
      id, title, layout, limit, desktopLimit, mobileLimit, hasMore, assets: sectionAssets,
    }) => {
      const isLargeHorizontalLayout = layout === 'largeHorizontal';
      const tokens = sectionAssets
        .filter(isListedAsset)
        .map((asset) => buildPerpsMarketToken(asset, isLargeHorizontalLayout));
      // Zero or a negative limit means no limit, as on iOS
      const backendLimit = (isPortrait ? mobileLimit : desktopLimit) ?? limit;
      const visibleLimit = backendLimit !== undefined && backendLimit > 0 ? backendLimit : undefined;

      return {
        id,
        // The backend sends the Movers section without a title
        title: title || (id === MOVERS_SECTION_ID ? lang(MOVERS_TITLE_KEY) : ''),
        layout,
        visibleLimit,
        hasMore: hasMore || (visibleLimit !== undefined && tokens.length > visibleLimit),
        tokens,
      };
    })
    .filter(({ tokens }) => tokens.length);
}

export function buildPerpsMarketToken(asset: ApiPerpsMarketAsset, withSparkline?: boolean): MarketToken {
  const token = buildPerpsToken(asset);

  return {
    slug: asset.id,
    token,
    name: token.name,
    priceText: formatCurrency(asset.context.markPx, PERPS_CURRENCY_SYMBOL),
    change: asset.context.percentChange24h,
    withChainIcon: false,
    sparkline: withSparkline ? asset.sparkline : undefined,
    tintColor: asset.tintColor,
  };
}

// `TokenIcon` needs an `ApiToken`. The screens never format coin amounts with it, so `decimals` stays zero.
export function buildPerpsToken(asset: Pick<ApiPerpsMarketAsset, 'id' | 'symbol' | 'chain'>
  & Partial<Pick<ApiPerpsMarketAsset, 'displayName' | 'label' | 'keywords' | 'image'>>): ApiToken {
  return {
    slug: asset.id,
    name: getPerpsAssetName(asset),
    symbol: asset.symbol,
    chain: asset.chain,
    image: asset.image ?? undefined,
    label: asset.label,
    keywords: asset.keywords,
    decimals: 0,
  };
}

export function isListedAsset(asset: ApiPerpsMarketAsset) {
  return !asset.isDelisted;
}
