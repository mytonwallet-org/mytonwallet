import type { GlobalState } from '../types';

import {
  SOLANA,
  SOLANA_USDT_MAINNET,
  TON_USDT_MAINNET,
  TONCOIN,
  TRC20_USDT_MAINNET,
  TRX,
} from '../../config';
import { INITIAL_STATE } from '../initialState';
import { selectTokenMatchingCurrentTransferAddressSlow } from './transfer';

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
