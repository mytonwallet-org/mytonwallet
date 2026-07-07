import {
  ETH_USDT_MAINNET,
  SOLANA,
  SOLANA_USDC_MAINNET,
  TONCOIN,
} from '../../config';
import { getSwapHistoryTokenFilter, getSwapItemSlug, swapItemToActivity } from './swap';

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

describe('getSwapHistoryTokenFilter', () => {
  it('uses backend legacy asset ids for CEX history filters', () => {
    expect(getSwapHistoryTokenFilter(TONCOIN.slug)).toBe('TON');
    expect(getSwapHistoryTokenFilter(SOLANA.slug)).toBe(SOLANA.slug);
    expect(getSwapHistoryTokenFilter(ETH_USDT_MAINNET.slug)).toBe(ETH_USDT_MAINNET.tokenAddress);
  });
});
