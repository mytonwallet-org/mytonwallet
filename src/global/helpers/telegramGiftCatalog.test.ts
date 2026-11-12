import type { ApiNft } from '../../api/types';

import { buildTelegramGiftCatalog } from './telegramGiftCatalog';

function gift(index: number, collectionAddress = 'collection-a', collectionName = 'A'): ApiNft {
  return {
    chain: 'ton', interface: 'default', index, address: `gift-${index}`,
    collectionAddress, collectionName, isTelegramGift: true, isOnSale: false, metadata: {},
  };
}

describe('Telegram gift catalog', () => {
  it.each([0, 1, 999, 1000, 1001, 2501])('counts all %i gifts without truncation', (count) => {
    const result = buildTelegramGiftCatalog(Array.from({ length: count }, (_, index) => gift(index)));
    expect(result.count).toBe(count);
    expect(result.collections.reduce((sum, collection) => sum + collection.count, 0)).toBe(count);
    if (count) expect(result.collections[0].count).toBe(count);
  });

  it('sorts by owned count descending, then name/address; equal names do not merge collections', () => {
    const result = buildTelegramGiftCatalog([
      gift(1, 'b', 'Same'), gift(2, 'a', 'Same'),
      gift(3, 'c', 'Z'), gift(4, 'c', 'Z'),
    ]);
    expect(result.collections.map(({ address, count }) => [address, count])).toEqual([
      ['c', 2], ['a', 1], ['b', 1],
    ]);
  });

  it('deduplicates gifts and excludes other NFTs even with gift-like names', () => {
    const realGift = gift(1);
    expect(buildTelegramGiftCatalog([
      realGift, realGift,
      { ...gift(2), isTelegramGift: false, name: 'Plush Pepe #123' },
      { ...gift(3), chain: 'solana' },
      { ...gift(4), collectionAddress: undefined },
    ]).count).toBe(1);
  });

  it('counts and sorts by all owned gifts while retaining hidden subtotals', () => {
    const nfts = [gift(1, 'large', 'Z'), gift(2, 'large', 'Private label'), gift(3, 'large', 'Private label'),
      gift(4, 'small', 'A'), gift(5, 'small', 'A'), gift(6, 'hidden', 'Private collection')];
    const catalog = buildTelegramGiftCatalog([...nfts, nfts[1]], new Set(['gift-1', 'gift-4', 'gift-5']));
    expect(catalog.count).toBe(6);
    expect(catalog.hiddenCount).toBe(3);
    expect(catalog.collections).toEqual([
      { address: 'large', name: 'Z', count: 3, hiddenCount: 2 },
      { address: 'small', name: 'A', count: 2, hiddenCount: 0 },
      { address: 'hidden', name: undefined, count: 1, hiddenCount: 1 },
    ]);
  });

  it('chooses a stable nonempty visible collection name regardless of page order', () => {
    const nfts = [gift(1, 'a', '  Z  '), gift(2, 'a', 'A'), gift(3, 'a', '  ')];
    expect(buildTelegramGiftCatalog(nfts)).toEqual(buildTelegramGiftCatalog([...nfts].reverse()));
    expect(buildTelegramGiftCatalog(nfts).collections[0].name).toBe('A');
  });
});
