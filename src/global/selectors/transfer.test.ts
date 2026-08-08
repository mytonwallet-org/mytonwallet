import type { ApiBaseCurrency, ApiChain } from '../../api/types';
import type { GlobalState } from '../types';

import {
  SOLANA,
  SOLANA_USDT_MAINNET,
  TON_USDT_MAINNET,
  TONCOIN,
  TRC20_USDT_MAINNET,
  TRX,
} from '../../config';
import { CHAIN_ORDER, getChainConfig } from '../../util/chain';
import { INITIAL_STATE } from '../initialState';
import {
  selectDefaultOnRampChain,
  selectIsOffRampAllowed,
  selectIsOnRampAllowed,
  selectTokenMatchingCurrentTransferAddressSlow,
} from './transfer';

const ACCOUNT_ID = 'test-account';
const TON_ADDRESS = 'EQAIsixsrb93f9kDyplo_bK5OdgW5r0WCcIJZdGOUG1B282S';
const TRON_ADDRESS = 'TBvwz11CKdgBymTtF7Q6UfhGWQyEqNrodT';
const SOL_ADDRESS = '35YT7tt9edJbroEKaC3T3XY4cLNWKtVzmyTEfW8LHPEA';

const TOKEN_INFO: Record<string, object> = {
  [TONCOIN.slug]: { ...TONCOIN, priceUsd: 5, percentChange24h: 0 },
  [TON_USDT_MAINNET.slug]: { ...TON_USDT_MAINNET, priceUsd: 1, percentChange24h: 0 },
  [TRX.slug]: { ...TRX, priceUsd: 0.1, percentChange24h: 0 },
  [TRC20_USDT_MAINNET.slug]: { ...TRC20_USDT_MAINNET, priceUsd: 1, percentChange24h: 0 },
  [SOLANA.slug]: { ...SOLANA, priceUsd: 150, percentChange24h: 0 },
  [SOLANA_USDT_MAINNET.slug]: { ...SOLANA_USDT_MAINNET, priceUsd: 1, percentChange24h: 0 },
};

/**
 * Builds a minimal GlobalState for testing selectTokenMatchingCurrentTransferAddressSlow.
 *
 * The set of chains available in the account is derived automatically from the
 * `chain` field of each token slug present in `balances`.
 */
function buildGlobal(
  tokenSlug: string,
  toAddress: string | undefined,
  balances: Record<string, bigint>,
): GlobalState {
  const byChain: Record<string, unknown> = {};
  for (const slug of Object.keys(balances)) {
    const info = TOKEN_INFO[slug] as any;
    if (info?.chain === 'ton') byChain.ton = { address: TON_ADDRESS };
    if (info?.chain === 'tron') byChain.tron = { address: TRON_ADDRESS };
    if (info?.chain === 'solana') byChain.solana = { address: SOL_ADDRESS };
  }

  const tokenInfoBySlug = Object.fromEntries(
    Object.keys(balances)
      .filter((slug) => slug in TOKEN_INFO)
      .map((slug) => [slug, TOKEN_INFO[slug]]),
  );

  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    currentTransfer: {
      ...INITIAL_STATE.currentTransfer,
      tokenSlug,
      toAddress,
    },
    accounts: {
      byId: { [ACCOUNT_ID]: { title: 'Test', type: 'mnemonic', byChain } },
    } as GlobalState['accounts'],
    tokenInfo: { bySlug: tokenInfoBySlug } as GlobalState['tokenInfo'],
    byAccountId: {
      [ACCOUNT_ID]: {
        balances: { bySlug: balances },
        nfts: { byAddress: {} },
      } as GlobalState['byAccountId'][string],
    },
    settings: {
      ...INITIAL_STATE.settings,
      isTestnet: false,
      byAccountId: { [ACCOUNT_ID]: {} },
    },
  };
}

