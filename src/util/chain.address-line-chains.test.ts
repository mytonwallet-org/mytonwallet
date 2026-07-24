// The gate reads `IS_GRAM_WALLET` from `process.env` at module-eval time (it never changes at runtime),
// so each build flavor gets a clean env + an isolated re-import - same technique as `config.matrix.test.ts`.

import type { ApiChain, ApiStakingState } from '../api/types';
import type { Account, UserToken } from '../global/types';

type ChainModule = typeof import('./chain');
type FormatModule = typeof import('./formatAccountAddress');

const FLAG = 'IS_GRAM_WALLET';

let savedFlag: string | undefined;

beforeAll(() => {
  savedFlag = process.env[FLAG];
});

afterAll(() => {
  if (savedFlag === undefined) {
    delete process.env[FLAG];
  } else {
    process.env[FLAG] = savedFlag;
  }
});

async function withBuild(isGramWallet: boolean, run: (chain: ChainModule, format: FormatModule) => void) {
  if (isGramWallet) {
    process.env[FLAG] = '1';
  } else {
    delete process.env[FLAG];
  }

  await jest.isolateModulesAsync(async () => {
    const chain = await import('./chain');
    const format = await import('./formatAccountAddress');
    run(chain, format);
  });
}

const ALL_CHAINS: ApiChain[] = ['ton', 'tron', 'ethereum', 'solana'];

const multiChainAccount: Account['byChain'] = {
  ton: { address: 'UQA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q7R8S9T0U1V2' },
  tron: { address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t' },
  ethereum: { address: '0xf3351234567890abcdef1234567890abcdefD397' },
};

const fundedTonToken = { chain: 'ton', slug: 'toncoin', amount: 100n } as UserToken;
const fundedTronToken = { chain: 'tron', slug: 'trx', amount: 5n } as UserToken;
const emptyTonToken = { chain: 'ton', slug: 'toncoin', amount: 0n } as UserToken;
const emptyTronToken = { chain: 'tron', slug: 'trx', amount: 0n } as UserToken;
const disabledTronToken = { chain: 'tron', slug: 'scam-usdt', amount: 999n, isDisabled: true } as UserToken;

const tonStake = { tokenSlug: 'toncoin', balance: 5n } as ApiStakingState;

describe('getAddressLineChains', () => {
  describe('Gram Wallet build', () => {
    it('collapses to TON while the funds sit on TON alone', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, new Set(['ton']))).toEqual(['ton']);
      });
    });

    it('collapses to TON while the wallet holds no funds at all', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, new Set())).toEqual(['ton']);
      });
    });

    it('shows only the funded chains once foreign-chain funds appear', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, new Set(['ton', 'tron']))).toEqual(['ton', 'tron']);
      });
    });

    it('hides an unfunded TON chain when the funds are foreign only', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, new Set(['tron']))).toEqual(['tron']);
      });
    });

    it('shows every chain while the token list is not known yet', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, undefined)).toEqual(ALL_CHAINS);
      });
    });

    it('keeps an unfunded account without a TON wallet intact', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(['tron', 'ethereum'], new Set())).toEqual(['tron', 'ethereum']);
      });
    });

    it('keeps every chain when no funded chain belongs to the account', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(['ton', 'tron'], new Set(['solana']))).toEqual(['ton', 'tron']);
      });
    });
  });

  it('never hides chains outside the Gram Wallet build', async () => {
    await withBuild(false, ({ getAddressLineChains }) => {
      expect(getAddressLineChains(ALL_CHAINS, new Set(['ton']))).toEqual(ALL_CHAINS);
    });
  });
});

describe('getAddressDisplayByChain', () => {
  describe('Gram Wallet build', () => {
    it('keeps only the TON address while the funds sit on TON alone', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        const result = getAddressDisplayByChain(multiChainAccount, [fundedTonToken, emptyTronToken]);
        expect(Object.keys(result)).toEqual(['ton']);
        expect(result.ton).toBe(multiChainAccount.ton);
      });
    });

    it('keeps only the TON address while the wallet holds no funds at all', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        expect(Object.keys(getAddressDisplayByChain(multiChainAccount, []))).toEqual(['ton']);
      });
    });

    it('keeps only the funded chains once foreign-chain funds appear', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        const result = getAddressDisplayByChain(multiChainAccount, [fundedTonToken, fundedTronToken]);
        expect(Object.keys(result)).toEqual(['ton', 'tron']);
      });
    });

    it('ignores disabled (hidden) tokens whatever their balance', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        const result = getAddressDisplayByChain(multiChainAccount, [fundedTonToken, disabledTronToken]);
        expect(Object.keys(result)).toEqual(['ton']);
      });
    });

    it('counts a staked-only balance as funds on its chain', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        const result = getAddressDisplayByChain(multiChainAccount, [emptyTonToken, emptyTronToken], [tonStake]);
        expect(Object.keys(result)).toEqual(['ton']);
      });
    });

    it('returns the same object while every account chain is funded', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        const byChain: Account['byChain'] = { ton: multiChainAccount.ton, tron: multiChainAccount.tron };
        expect(getAddressDisplayByChain(byChain, [fundedTonToken, fundedTronToken])).toBe(byChain);
      });
    });

    it('returns the same object while the token list is not known yet', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        expect(getAddressDisplayByChain(multiChainAccount, undefined)).toBe(multiChainAccount);
      });
    });
  });

  it('returns the same object outside the Gram Wallet build', async () => {
    await withBuild(false, (_, { getAddressDisplayByChain }) => {
      expect(getAddressDisplayByChain(multiChainAccount, [fundedTonToken])).toBe(multiChainAccount);
    });
  });
});
