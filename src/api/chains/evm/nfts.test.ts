import type { ApiAccountAny } from '../../types';
import type { AlchemyOwnedNft } from './types';

import { getIsNftVisibleByFlags } from '../../../global/helpers/nfts';
import { fetchJson } from '../../../util/fetch';
import { fetchStoredAccount } from '../../common/accounts';
import { fetchNftByAddress, getAccountNfts } from './nfts';

jest.mock('../../../util/fetch', () => ({
  ...jest.requireActual('../../../util/fetch'),
  fetchJson: jest.fn(),
}));

jest.mock('../../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
}));

const OWNER = '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045';
const CONTRACT = '0x000000000000888741B254d37e1b27128AfEAaBC';
const TOKEN_ID = '5261405894391250505533265397778618870761357154713600';
const classifications = ['SuspiciousMetadata', 'SpammyMetadata'];
const fetchJsonMock = jest.mocked(fetchJson);

function makeNft(isSpam?: boolean | null): AlchemyOwnedNft {
  return {
    contract: { address: CONTRACT, tokenType: 'ERC721', isSpam, spamClassifications: classifications },
    tokenId: TOKEN_ID,
    tokenType: 'ERC721',
    name: 'SLOW',
    description: 'Tokenized representation of a time-locked Ether (ETH) transfer.',
    image: {},
    raw: {},
    balance: '1',
  };
}

beforeEach(() => {
  fetchJsonMock.mockReset();
  jest.mocked(fetchStoredAccount).mockResolvedValue({
    type: 'bip39',
    byChain: { ethereum: { address: OWNER, index: 0 } },
  } as ApiAccountAny);
});

it('keeps provider-flagged NFTs in the wallet response but hides them unless the user restores them', async () => {
  fetchJsonMock.mockResolvedValue({ ownedNfts: [makeNft(true)], totalCount: 1 });

  const nfts = await getAccountNfts('base', '0-mainnet');

  expect(nfts).toHaveLength(1);
  expect(nfts[0]).toMatchObject({
    address: `${CONTRACT.toLowerCase()}/${TOKEN_ID}`,
    isHidden: true,
    isScam: false,
    spamInfo: { provider: 'alchemy', isSpam: true, classifications },
  });
  expect(getIsNftVisibleByFlags(nfts[0])).toBe(false);
  expect(getIsNftVisibleByFlags(nfts[0], false, true)).toBe(true);
});

// Missing and null verdicts are unknown; classification labels alone are not a spam verdict.
// eslint-disable-next-line no-null/no-null
it.each([true, false, null, undefined])('preserves the %s verdict on received NFT metadata', async (isSpam) => {
  fetchJsonMock.mockResolvedValue(makeNft(isSpam));

  const nft = await fetchNftByAddress('base', 'mainnet', CONTRACT, TOKEN_ID, OWNER);

  expect(nft.isHidden).toBe(isSpam === true);
  expect(nft.isScam).toBe(false);
  expect(nft.spamInfo).toEqual({ provider: 'alchemy', isSpam: isSpam ?? undefined, classifications });
});

it('keeps the scam-link check when the provider does not flag the NFT', async () => {
  fetchJsonMock.mockResolvedValue({ ...makeNft(false), description: 'Claim at https://nft-scam.example' });

  const nft = await fetchNftByAddress('base', 'mainnet', CONTRACT, TOKEN_ID, OWNER);

  expect(nft).toMatchObject({ isHidden: true, isScam: true, spamInfo: { isSpam: false } });
});
