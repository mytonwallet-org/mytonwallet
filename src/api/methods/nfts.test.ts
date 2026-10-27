const mockCallBackendPost = jest.fn();
const mockFetchNftByAddress = jest.fn();

jest.mock('../common/accounts', () => ({ fetchStoredWallet: jest.fn(() => Promise.resolve({ address: 'sender' })) }));
jest.mock('./transfer', () => ({ createLocalTransactions: jest.fn() }));
jest.mock('./optional', () => ({
  requireMfaMethods: () => ({ refreshMfaState: jest.fn(() => Promise.resolve(undefined)) }),
}));

jest.mock('../common/backend', () => ({
  callBackendPost: (...args: unknown[]) => mockCallBackendPost(...args),
}));

jest.mock('../chains/ton/toncenter/nfts', () => ({
  fetchNftByAddress: (...args: unknown[]) => mockFetchNftByAddress(...args),
}));

import type { ApiNft } from '../types';
import { ApiTransactionError } from '../types';

import chains from '../chains';
import { fetchNftByAddress, reportNft, submitNftTransfers } from './nfts';
import { createLocalTransactions } from './transfer';

const NFT_ADDRESS = 'EQBtqQlC09xW_oOHJOrMofDmFndOrY7zCjd7bYELIoabO9JC';

describe('NFT methods', () => {
  afterEach(() => {
    mockCallBackendPost.mockReset();
    mockFetchNftByAddress.mockReset();
  });

  it('sends a chain-qualified NFT report to the backend', async () => {
    mockCallBackendPost.mockResolvedValue({ ok: true });
    const options = {
      chain: 'ton' as const,
      network: 'mainnet' as const,
      nftAddress: 'EQ-reported-nft',
    };

    await reportNft(options);

    expect(mockCallBackendPost).toHaveBeenCalledWith('/nfts/report', options);
  });

  describe('fetchNftByAddress', () => {
    it('serves the NFT loaded by the chain', async () => {
      const parsedNft = { address: NFT_ADDRESS, name: 'Parsed NFT' };
      mockFetchNftByAddress.mockResolvedValue(parsedNft);

      const result = await fetchNftByAddress('ton', 'mainnet', NFT_ADDRESS);

      expect(mockFetchNftByAddress).toHaveBeenCalledWith('mainnet', NFT_ADDRESS);
      expect(result).toBe(parsedNft);
    });
  });

  describe('submitNftTransfers', () => {
    const nfts = Array.from({ length: 5 }, (_, index) => ({ address: `nft-${index}` } as ApiNft));
    let submit: jest.SpyInstance;

    beforeEach(() => {
      submit = jest.spyOn(chains.ton, 'submitNftTransfers');
      jest.mocked(createLocalTransactions).mockImplementation((_accountId, _chain, transactions) => transactions.map(
        (transaction) => ({ ...transaction, id: `${transaction.id}/${transaction.normalizedAddress}` }),
      ) as ReturnType<typeof createLocalTransactions>);
    });

    afterEach(() => {
      submit.mockRestore();
      jest.mocked(createLocalTransactions).mockClear();
    });

    it('associates every NFT with its own batch hash', async () => {
      submit.mockResolvedValue({
        transfers: nfts.map((nft, index) => ({
          toAddress: nft.address,
          msgHashNormalized: index < 4 ? 'first' : 'second',
        })),
      });

      const result = await submitNftTransfers('ton', '0-mainnet', 'token', nfts, 'recipient', 'comment', 50n);

      expect(result).toEqual({
        activityIds: ['first/nft-0', 'first/nft-1', 'first/nft-2', 'first/nft-3', 'second/nft-4'],
      });
      const transactions = jest.mocked(createLocalTransactions).mock.calls[0][2];
      expect(transactions.map((transaction) => transaction.externalMsgHashNorm)).toEqual([
        'first', 'first', 'first', 'first', 'second',
      ]);
      expect(transactions.map((transaction) => transaction.nft)).toEqual(nfts);
      expect(transactions.every((transaction) => transaction.fee === 10n)).toBe(true);
    });

    it('records accepted batches and a partial failure with fees only for submitted NFTs', async () => {
      submit.mockResolvedValue({
        error: ApiTransactionError.InsufficientBalance,
        transfers: nfts.slice(0, 4).map((nft) => ({ toAddress: nft.address, msgHashNormalized: 'first' })),
      });

      const result = await submitNftTransfers('ton', '0-mainnet', 'token', nfts, 'recipient', undefined, 50n);

      expect(result).toEqual({
        error: ApiTransactionError.PartialTransactionFailure,
        activityIds: ['first/nft-0', 'first/nft-1', 'first/nft-2', 'first/nft-3'],
      });
      const transactions = jest.mocked(createLocalTransactions).mock.calls[0][2];
      expect(transactions.map((transaction) => transaction.nft)).toEqual(nfts.slice(0, 4));
      expect(transactions.every((transaction) => transaction.fee === 10n)).toBe(true);
    });
  });
});
