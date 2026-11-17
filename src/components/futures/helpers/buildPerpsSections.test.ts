import type { ApiPerpsMarketAsset, ApiPerpsMarketSection } from '../../../api/types';
import type { LangFn } from '../../../util/langProvider';

import { buildPerpsSections, MOVERS_SECTION_ID } from './buildPerpsSections';

const lang = ((key: string) => key) as LangFn;

const BTC = buildAsset({ id: 'hyperliquid:hl:BTC', symbol: 'BTC', displayName: 'Bitcoin' });
const ETH = buildAsset({ id: 'hyperliquid:hl:ETH', symbol: 'ETH' });
const SOL = buildAsset({ id: 'hyperliquid:hl:SOL', symbol: 'SOL', isDelisted: true });
const TSLA = buildAsset({ id: 'hyperliquid:xyz:TSLA', symbol: 'TSLA', dex: 'xyz' });

describe('buildPerpsSections', () => {
  it('keeps the backend sections in their order without delisted markets and empty sections', () => {
    const sections = buildPerpsSections(lang, [
      buildSection({ id: 'popular', layout: 'grid', assets: [ETH, SOL] }),
      buildSection({ id: 'stocks', layout: 'rows', assets: [TSLA] }),
      buildSection({ id: 'gone', layout: 'rows', assets: [SOL] }),
    ]);

    expect(sections.map(({ id }) => id)).toEqual(['popular', 'stocks']);
    expect(sections[0].tokens.map(({ slug }) => slug)).toEqual([ETH.id]);
  });

  it('titles the movers itself and gives sparklines to the large cards only', () => {
    const [movers, popular] = buildPerpsSections(lang, [
      buildSection({ id: MOVERS_SECTION_ID, title: '', layout: 'largeHorizontal', assets: [BTC] }),
      buildSection({ id: 'popular', layout: 'grid', assets: [BTC] }),
    ]);

    expect(movers.title).toBe('Today\'s Movers');
    expect(movers.tokens[0].sparkline).toBe(BTC.sparkline);
    expect(popular.tokens[0].sparkline).toBeUndefined();
  });

  it('takes the preview size of the layout and offers See All when markets do not fit', () => {
    const section = buildSection({
      id: 'popular', layout: 'grid', assets: [BTC, ETH], mobileLimit: 1, desktopLimit: 2,
    });

    const [portrait] = buildPerpsSections(lang, [section], true);
    const [landscape] = buildPerpsSections(lang, [section], false);

    expect(portrait).toMatchObject({ visibleLimit: 1, hasMore: true });
    expect(landscape).toMatchObject({ visibleLimit: 2, hasMore: false });
  });

  it('shows nothing for an empty list of sections', () => {
    expect(buildPerpsSections(lang, [])).toEqual([]);
  });

  it('names the market after its curated name and shows the change from the catalogue', () => {
    const [section] = buildPerpsSections(lang, [
      buildSection({ id: 'all', layout: 'rows', assets: [BTC, ETH] }),
    ]);

    expect(section.tokens.map(({ name }) => name)).toEqual(['Bitcoin', 'ETH']);
    expect(section.tokens[0].change).toBe(-1.5);
  });
});

function buildAsset({
  id, symbol, displayName, dex = '', isDelisted,
}: {
  id: string;
  symbol: string;
  displayName?: string;
  dex?: string;
  isDelisted?: boolean;
}): ApiPerpsMarketAsset {
  return {
    id,
    index: 0,
    name: dex ? `${dex}:${symbol}` : symbol,
    chain: 'hyperliquid',
    provider: 'hyperliquid',
    dex,
    symbol,
    displayName,
    // eslint-disable-next-line no-null/no-null
    image: null,
    szDecimals: 5,
    maxLeverage: 40,
    isDelisted,
    sparkline: [1, 2, 3],
    context: {
      percentChange24h: -1.5,
      funding: '0.0000125',
      openInterest: '1',
      prevDayPx: '100',
      dayNtlVlm: '1',
      premium: '0',
      oraclePx: '98.5',
      markPx: '98.5',
      // eslint-disable-next-line no-null/no-null
      midPx: null,
      // eslint-disable-next-line no-null/no-null
      impactPxs: null,
      dayBaseVlm: '1',
    },
  };
}

function buildSection(section: Pick<ApiPerpsMarketSection, 'id' | 'layout' | 'assets'>
  & Partial<Pick<ApiPerpsMarketSection, 'title' | 'mobileLimit' | 'desktopLimit'>>): ApiPerpsMarketSection {
  return { title: section.id, hasMore: false, ...section };
}
