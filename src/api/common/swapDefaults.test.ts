import type { ApiSwapDefaultsRequest, ApiToken } from '../types';

import {
  ETH, ETH_USDC_MAINNET, ETH_USDT_MAINNET, MONAD, ROBINHOOD, SOLANA, SOLANA_USDC_MAINNET, SOLANA_USDT_MAINNET,
  TON_USDT_MAINNET, TON_USDT_TESTNET, TONCOIN,
} from '../../config';
import { resolveSwapDefaults } from './swapDefaults';

const stock: ApiToken = { slug: 'solana-nvdax', name: 'NVIDIA', symbol: 'NVDAx', decimals: 6, chain: 'solana' };

function resolve(overrides: Partial<ApiSwapDefaultsRequest> = {}) {
  return resolveSwapDefaults({
    accountChains: ['solana', 'ethereum', 'ton'],
    network: 'mainnet',
    balancesUsdBySlug: {},
    ...overrides,
  });
}

const priorities: {
  name: string;
  fixed: ApiToken;
  request?: Partial<ApiSwapDefaultsRequest>;
  sellOpposite: ApiToken;
  buyOpposite: ApiToken;
}[] = [
  {
    name: 'native: a tiny same-chain stable balance precedes richer foreign holdings',
    fixed: SOLANA,
    request: { balancesUsdBySlug: {
      [SOLANA_USDC_MAINNET.slug]: 0.000001, [TON_USDT_MAINNET.slug]: 1000, [ETH.slug]: 2000,
    } },
    sellOpposite: SOLANA_USDC_MAINNET, buyOpposite: SOLANA_USDC_MAINNET,
  },
  {
    name: 'native: foreign stablecoins precede foreign native tokens',
    fixed: SOLANA,
    request: { balancesUsdBySlug: {
      [TON_USDT_MAINNET.slug]: 20, [ETH_USDC_MAINNET.slug]: 10, [ETH.slug]: 2000,
    } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: TON_USDT_MAINNET,
  },
  {
    name: 'native: foreign native tokens are the last funded option',
    fixed: SOLANA,
    request: { balancesUsdBySlug: { [ETH.slug]: 2000, [TONCOIN.slug]: 2 } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: ETH,
  },
  {
    name: 'native: owning only the fixed asset still falls back to its stablecoin',
    fixed: SOLANA,
    request: { balancesUsdBySlug: { [SOLANA.slug]: 10000 } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: SOLANA_USDT_MAINNET,
  },
  {
    name: 'stablecoin: same-chain native comes first',
    fixed: SOLANA_USDC_MAINNET,
    request: { balancesUsdBySlug: {
      [SOLANA.slug]: 1e-7, [TON_USDT_MAINNET.slug]: 1000, [ETH.slug]: 2000,
    } },
    sellOpposite: SOLANA, buyOpposite: SOLANA,
  },
  {
    name: 'stablecoin: another stablecoin on the same chain is not a candidate',
    fixed: SOLANA_USDC_MAINNET,
    request: { balancesUsdBySlug: {
      [SOLANA_USDT_MAINNET.slug]: 10000, [TON_USDT_MAINNET.slug]: 0.000001, [ETH.slug]: 2000,
    } },
    sellOpposite: SOLANA, buyOpposite: TON_USDT_MAINNET,
  },
  {
    name: 'stablecoin: foreign native is used when earlier options have no balance',
    fixed: SOLANA_USDC_MAINNET,
    request: { balancesUsdBySlug: { [ETH.slug]: 2e-15 } },
    sellOpposite: SOLANA, buyOpposite: ETH,
  },
  {
    name: 'stablecoin: all-zero balances fall back to same-chain native',
    fixed: SOLANA_USDC_MAINNET,
    sellOpposite: SOLANA, buyOpposite: SOLANA,
  },
  {
    name: 'ordinary token: same-chain stablecoins precede same-chain native',
    fixed: stock,
    request: { balancesUsdBySlug: { [SOLANA_USDC_MAINNET.slug]: 0.000001, [SOLANA.slug]: 100 } },
    sellOpposite: SOLANA_USDC_MAINNET, buyOpposite: SOLANA_USDC_MAINNET,
  },
  {
    name: 'ordinary token: same-chain native precedes foreign stablecoins',
    fixed: stock,
    request: { balancesUsdBySlug: { [SOLANA.slug]: 1e-7, [TON_USDT_MAINNET.slug]: 1000 } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: SOLANA,
  },
  {
    name: 'ordinary token: foreign stablecoins precede foreign native',
    fixed: stock,
    request: { balancesUsdBySlug: { [TON_USDT_MAINNET.slug]: 0.000001, [ETH.slug]: 2000 } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: TON_USDT_MAINNET,
  },
  {
    name: 'ordinary token: foreign native is the last funded option',
    fixed: stock,
    request: { balancesUsdBySlug: { [ETH.slug]: 2e-15 } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: ETH,
  },
  {
    name: 'ordinary token: all-zero balances fall back to same-chain stablecoin',
    fixed: stock,
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: SOLANA_USDT_MAINNET,
  },
  {
    name: 'missing local stablecoin: a valid foreign stable precedes a funded foreign native for sales',
    fixed: ROBINHOOD,
    request: { accountChains: ['solana', 'ethereum', 'robinhood'], balancesUsdBySlug: {
      [ETH.slug]: 2000, [SOLANA.slug]: 100,
    } },
    sellOpposite: SOLANA_USDT_MAINNET, buyOpposite: ETH,
  },
  {
    name: 'no configured stablecoins: foreign native is valid even with zero balance',
    fixed: ROBINHOOD,
    request: { accountChains: ['robinhood', 'monad'] },
    sellOpposite: MONAD, buyOpposite: MONAD,
  },
];

describe('resolveSwapDefaults', () => {
  describe.each(priorities)('$name', ({ fixed, request, sellOpposite, buyOpposite }) => {
    it('selling picks the first valid candidate', () => {
      const result = resolve({ ...request, tokenIn: fixed });
      expect(result.tokenIn).toEqual(fixed);
      expect(result.tokenOut?.slug).toBe(sellOpposite.slug);
      expect(result.tokenIn?.slug).not.toBe(result.tokenOut?.slug);
      expect(Object.keys(result).sort()).toEqual(['tokenIn', 'tokenOut']);
    });

    it('buying picks the first funded candidate or the first candidate if all are zero', () => {
      const result = resolve({ ...request, tokenOut: fixed });
      expect(result.tokenOut).toEqual(fixed);
      expect(result.tokenIn?.slug).toBe(buyOpposite.slug);
      expect(result.tokenIn?.slug).not.toBe(result.tokenOut?.slug);
    });
  });

  it('ranks balances by USD value within a priority group', () => {
    const result = resolve({ tokenOut: stock, balancesUsdBySlug: {
      [ETH.slug]: 2000, [TONCOIN.slug]: 1000,
    } });
    expect(result.tokenIn?.slug).toBe(ETH.slug);
  });

  it('ignores ordinary holdings when choosing a destination for native sales', () => {
    const result = resolve({ tokenIn: SOLANA, balancesUsdBySlug: { [stock.slug]: 1e14 } });
    expect(result.tokenOut?.slug).toBe(SOLANA_USDT_MAINNET.slug);
  });

  it('chooses the two largest basic holdings for an empty form without a chain', () => {
    const result = resolve({ balancesUsdBySlug: {
      [ETH.slug]: 2000, [TON_USDT_MAINNET.slug]: 1000, [stock.slug]: 1e8,
    } });
    expect(result.tokenIn?.slug).toBe(ETH.slug);
    expect(result.tokenOut?.slug).toBe(TON_USDT_MAINNET.slug);
  });

  it('uses a same-chain counterpart when only one basic holding is funded', () => {
    const result = resolve({ balancesUsdBySlug: { [TON_USDT_MAINNET.slug]: 0.000001 } });
    expect(result.tokenIn?.slug).toBe(TON_USDT_MAINNET.slug);
    expect(result.tokenOut?.slug).toBe(TONCOIN.slug);
  });

  it('uses UI account order for an empty wallet and ignores ordinary holdings', () => {
    const result = resolve({ accountChains: ['ethereum', 'solana'], balancesUsdBySlug: { [stock.slug]: 100000 } });
    expect(result.tokenIn?.slug).toBe(ETH.slug);
    expect(result.tokenOut?.slug).toBe(ETH_USDT_MAINNET.slug);
  });

  it('preserves both explicit sides even without balances or an account chain', () => {
    expect(resolve({ tokenIn: ETH, tokenOut: stock, accountChains: [] }))
      .toEqual({ tokenIn: ETH, tokenOut: stock });
  });

  it('does not treat a token with a stablecoin symbol as a configured stablecoin', () => {
    const impostor = { ...stock, slug: 'solana-impostor', symbol: 'USDC' };
    const result = resolve({ tokenOut: impostor, balancesUsdBySlug: { [SOLANA_USDC_MAINNET.slug]: 1 } });
    expect(result.tokenIn?.slug).toBe(SOLANA_USDC_MAINNET.slug);
  });

  it('treats unpriced holdings as zero USD and uses the first valid fallback', () => {
    const result = resolve({ tokenOut: stock, balancesUsdBySlug: { [ETH.slug]: 0 } });
    expect(result.tokenIn?.slug).toBe(SOLANA_USDT_MAINNET.slug);
  });

  it('ignores balances from chains outside the account', () => {
    const result = resolve({ accountChains: ['solana'], tokenOut: stock, balancesUsdBySlug: { [ETH.slug]: 2e-15 } });
    expect(result.tokenIn?.slug).toBe(SOLANA_USDT_MAINNET.slug);
  });

  it('uses a stablecoin from the selected network', () => {
    const result = resolve({ accountChains: ['ton'], network: 'testnet', tokenIn: TONCOIN });
    expect(result.tokenOut?.slug).toBe(TON_USDT_TESTNET.slug);
  });

  it('leaves either missing side empty when no distinct configured token exists', () => {
    expect(resolve({ accountChains: ['robinhood'] })).toEqual({ tokenIn: ROBINHOOD, tokenOut: undefined });
    expect(resolve({ accountChains: ['robinhood'], tokenIn: ROBINHOOD }))
      .toEqual({ tokenIn: ROBINHOOD, tokenOut: undefined });
    expect(resolve({ accountChains: ['robinhood'], tokenOut: ROBINHOOD }))
      .toEqual({ tokenIn: undefined, tokenOut: ROBINHOOD });
  });

  it('leaves an empty form empty when no account chain is available', () => {
    expect(resolve({ accountChains: [] })).toEqual({ tokenIn: undefined, tokenOut: undefined });
  });
});
