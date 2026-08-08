import type { ApiNft } from '../../api/types';

import { buildNftCollectionIndex, getCollectionKey, getIsNftVisible } from './nfts';

const COLLECTION = 'EQBDMXqg2YcGmMnn5_bXG63y-hh_YNV0dx-ylx-vL3v_WZt4';
const EMPTY_SET: ReadonlySet<string> = new Set();

function makeNft(partial: Partial<ApiNft> = {}): ApiNft {
  return {
    chain: 'ton',
    interface: 'default',
    index: 0,
    address: 'EQAglL_g6q2AhMK_BT9jN1F-8jBlv2pOI30vRkPluU9kcXgV',
    thumbnail: '',
    image: '',
    isOnSale: false,
    metadata: {},
    ...partial,
  };
}

describe('getIsNftVisible', () => {
  it('shows a plain NFT', () => {
    expect(getIsNftVisible(makeNft(), EMPTY_SET, EMPTY_SET, true)).toBe(true);
  });

  it('hides an unverified NFT when the setting is on', () => {
    expect(getIsNftVisible(makeNft({ isUnverified: true }), EMPTY_SET, EMPTY_SET, true)).toBe(false);
  });

  it('shows an unverified NFT when the setting is off', () => {
    expect(getIsNftVisible(makeNft({ isUnverified: true }), EMPTY_SET, EMPTY_SET, false)).toBe(true);
  });

  it('hides an NFT hidden by the anti-scam protection', () => {
    expect(getIsNftVisible(makeNft({ isHidden: true }), EMPTY_SET, EMPTY_SET, true)).toBe(false);
  });

  it('shows a whitelisted NFT regardless of both hiding reasons', () => {
    const nft = makeNft({ isHidden: true, isUnverified: true });
    expect(getIsNftVisible(nft, EMPTY_SET, new Set([nft.address]), true)).toBe(true);
  });

  it('hides a blacklisted NFT even when it is whitelisted', () => {
    const nft = makeNft();
    expect(getIsNftVisible(nft, new Set([nft.address]), new Set([nft.address]), true)).toBe(false);
  });
});

describe('buildNftCollectionIndex', () => {
  it('drops a collection whose NFTs are all unverified', () => {
    const nft = makeNft({ collectionAddress: COLLECTION, isUnverified: true });
    const { byKey, totalVisibleCount } = buildNftCollectionIndex({ [nft.address]: nft }, undefined, undefined, true);

    expect(totalVisibleCount).toBe(0);
    expect(byKey.size).toBe(0);
  });

  it('keeps a collection when at least one of its NFTs is verified', () => {
    const unverified = makeNft({ address: 'unverified', collectionAddress: COLLECTION, isUnverified: true });
    const verified = makeNft({ address: 'verified', collectionAddress: COLLECTION, collectionName: 'Market Makers' });
    const { byKey, totalVisibleCount } = buildNftCollectionIndex(
      { unverified, verified }, undefined, undefined, true,
    );

    expect(totalVisibleCount).toBe(1);
    expect(byKey.get(getCollectionKey('ton', COLLECTION))).toMatchObject({ count: 1, name: 'Market Makers' });
  });
});
