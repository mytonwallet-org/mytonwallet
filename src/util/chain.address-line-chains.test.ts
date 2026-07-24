// The gate reads `IS_GRAM_WALLET` from `process.env` at module-eval time (it never changes at runtime),
// so each build flavor gets a clean env + an isolated re-import - same technique as `config.matrix.test.ts`.

import type { ApiChain } from '../api/types';
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
};

const tonToken = { chain: 'ton', isDisabled: false } as UserToken;
const tronToken = { chain: 'tron', isDisabled: false } as UserToken;
const disabledTronToken = { chain: 'tron', isDisabled: true } as UserToken;

describe('getAddressLineChains', () => {
  describe('Gram Wallet build', () => {
    it('collapses to TON while the wallet holds TON-chain tokens only', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, true)).toEqual(['ton']);
      });
    });

    it('shows every chain once a foreign-chain token appears', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, false)).toEqual(ALL_CHAINS);
      });
    });

    it('shows every chain while the token list is not known yet', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(ALL_CHAINS, undefined)).toEqual(ALL_CHAINS);
      });
    });

    it('keeps an account without a TON wallet intact', async () => {
      await withBuild(true, ({ getAddressLineChains }) => {
        expect(getAddressLineChains(['tron', 'ethereum'], true)).toEqual(['tron', 'ethereum']);
      });
    });
  });

  it('never hides chains outside the Gram Wallet build', async () => {
    await withBuild(false, ({ getAddressLineChains }) => {
      expect(getAddressLineChains(ALL_CHAINS, true)).toEqual(ALL_CHAINS);
    });
  });
});

describe('getAddressDisplayByChain', () => {
  describe('Gram Wallet build', () => {
    it('keeps only the TON address while shown tokens are TON-only', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        const result = getAddressDisplayByChain(multiChainAccount, [tonToken, disabledTronToken]);
        expect(Object.keys(result)).toEqual(['ton']);
        expect(result.ton).toBe(multiChainAccount.ton);
      });
    });

    it('keeps only the TON address while the wallet shows no tokens at all', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        expect(Object.keys(getAddressDisplayByChain(multiChainAccount, []))).toEqual(['ton']);
      });
    });

    it('returns the same object once a foreign-chain token is shown', async () => {
      await withBuild(true, (_, { getAddressDisplayByChain }) => {
        expect(getAddressDisplayByChain(multiChainAccount, [tonToken, tronToken])).toBe(multiChainAccount);
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
      expect(getAddressDisplayByChain(multiChainAccount, [tonToken])).toBe(multiChainAccount);
    });
  });
});
