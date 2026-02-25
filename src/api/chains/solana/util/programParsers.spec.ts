import type { Address } from '@solana/kit';

import { parseTokenOperation } from './programParsers';

jest.mock('./metadata', () => ({
  updateTokensMetadataByAddress: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../../../common/tokens', () => ({
  buildTokenSlug: jest.fn((chain: string, address: string) => `${chain}:${address}`),
  getTokenBySlug: jest.fn().mockReturnValue({ slug: 'solana:mock', decimals: 9 }),
  updateTokens: jest.fn().mockResolvedValue(undefined),
}));

const ATA_RENT = 2039280n;

describe('parseTokenOperation', () => {
  const userAddress = 'UserAddress1111111111111111111111111111111' as Address;
  const otherAddress = 'OtherAddress222222222222222222222222222222' as Address;
  const mintAddress = 'TokenMint333333333333333333333333333333333' as Address;

  const staticAccountKeys = [userAddress, otherAddress, mintAddress];

  const baseMeta = {
    fee: 5000n,
    preBalances: [10000000n, 10000000n, 0n],
    postBalances: [9995000n, 10000000n, 0n],
    preTokenBalances: [],
    postTokenBalances: [],
  };

  it('should parse an outgoing token transfer', async () => {
    const txMeta = {
      ...baseMeta,
      preTokenBalances: [
        { accountIndex: 0, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000' } },
      ],
      postTokenBalances: [
        { accountIndex: 0, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '900' } },
        { accountIndex: 1, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '100' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect(result).toBeDefined();
    expect(result?.isSwap).toBe(false);
    expect((result as any)?.transfer?.amount).toBe(100n); // diff 1000 - 900
    expect((result as any)?.transfer?.isIncoming).toBe(false);
    expect((result as any)?.transfer?.fromAddress).toBe(userAddress);
    expect((result as any)?.transfer?.toAddress).toBe(otherAddress);
  });

  it('should parse an incoming token transfer', async () => {
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n, 10000000n, 0n],
      preTokenBalances: [
        { accountIndex: 0, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '500' } },
        { accountIndex: 0, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '1000' } },
      ],
      postTokenBalances: [
        { accountIndex: 0, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000' } },
        { accountIndex: 0, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '500' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect((result as any)?.transfer?.isIncoming).toBe(true);
    expect((result as any)?.transfer?.toAddress).toBe(userAddress);
    expect((result as any)?.transfer?.fromAddress).toBe(otherAddress);
    expect((result as any)?.transfer?.amount).toBe(500n);
  });

  it('should parse a swap between two tokens', async () => {
    const mintA = 'MintAAAAA111111111111111111111111111111111';
    const mintB = 'MintBBBBB222222222222222222222222222222222';

    const txMeta = {
      ...baseMeta,
      preTokenBalances: [
        { accountIndex: 0, mint: mintA, owner: userAddress, uiTokenAmount: { amount: '1000000000' } },
        { accountIndex: 1, mint: mintB, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 0, mint: mintA, owner: userAddress, uiTokenAmount: { amount: '0' } },
        { accountIndex: 1, mint: mintB, owner: userAddress, uiTokenAmount: { amount: '2000000000' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect(result?.isSwap).toBe(true);
    expect((result as any)?.swap?.fromAmount).toBe('1');
    expect((result as any)?.swap?.toAmount).toBe('2');
    expect((result as any)?.assets).toContain(mintA);
    expect((result as any)?.assets).toContain(mintB);
  });

  it('should account for ATA rent in fees when new token account is created', async () => {
    const txMeta = {
      ...baseMeta,
      postBalances: [7955720n, 10000000n, 0n],
      preTokenBalances: [],
      postTokenBalances: [
        { accountIndex: 3, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '100' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    if (result?.isSwap) {
      expect(result.swap?.networkFee).toBe((5000n + ATA_RENT).toString());
    }
  });

  it('should return undefined if no token balances found', async () => {
    const txMeta = { ...baseMeta, preTokenBalances: [], postTokenBalances: [] };
    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);
    expect(result).toBeUndefined();
  });
});
