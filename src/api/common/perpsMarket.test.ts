import type { ApiPerpsGetAssetsResult, ApiPerpsMarketAsset, ApiPerpsMarketSection } from '../types';

import { buildPerpsMarketCatalogue } from './perpsMarket';

const asset = {
  id: 'hyperliquid:xyz:NVDA', name: 'xyz:NVDA', symbol: 'NVDA', dex: 'xyz',
  index: 5, wireAssetIndex: 110005,
  szDecimals: 3, maxLeverage: 10, context: { markPx: '100', prevDayPx: '99' },
} as ApiPerpsMarketAsset;
const section: ApiPerpsMarketSection = {
  id: 'stocks', title: 'سهام توکن‌شده', layout: 'grid', mobileLimit: 8, desktopLimit: 12,
  hasMore: false, assets: [{ ...asset, displayName: 'NVIDIA', keywords: ['rwa', 'stock'], tintColor: '#76B900' }],
};
const limitsByChain = {
  hyperliquid: { minOpenDepositUsdc: '10.2', minIncreaseDepositUsdc: '0.2', minPositionMarginUsdc: '10' },
};

test('section metadata does not overwrite canonical price, precision, book or wire coin', () => {
  const response: ApiPerpsGetAssetsResult = {
    assetsByChain: { hyperliquid: [asset] },
    sections: [{ ...section, assets: [{ ...section.assets[0], name: 'NVIDIA', dex: '', szDecimals: 9, wireAssetIndex: 0,
      context: { ...asset.context, markPx: '1' } }] }],
    limitsByChain,
  };
  const result = buildPerpsMarketCatalogue(response);
  expect(result.sections[0]).toMatchObject({ id: 'stocks', title: section.title, mobileLimit: 8, layout: 'grid' });
  expect(result.assets[0]).toMatchObject({
    ...asset, displayName: 'NVIDIA', keywords: ['rwa', 'stock'], tintColor: '#76B900',
  });
  expect(result.sections[0].assets[0]).toBe(result.assets[0]);
  expect(response.assetsByChain.hyperliquid?.[0].name).toBe('xyz:NVDA');
  expect(response.assetsByChain.hyperliquid?.[0]).not.toHaveProperty('displayName');
});

test('catalogue tint survives sections without color metadata', () => {
  const colored = { ...asset, tintColor: '#208D80' };
  const response = { assetsByChain: { hyperliquid: [colored] }, sections: [], limitsByChain };
  expect(buildPerpsMarketCatalogue(response).assets[0].tintColor).toBe('#208D80');
  const result = buildPerpsMarketCatalogue({ ...response, sections: [{ ...section, assets: [asset] }] });
  expect(result.sections[0].assets[0].tintColor).toBe('#208D80');
});

test('unknown, duplicate, delisted and unsupported section entries are removed without losing catalogue assets', () => {
  const delisted = { ...asset, id: 'delisted', isDelisted: true };
  const result = buildPerpsMarketCatalogue({
    assetsByChain: { hyperliquid: [asset, delisted] },
    sections: [
      { ...section, assets: [asset, asset, { ...asset, id: 'unknown' }, delisted] },
      section,
      { ...section, id: 'future-layout', layout: 'new-layout' as any },
      { ...section, id: 'empty', assets: [] },
    ],
    limitsByChain,
  });
  expect(result.sections.map((value) => value.id)).toEqual(['stocks']);
  expect(result.sections[0].assets.map((value) => value.id)).toEqual([asset.id]);
  expect(result.assets).toHaveLength(2);
});