describe('selectTokenMatchingCurrentTransferAddressSlow', () => {
  describe('no-op conditions', () => {
    it('returns the current token when toAddress is empty', () => {
      const global = buildGlobal(TONCOIN.slug, undefined, {
        [TONCOIN.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TONCOIN.slug);
    });

    it('returns the current token when the address belongs to the current chain (TON → TON)', () => {
      const global = buildGlobal(TONCOIN.slug, TON_ADDRESS, {
        [TONCOIN.slug]: 1_000_000_000n,
        [TRX.slug]: 1_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TONCOIN.slug);
    });

    it('returns the current token when the address belongs to the current chain (TRON → TRON)', () => {
      const global = buildGlobal(TRX.slug, TRON_ADDRESS, {
        [TRX.slug]: 1_000_000n,
        [TONCOIN.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TRX.slug);
    });
  });

  describe('chain switching from TON', () => {
    it('selects TRX when pasting a TRON address while Toncoin is current', () => {
      const global = buildGlobal(TONCOIN.slug, TRON_ADDRESS, {
        [TONCOIN.slug]: 1_000_000_000n,
        [TRX.slug]: 1_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TRX.slug);
    });

    it('selects SOL when pasting a Solana address while Toncoin is current', () => {
      const global = buildGlobal(TONCOIN.slug, SOL_ADDRESS, {
        [TONCOIN.slug]: 1_000_000_000n,
        [SOLANA.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(SOLANA.slug);
    });
  });

  describe('chain switching from Solana (Bug 1: TRON address overlaps Solana regex)', () => {
    it('selects TRX when pasting a TRON address while SOL is current', () => {
      const global = buildGlobal(SOLANA.slug, TRON_ADDRESS, {
        [SOLANA.slug]: 1_000_000_000n,
        [TRX.slug]: 1_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TRX.slug);
    });

    it('selects Toncoin when pasting a TON address while SOL is current', () => {
      const global = buildGlobal(SOLANA.slug, TON_ADDRESS, {
        [SOLANA.slug]: 1_000_000_000n,
        [TONCOIN.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TONCOIN.slug);
    });
  });

  describe('native → native token preference', () => {
    it('prefers Toncoin (native) over TON USDT when TRX is current', () => {
      const global = buildGlobal(TRX.slug, TON_ADDRESS, {
        [TRX.slug]: 1_000_000n,
        [TONCOIN.slug]: 100_000_000n,
        [TON_USDT_MAINNET.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TONCOIN.slug);
    });

    it('prefers Toncoin (native) over TON USDT when SOL is current', () => {
      const global = buildGlobal(SOLANA.slug, TON_ADDRESS, {
        [SOLANA.slug]: 1_000_000_000n,
        [TONCOIN.slug]: 100_000_000n,
        [TON_USDT_MAINNET.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TONCOIN.slug);
    });

    it('prefers TRX (native) over TRON USDT when Toncoin is current', () => {
      const global = buildGlobal(TONCOIN.slug, TRON_ADDRESS, {
        [TONCOIN.slug]: 1_000_000_000n,
        [TRX.slug]: 1_000_000n,
        [TRC20_USDT_MAINNET.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TRX.slug);
    });
  });

  describe('USDT cross-chain preference (Bug 2)', () => {
    it('prefers TRON USDT over TRX when TON USDT is current', () => {
      const global = buildGlobal(TON_USDT_MAINNET.slug, TRON_ADDRESS, {
        [TON_USDT_MAINNET.slug]: 1_000_000n,
        [TRC20_USDT_MAINNET.slug]: 1_000_000n,
        [TRX.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(TRC20_USDT_MAINNET.slug);
    });

    it('prefers Solana USDT over SOL when TON USDT is current', () => {
      const global = buildGlobal(TON_USDT_MAINNET.slug, SOL_ADDRESS, {
        [TON_USDT_MAINNET.slug]: 1_000_000n,
        [SOLANA_USDT_MAINNET.slug]: 1_000_000n,
        [SOLANA.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(SOLANA_USDT_MAINNET.slug);
    });

    it('falls back to the max-balance token when the target chain has no USDT in the account', () => {
      const global = buildGlobal(TON_USDT_MAINNET.slug, SOL_ADDRESS, {
        [TON_USDT_MAINNET.slug]: 1_000_000n,
        [SOLANA.slug]: 1_000_000_000n,
      });

      expect(selectTokenMatchingCurrentTransferAddressSlow(global)).toBe(SOLANA.slug);
    });
  });
});

describe('ramp availability by allowed currencies', () => {
  function buildRestrictedGlobal(allowedOnOffRampCurrencies?: ApiBaseCurrency[]): GlobalState {
    return {
      ...INITIAL_STATE,
      restrictions: { ...INITIAL_STATE.restrictions, allowedOnOffRampCurrencies },
    };
  }

  it('allows both ramps when the server list is absent', () => {
    const global = buildRestrictedGlobal(undefined);

    expect(selectIsOnRampAllowed(global, 'ton')).toBe(true);
    expect(selectIsOffRampAllowed(global, 'ton')).toBe(true);
  });

  it('hides both ramps when the server list is empty', () => {
    const global = buildRestrictedGlobal([]);

    expect(selectIsOnRampAllowed(global, 'ton')).toBe(false);
    expect(selectIsOffRampAllowed(global, 'ton')).toBe(false);
  });

  it('keeps the on-ramp when only off-ramp currencies are gone', () => {
    const global = buildRestrictedGlobal(['USD']);

    expect(selectIsOnRampAllowed(global, 'ton')).toBe(true);
    expect(selectIsOffRampAllowed(global, 'ton')).toBe(false);
  });

  it('hides the off-ramp outside TON when RUB is the only allowed currency', () => {
    const global = buildRestrictedGlobal(['RUB']);

    expect(selectIsOffRampAllowed(global, 'tron')).toBe(false);
    expect(selectIsOffRampAllowed(global, 'ton')).toBe(true);
  });

  it('hides the on-ramp on Tron when RUB is the only allowed currency', () => {
    const global = buildRestrictedGlobal(['RUB']);

    expect(selectIsOnRampAllowed(global, 'tron')).toBe(false);
    expect(selectIsOnRampAllowed(global, 'ton')).toBe(true);
  });

  function buildAccountGlobal(chains: ApiChain[], allowedOnOffRampCurrencies?: ApiBaseCurrency[]): GlobalState {
    const byChain = Object.fromEntries(chains.map((chain) => [chain, { address: TON_ADDRESS }]));

    return {
      ...buildRestrictedGlobal(allowedOnOffRampCurrencies),
      currentAccountId: ACCOUNT_ID,
      accounts: { byId: { [ACCOUNT_ID]: { title: 'Test', type: 'mnemonic', byChain } } } as GlobalState['accounts'],
    };
  }

  describe('selectDefaultOnRampChain', () => {
    it('skips a leading chain the ramp does not serve', () => {
      expect(selectDefaultOnRampChain(buildAccountGlobal(['hyperliquid', 'robinhood']))).toBe('robinhood');
    });

    it('keeps the account order among the chains it does serve', () => {
      expect(selectDefaultOnRampChain(buildAccountGlobal(['solana', 'ton']))).toBe('ton');
    });

    it('answers nothing when the account has nothing to buy on', () => {
      expect(selectDefaultOnRampChain(buildAccountGlobal(['hyperliquid']))).toBeUndefined();
    });

    // The Buy button reads this and nothing else, so an answer the ramp then refuses would be a button
    // whose own click declines
    it('never answers with a chain the on-ramp refuses', () => {
      const allowedLists: (ApiBaseCurrency[] | undefined)[] = [undefined, [], ['USD'], ['RUB']];

      for (const allowed of allowedLists) {
        const global = buildAccountGlobal(CHAIN_ORDER, allowed);
        const chain = selectDefaultOnRampChain(global);

        expect(chain === undefined || selectIsOnRampAllowed(global, chain)).toBe(true);
      }
    });
  });

  // Both selectors are the choke point their entry points dispatch through, so a chain the ramp does
  // not serve has to be refused there and not only in whichever component happens to remember
  it('refuses both ramps on a chain that does not support them', () => {
    const global = buildRestrictedGlobal(undefined);

    for (const chain of CHAIN_ORDER) {
      expect(selectIsOnRampAllowed(global, chain)).toBe(getChainConfig(chain).isOnRampSupported);
      expect(selectIsOffRampAllowed(global, chain)).toBe(getChainConfig(chain).isOffRampSupported);
    }
  });
});
