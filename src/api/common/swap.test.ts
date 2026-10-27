import type { ApiActivity } from '../types';

import {
  ARC,
  BASE_USDC_MAINNET,
  ETH,
  ETH_USDT_MAINNET,
  HYPERLIQUID,
  MONAD,
  OPTIMISM,
  ROBINHOOD,
  SOLANA,
  SOLANA_USDC_MAINNET,
  TONCOIN,
} from '../../config';
import { getChainBySlug } from '../../util/tokens';
import { fetchStoredAccount } from './accounts';
import { callBackendPost } from './backend';
import { getBackendConfigCache } from './cache';
import {
  canHaveBackendDexSwap,
  getBackendDexHistoryAssetFilter,
  getSwapHistoryTokenFilter,
  getSwapItemSlug,
  isBackendDexSlug,
  swapItemToActivity,
  swapReplaceActivities,
} from './swap';

jest.mock('./accounts', () => ({
  ...jest.requireActual('./accounts'),
  fetchStoredAccount: jest.fn(),
}));
jest.mock('./backend', () => ({
  ...jest.requireActual('./backend'),
  callBackendPost: jest.fn(),
}));
jest.mock('./cache', () => ({
  ...jest.requireActual('./cache'),
  getBackendConfigCache: jest.fn(),
}));

const SOLANA_EXAMPLE_MINT = 'AymATz4TCL9sWNEEV9Kvyz45CHVhDZ6kUgjTJPzLpU9P';

describe('getSwapItemSlug', () => {
  it('passes legacy backend asset ids through unchanged', () => {
    expect(getSwapItemSlug('solana-usdc')).toBe('solana-usdc');
    expect(getSwapItemSlug('sol')).toBe('sol');
  });

  it('maps legacy TON symbol to the frontend TON slug', () => {
    expect(getSwapItemSlug('TON')).toBe(TONCOIN.slug);
  });

  it('uses chain context for legacy raw token addresses in locally-created swap items', () => {
    expect(getSwapItemSlug(SOLANA_USDC_MAINNET.tokenAddress, 'solana')).toBe(SOLANA_USDC_MAINNET.slug);
  });

  it('maps NewBackendId native assets to frontend native token slugs', () => {
    expect(getSwapItemSlug('ton:native')).toBe(TONCOIN.slug);
    expect(getSwapItemSlug('solana:native')).toBe('sol');
  });

  it('maps known NewBackendId token addresses to frontend token slugs', () => {
    expect(getSwapItemSlug(`solana:${SOLANA_USDC_MAINNET.tokenAddress}`)).toBe(SOLANA_USDC_MAINNET.slug);
    expect(getSwapItemSlug(`ethereum:${ETH_USDT_MAINNET.tokenAddress}`)).toBe(ETH_USDT_MAINNET.slug);
  });

  it('builds a frontend token slug for unknown NewBackendId token addresses', () => {
    expect(getSwapItemSlug(`solana:${SOLANA_EXAMPLE_MINT}`)).toBe('solana-aymatz4tcl');
  });

  it('does not require chain context for CEX cross-chain asset ids', () => {
    const activity = swapItemToActivity({
      id: '42',
      timestamp: 1,
      from: `solana:${SOLANA_EXAMPLE_MINT}`,
      fromAmount: '1',
      fromAddress: 'EQ-address',
      to: 'ton:native',
      toAmount: '2',
      status: 'pending',
      hashes: [],
      transactionIds: {},
      exchanger: 'near-intents',
      cexLabel: 'near-intents',
      cex: { status: 'waiting', transactionId: 'correlation-id' },
    } as any);

    expect(activity.from).toBe('solana-aymatz4tcl');
    expect(activity.to).toBe(TONCOIN.slug);
  });
});

describe('LI.FI history mapping', () => {
  it('keeps the actual alternate token and amount distinct from the original quote', () => {
    const activity = swapItemToActivity({
      id: '42', timestamp: 1,
      from: 'ethereum:native', fromAmount: '1', fromAddress: '0x123',
      to: 'arbitrum:0x3333333333333333333333333333333333333333', toAmount: '0.975',
      status: 'completed', hashes: [], transactionIds: {}, exchanger: 'lifi',
      lifi: {
        outcome: 'partial', quotedTo: 'arbitrum:0x1111111111111111111111111111111111111111',
        quotedToAmount: '1',
        received: {
          chain: 'arbitrum', tokenAddress: '0x3333333333333333333333333333333333333333',
          symbol: 'USDT', decimals: 6, amount: '0.975',
        },
      },
    } as any);

    expect(activity.to).toBe('arbitrum-0x33333333');
    expect(activity.toAmount).toBe('0.975');
    expect(activity.lifi?.outcome).toBe('partial');
    expect(activity.lifi?.quotedToAmount).toBe('1');
  });

  it('preserves terminal refund as a failed swap with refunded funds shown separately', () => {
    const activity = swapItemToActivity({
      id: '43', timestamp: 1,
      from: 'ethereum:native', fromAmount: '1', fromAddress: '0x123',
      to: 'ethereum:native', toAmount: '0.99',
      status: 'failed', hashes: [], transactionIds: {}, exchanger: 'lifi',
      lifi: { outcome: 'refunded', quotedTo: 'arbitrum:native', quotedToAmount: '1' },
    } as any);

    expect(activity.status).toBe('failed');
    expect(activity.lifi?.outcome).toBe('refunded');
    expect(activity.lifi?.quotedTo).toBe('arbitrum:native');
  });
});

