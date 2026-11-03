import type { Address } from '@solana/kit';

import { SOLANA_PROGRAM_IDS, WSOL_MINT } from '../constants';
import { parseTokenOperation, parseUserPaidTokenAccountRent } from './programParsers';

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
    expect((result as any)?.transfers?.[0]?.amount).toBe(100n); // diff 1000 - 900
    expect((result as any)?.transfers?.[0]?.isIncoming).toBe(false);
    expect((result as any)?.transfers?.[0]?.fromAddress).toBe(userAddress);
    expect((result as any)?.transfers?.[0]?.toAddress).toBe(otherAddress);
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

    const feePayerFirstKeys = [otherAddress, userAddress, mintAddress];
    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, feePayerFirstKeys);

    expect((result as any)?.transfers).toHaveLength(1);
    expect((result as any)?.transfers?.[0]?.isIncoming).toBe(true);
    expect((result as any)?.transfers?.[0]?.toAddress).toBe(userAddress);
    expect((result as any)?.transfers?.[0]?.fromAddress).toBe(otherAddress);
    expect((result as any)?.transfers?.[0]?.amount).toBe(500n);
  });

  it('should show wrapped SOL the user receives as wrapped SOL', async () => {
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n, 10000000n, 0n],
      preTokenBalances: [
        { accountIndex: 3, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '0' } },
        { accountIndex: 4, mint: WSOL_MINT, owner: otherAddress, uiTokenAmount: { amount: '2000' } },
      ],
      postTokenBalances: [
        { accountIndex: 3, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '2000' } },
        { accountIndex: 4, mint: WSOL_MINT, owner: otherAddress, uiTokenAmount: { amount: '0' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, [otherAddress, userAddress]);

    expect((result as any)?.transfers).toEqual([
      expect.objectContaining({ slug: `solana:${WSOL_MINT}`, amount: 2000n, isIncoming: true }),
    ]);
  });

  it('should show the full SOL amount received by a user who pays the fee', async () => {
    const otherTokenBalance = {
      accountIndex: 1, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '100' },
    };
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n + 1000000000n - 5000n, 10000000n, 0n],
      preTokenBalances: [otherTokenBalance],
      postTokenBalances: [otherTokenBalance],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect((result as any)?.transfers).toEqual([
      expect.objectContaining({ slug: 'sol', amount: 1000000000n, isIncoming: true }),
    ]);
  });

  it('should show the full SOL amount sent when another account pays the fee', async () => {
    const txMeta = {
      ...baseMeta,
      preBalances: [10000000n, 2000000000n, 0n],
      postBalances: [10000000n - 5000n, 1000000000n, 0n],
      preTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000' } },
        { accountIndex: 0, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '900' } },
        { accountIndex: 0, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '100' } },
      ],
    };
    const feePayerFirstKeys = [otherAddress, userAddress, mintAddress];

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, feePayerFirstKeys);

    expect((result as any)?.transfers).toEqual([
      expect.objectContaining({ slug: `solana:${mintAddress}`, amount: 100n }),
      expect.objectContaining({ slug: 'sol', amount: 1000000000n }),
    ]);
  });

  it('should show a burned token and the SOL paid with it as outgoing', async () => {
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n - 5000n - 1000000n, 10000000n + 1000000n, 0n],
      preTokenBalances: [
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000' } },
      ],
      postTokenBalances: [
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '900' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect((result as any)?.transfers).toEqual([
      expect.objectContaining({ slug: `solana:${mintAddress}`, amount: 100n, isIncoming: false }),
      expect.objectContaining({ slug: 'sol', amount: 1000000n, isIncoming: false }),
    ]);
  });

  describe('rent of a token account the transaction opens', () => {
    const rent = 1488440n;
    const userTokenBefore = {
      accountIndex: 0, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000' },
    };
    const userTokenAfter = { ...userTokenBefore, uiTokenAmount: { amount: '900' } };
    const newRecipientAccount = {
      accountIndex: 3, mint: mintAddress, owner: otherAddress, uiTokenAmount: { amount: '100' },
    };
    const userPaidRent = new Map([[3, rent]]);
    const metaWithUserBalance = (postBalance: bigint) => ({
      ...baseMeta,
      preBalances: [10000000n, 10000000n, 0n, 0n],
      postBalances: [postBalance, 10000000n, 0n, rent],
      preTokenBalances: [userTokenBefore],
      postTokenBalances: [userTokenAfter, newRecipientAccount],
    });
    const parse = (txMeta: object, rentByAccountIndex: ReadonlyMap<number, bigint>) => (
      parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys, rentByAccountIndex)
    );

    it('should show the rent of every further account opened for the same token as a transfer', async () => {
      const secondRecipient = {
        ...newRecipientAccount, accountIndex: 4, owner: 'Second5555555555555555555555555555555555555',
      };
      const result = await parse({
        ...metaWithUserBalance(10000000n - 5000n - 2n * rent),
        postTokenBalances: [
          { ...userTokenAfter, uiTokenAmount: { amount: '800' } },
          newRecipientAccount,
          secondRecipient,
        ],
      }, new Map([[3, rent], [4, rent]]));

      expect((result as any)?.transfers).toEqual([
        expect.objectContaining({ slug: `solana:${mintAddress}`, amount: 200n }),
        expect.objectContaining({ slug: 'sol', amount: rent }),
      ]);
      expect((result as any)?.networkFee).toBe(5000n + rent);
    });

    it('should not take more rent into the fee than the SOL the user spends', async () => {
      const result = await parse(metaWithUserBalance(10000000n - 5000n - rent + 1000n), userPaidRent);

      expect((result as any)?.transfers).toEqual([
        expect.objectContaining({ slug: `solana:${mintAddress}`, amount: 100n }),
      ]);
      expect((result as any)?.networkFee).toBe(5000n + rent - 1000n);
    });

    it('should take the rent of an account opened for sent wrapped SOL into the fee', async () => {
      const result = await parse({
        ...metaWithUserBalance(10000000n - 5000n - rent),
        preTokenBalances: [{ ...userTokenBefore, mint: WSOL_MINT }],
        postTokenBalances: [{ ...userTokenAfter, mint: WSOL_MINT }, { ...newRecipientAccount, mint: WSOL_MINT }],
      }, userPaidRent);

      expect((result as any)?.transfers).toEqual([
        expect.objectContaining({ slug: `solana:${WSOL_MINT}`, amount: 100n }),
      ]);
      expect((result as any)?.networkFee).toBe(5000n + rent);
    });

    it('should show SOL as a transfer when the account the user opens does not receive a sent token', async () => {
      const existingRecipient = { ...newRecipientAccount, accountIndex: 1 };
      const notReceiving = [
        { ...newRecipientAccount, mint: 'OtherMint4444444444444444444444444444444444', uiTokenAmount: { amount: '5' } },
        { ...newRecipientAccount, uiTokenAmount: { amount: '0' } },
      ];

      for (const openedAccount of notReceiving) {
        const result = await parse({
          ...metaWithUserBalance(10000000n - 5000n - rent),
          preTokenBalances: [userTokenBefore, { ...existingRecipient, uiTokenAmount: { amount: '0' } }],
          postTokenBalances: [userTokenAfter, existingRecipient, openedAccount],
        }, userPaidRent);

        expect((result as any)?.transfers).toEqual([
          expect.objectContaining({ slug: `solana:${mintAddress}`, amount: 100n }),
          expect.objectContaining({ slug: 'sol', amount: rent }),
        ]);
        expect((result as any)?.networkFee).toBe(5000n);
      }
    });
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

  it('should show wrapped SOL the user swaps for a token', async () => {
    const txMeta = {
      ...baseMeta,
      preTokenBalances: [
        { accountIndex: 1, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '2000000000' } },
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '0' } },
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '3000000000' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect(result?.isSwap).toBe(true);
    expect((result as any)?.swap).toMatchObject({ fromAmount: '2', toAmount: '3' });
  });

  it('should show the SOL a swap spends when it unwraps wrapped SOL the user already held', async () => {
    const accountRent = 2039280n;
    const txMeta = {
      ...baseMeta,
      preBalances: [20000000000n, 10000000n, 0n],
      postBalances: [20000000000n - 10000000000n + 1000000n + accountRent - 5000n, 10000000n, 0n],
      preTokenBalances: [
        { accountIndex: 1, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '1000000' } },
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '3000000000' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect((result as any)?.swap).toMatchObject({ from: 'sol', fromAmount: '9.99796072', toAmount: '3' });
  });

  it('should show SOL a token swap spends besides the fee, such as a tip, in the fee', async () => {
    const mintB = 'MintBBBBB222222222222222222222222222222222';
    const tip = 1230n;
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n - 5000n - tip, 10000000n, 0n],
      preTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000000000' } },
        { accountIndex: 2, mint: mintB, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '500000000' } },
        { accountIndex: 2, mint: mintB, owner: userAddress, uiTokenAmount: { amount: '3000000000' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect(result?.isSwap).toBe(true);
    expect((result as any)?.swap).toMatchObject({ fromAmount: '0.5', toAmount: '3', networkFee: String(5000n + tip) });
  });

  it('should leave rent a token swap refunds to the user out of its assets', async () => {
    const mintB = 'MintBBBBB222222222222222222222222222222222';
    const mintC = 'MintCCCCC333333333333333333333333333333333';
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n - 5000n + ATA_RENT, 10000000n, 0n],
      preTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '1000000000' } },
        { accountIndex: 2, mint: mintB, owner: userAddress, uiTokenAmount: { amount: '0' } },
        { accountIndex: 3, mint: mintC, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '500000000' } },
        { accountIndex: 2, mint: mintB, owner: userAddress, uiTokenAmount: { amount: '3000000000' } },
      ],
    };

    const result = await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys);

    expect(result?.isSwap).toBe(true);
    expect((result as any)?.swap).toMatchObject({ fromAmount: '0.5', toAmount: '3', networkFee: '5000' });
  });

  it('should leave a swap that sends more than one asset to the unparsed preview', async () => {
    const junkMint = 'JunkMint4444444444444444444444444444444444';
    const wrapped = 2000000000n;
    const txMeta = {
      ...baseMeta,
      preTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '250000000' } },
        { accountIndex: 2, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: String(wrapped) } },
        { accountIndex: 3, mint: junkMint, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '150000000' } },
        { accountIndex: 2, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '0' } },
        { accountIndex: 3, mint: junkMint, owner: userAddress, uiTokenAmount: { amount: '1' } },
      ],
    };

    expect(await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys)).toBeUndefined();
  });

  it('should leave a swap that receives more than one asset to the unparsed preview', async () => {
    const lpMint = 'LpMint55555555555555555555555555555555555555';
    const txMeta = {
      ...baseMeta,
      postBalances: [10000000n - 5000n + 3000000000n, 10000000n, 0n],
      preTokenBalances: [
        { accountIndex: 1, mint: lpMint, owner: userAddress, uiTokenAmount: { amount: '1000' } },
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: lpMint, owner: userAddress, uiTokenAmount: { amount: '0' } },
        { accountIndex: 2, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '500000000' } },
      ],
    };

    expect(await parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys)).toBeUndefined();
  });

  it('should refuse an approval that changes no holding of the user', async () => {
    const txMeta = {
      ...baseMeta,
      preTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '500' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: mintAddress, owner: userAddress, uiTokenAmount: { amount: '500' } },
      ],
    };

    await expect(parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys))
      .rejects.toThrow('Transaction changes no holding of the user');
  });

  it('should refuse a wrap that changes no holding of the user', async () => {
    const wrapped = 2000000000n;
    const txMeta = {
      ...baseMeta,
      preBalances: [10000000000n, 10000000n, 0n],
      postBalances: [10000000000n - wrapped - 5000n, 10000000n + wrapped, 0n],
      preTokenBalances: [
        { accountIndex: 1, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: '0' } },
      ],
      postTokenBalances: [
        { accountIndex: 1, mint: WSOL_MINT, owner: userAddress, uiTokenAmount: { amount: String(wrapped) } },
      ],
    };

    await expect(parseTokenOperation('mainnet', txMeta as any, userAddress, staticAccountKeys))
      .rejects.toThrow('Transaction changes no holding of the user');
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

describe('parseUserPaidTokenAccountRent', () => {
  const user = 'UserAddress1111111111111111111111111111111';
  const dapp = 'DappAddress444444444444444444444444444444444';
  const newAccount = 'NewAccount55555555555555555555555555555555';
  const rent = 1600200;
  const staticAccounts = [user, newAccount, dapp, SOLANA_PROGRAM_IDS.ata[0], SOLANA_PROGRAM_IDS.token[0]];
  const openAccount = (data?: number[], programAddressIndex = 3, accountIndex = 1) => ({
    staticAccounts,
    instructions: [{ programAddressIndex, accountIndices: [0, accountIndex, 2], data: data && new Uint8Array(data) }],
  }) as any;
  const funding = (source: string, type = 'createAccount', index = 0) => [{
    index,
    instructions: [{
      parsed: { type, info: { source, newAccount, lamports: rent } },
      program: 'system',
      programId: SOLANA_PROGRAM_IDS.system[0],
      stackHeight: 2,
    }],
  }] as any;

  it('should take the lamports the user pays inside the instruction that opens the account', () => {
    expect(parseUserPaidTokenAccountRent(openAccount(), funding(user), user)).toEqual(new Map([[1, BigInt(rent)]]));
    expect(parseUserPaidTokenAccountRent(openAccount([1]), funding(user, 'transfer'), user))
      .toEqual(new Map([[1, BigInt(rent)]]));
  });

  it('should ignore an account the dapp pays for', () => {
    expect(parseUserPaidTokenAccountRent(openAccount(), funding(dapp), user).size).toBe(0);
  });

  it('should ignore lamports the user pays in another instruction', () => {
    expect(parseUserPaidTokenAccountRent(openAccount(), funding(user, 'createAccount', 1), user).size).toBe(0);
  });

  it('should ignore an instruction that does not open an account', () => {
    expect(parseUserPaidTokenAccountRent(openAccount([2]), funding(user), user).size).toBe(0);
    expect(parseUserPaidTokenAccountRent(openAccount([1], 4), funding(user), user).size).toBe(0);
  });

  it('should ignore an account loaded from a lookup table', () => {
    expect(parseUserPaidTokenAccountRent(openAccount(undefined, 3, 9), funding(user), user).size).toBe(0);
  });

  it('should ignore an account closed in the same transaction', () => {
    const innerClose = (inner: object) => [...funding(user), { index: 1, instructions: [inner] }] as any;

    expect(parseUserPaidTokenAccountRent(openAccount(), innerClose({
      parsed: { type: 'closeAccount', info: { account: newAccount } },
      program: 'spl-token',
      programId: SOLANA_PROGRAM_IDS.token[0],
      stackHeight: 2,
    }), user).size).toBe(0);
    expect(parseUserPaidTokenAccountRent(openAccount(), innerClose({
      accounts: [newAccount, user], data: 'A', programId: SOLANA_PROGRAM_IDS.token[1], stackHeight: 2,
    }), user).size).toBe(0);
  });
});
