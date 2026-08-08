import type { ApiNft } from '../../api/types';

import { makeMockTransactionActivity } from '../../../tests/mocks';
import { getIsHiddenNftActivity, isScamTransaction } from '.';

const WHITELISTED_ADDRESS = 'EQNft_Whitelisted_0000000000000000000000000000000000000';
const BLACKLISTED_ADDRESS = 'EQNft_Blacklisted_0000000000000000000000000000000000000';
const PLAIN_ADDRESS = 'EQNft_Plain_00000000000000000000000000000000000000000000';

function makeNft(partial: Partial<ApiNft> = {}): ApiNft {
  return {
    chain: 'ton',
    index: 0,
    address: PLAIN_ADDRESS,
    thumbnail: '',
    image: '',
    isOnSale: false,
    metadata: {},
    interface: 'default',
    ...partial,
  };
}

describe('isScamTransaction', () => {
  it('marks a transaction carrying a scam NFT as scam', () => {
    const activity = makeMockTransactionActivity({ isIncoming: false, nft: makeNft({ isScam: true }) });
    expect(isScamTransaction(activity)).toBe(true);
  });

  it('does not mark a transaction with a regular NFT as scam', () => {
    const activity = makeMockTransactionActivity({ isIncoming: false, nft: makeNft() });
    expect(isScamTransaction(activity)).toBe(false);
  });
});

describe('getIsHiddenNftActivity', () => {
  it('hides a blacklisted NFT', () => {
    const activity = makeMockTransactionActivity({ nft: makeNft({ address: BLACKLISTED_ADDRESS }) });
    expect(getIsHiddenNftActivity(activity, [BLACKLISTED_ADDRESS])).toBe(true);
  });

  it('hides a backend-hidden NFT that is not whitelisted', () => {
    const activity = makeMockTransactionActivity({ nft: makeNft({ isHidden: true }) });
    expect(getIsHiddenNftActivity(activity, [], [])).toBe(true);
  });

  it('keeps a backend-hidden NFT that the user whitelisted', () => {
    const activity = makeMockTransactionActivity({ nft: makeNft({ address: WHITELISTED_ADDRESS, isHidden: true }) });
    expect(getIsHiddenNftActivity(activity, undefined, [WHITELISTED_ADDRESS])).toBe(false);
  });

  it('keeps a regular NFT', () => {
    const activity = makeMockTransactionActivity({ nft: makeNft() });
    expect(getIsHiddenNftActivity(activity, [], [])).toBe(false);
  });

  it('keeps a transaction without an NFT', () => {
    const activity = makeMockTransactionActivity({ nft: undefined });
    expect(getIsHiddenNftActivity(activity, [BLACKLISTED_ADDRESS], [])).toBe(false);
  });

  it('hides an incoming unverified NFT when the setting is on', () => {
    const activity = makeMockTransactionActivity({ isIncoming: true, nft: makeNft({ isUnverified: true }) });
    expect(getIsHiddenNftActivity(activity, [], [], true)).toBe(true);
  });

  it('keeps an outgoing unverified NFT, because the user authored the transfer', () => {
    const activity = makeMockTransactionActivity({ isIncoming: false, nft: makeNft({ isUnverified: true }) });
    expect(getIsHiddenNftActivity(activity, [], [], true)).toBe(false);
  });

  // For `nftTrade` the `isIncoming` flag shows the TONCOIN direction, so a sale looks like an incoming transfer
  it('keeps an unverified NFT sold on a marketplace', () => {
    const activity = makeMockTransactionActivity({
      isIncoming: true,
      type: 'nftTrade',
      nft: makeNft({ isUnverified: true }),
    });
    expect(getIsHiddenNftActivity(activity, [], [], true)).toBe(false);
  });

  it('keeps an unverified NFT bought on a marketplace', () => {
    const activity = makeMockTransactionActivity({
      isIncoming: false,
      type: 'nftTrade',
      nft: makeNft({ isUnverified: true }),
    });
    expect(getIsHiddenNftActivity(activity, [], [], true)).toBe(false);
  });

  it('keeps an unverified NFT when the setting is off', () => {
    const activity = makeMockTransactionActivity({ isIncoming: true, nft: makeNft({ isUnverified: true }) });
    expect(getIsHiddenNftActivity(activity, [], [], false)).toBe(false);
  });

  it('keeps an unverified NFT that the user whitelisted', () => {
    const activity = makeMockTransactionActivity({
      isIncoming: true,
      nft: makeNft({ address: WHITELISTED_ADDRESS, isUnverified: true }),
    });
    expect(getIsHiddenNftActivity(activity, [], [WHITELISTED_ADDRESS], true)).toBe(false);
  });
});