describe('getSwapHistoryTokenFilter', () => {
  it('uses backend legacy asset ids for CEX history filters', () => {
    expect(getSwapHistoryTokenFilter(TONCOIN.slug)).toBe('TON');
    expect(getSwapHistoryTokenFilter(SOLANA.slug)).toBe(SOLANA.slug);
    expect(getSwapHistoryTokenFilter(ETH_USDT_MAINNET.slug)).toBe(ETH_USDT_MAINNET.tokenAddress);
  });
});

describe('backend DEX history reconciliation helpers', () => {
  it('recognizes TON and backend-supported EVM slugs as backend DEX candidates', () => {
    expect(isBackendDexSlug(TONCOIN.slug)).toBe(true);
    expect(isBackendDexSlug(ETH.slug)).toBe(true);
    expect(isBackendDexSlug(BASE_USDC_MAINNET.slug)).toBe(true);
    expect(isBackendDexSlug(OPTIMISM.slug)).toBe(true);
    expect(isBackendDexSlug(MONAD.slug)).toBe(true);
    expect(isBackendDexSlug(HYPERLIQUID.slug)).toBe(true);
    expect(isBackendDexSlug(ROBINHOOD.slug)).toBe(true);
    expect(isBackendDexSlug(ARC.slug)).toBe(true);
    expect(canHaveBackendDexSwap(TONCOIN.slug, [])).toBe(true);
    expect(canHaveBackendDexSwap(ETH.slug, [])).toBe(true);
  });

  it.each([
    [ROBINHOOD.slug, 'robinhood', ROBINHOOD.symbol],
    [ARC.slug, 'arc', ARC.symbol],
  ])('loads backend DEX history for %s activities', async (slug, chain, asset) => {
    expect(getChainBySlug(slug)).toBe(chain);
    jest.mocked(fetchStoredAccount).mockResolvedValue({
      byChain: { ton: { address: 'EQ-history' }, [chain]: { address: '0xwallet' } },
    } as never);
    jest.mocked(getBackendConfigCache).mockResolvedValue({ swapVersion: 2 } as never);
    jest.mocked(callBackendPost).mockResolvedValue([]);
    jest.mocked(callBackendPost).mockClear();

    const chainActivities = [activity({ slug })];
    expect(await swapReplaceActivities('0-mainnet', chainActivities, slug)).toEqual(chainActivities);
    expect(callBackendPost).toHaveBeenCalledWith('/swap/history/EQ-history', expect.objectContaining({
      asset,
      isCex: false,
    }), expect.any(Object));
  });

  it('keeps unsupported non-backend-DEX chains out of backend DEX history', () => {
    expect(isBackendDexSlug(SOLANA.slug)).toBe(false);
    expect(canHaveBackendDexSwap(SOLANA.slug, [])).toBe(false);
    expect(canHaveBackendDexSwap(undefined, [activity({ slug: SOLANA.slug })])).toBe(false);
  });

  it('detects backend DEX candidates from activity token slugs when no slug filter is selected', () => {
    expect(canHaveBackendDexSwap(undefined, [activity({ slug: ETH.slug })])).toBe(true);
    expect(canHaveBackendDexSwap(undefined, [swapActivity({
      from: ETH.slug,
      to: BASE_USDC_MAINNET.slug,
    })])).toBe(true);
  });

  it('uses backend asset ids for backend DEX history filters', () => {
    expect(getBackendDexHistoryAssetFilter(TONCOIN.slug)).toBe(TONCOIN.symbol);
    expect(getBackendDexHistoryAssetFilter(ETH.slug)).toBe(ETH.symbol);
    expect(getBackendDexHistoryAssetFilter(BASE_USDC_MAINNET.slug)).toBe(BASE_USDC_MAINNET.tokenAddress);
  });
});

function activity({ slug }: { slug: string }): ApiActivity {
  return {
    id: 'tx-id',
    kind: 'transaction',
    timestamp: 1,
    slug,
  } as ApiActivity;
}

function swapActivity({ from, to }: { from: string; to: string }): ApiActivity {
  return {
    id: 'swap-id',
    kind: 'swap',
    timestamp: 1,
    from,
    to,
  } as ApiActivity;
}
