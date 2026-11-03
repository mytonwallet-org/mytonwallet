import { Interface } from 'ethers';

import type { EvmSwapTransactionPayload } from './swap';
import type { EvmSwapIntent } from './swapBinding';

import { getTokenByAddress } from '../../common/tokens';
import { LIFI_CONTRACTS, UNISWAP_PERMIT2_ADDRESS } from './constants';
import {
  bindEvmSwapPayload,
  bindEvmSwapTransactionRequest,
  buildEvmSwapIntent,
  SWAP_PERMIT2_LIFETIME_SECONDS,
} from './swapBinding';

jest.mock('../../common/tokens', () => ({ getTokenByAddress: jest.fn() }));

const NOW = 1_800_000_000;
const OWNER = '0x1111111111111111111111111111111111111111';
const HOSTILE = '0x00000000000000000000000000000000DeaDBeef';
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const UNIVERSAL_ROUTER = '0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af';

const erc20Interface = new Interface([
  'function approve(address spender, uint256 amount)',
  'function transfer(address to, uint256 amount)',
]);
const wrappedNativeInterface = new Interface(['function deposit()', 'function withdraw(uint256 amount)']);

const USDC_INTENT: EvmSwapIntent = {
  chainId: 1,
  owner: OWNER,
  sellToken: USDC,
  maxSellAmount: 2_000_000n,
  maxNativeFee: 0n,
};

const ETH_INTENT: EvmSwapIntent = {
  chainId: 1,
  owner: OWNER,
  buyToken: USDC,
  maxSellAmount: 10n ** 16n,
  maxNativeFee: 0n,
};

function tx(to: string, data: string, value = '0') {
  return { to, from: HOSTILE, data, value, chainId: 1 };
}

const UNISWAP_APPROVAL_PERMIT_PAYLOAD: EvmSwapTransactionPayload = {
  routing: 'CLASSIC',
  requiresPermitSignature: true,
  approval: tx(USDC, erc20Interface.encodeFunctionData('approve', [UNISWAP_PERMIT2_ADDRESS, (1n << 256n) - 1n])),
  permitData: {
    domain: { name: 'Permit2', chainId: 1, verifyingContract: UNISWAP_PERMIT2_ADDRESS },
    types: {},
    values: {
      details: { token: USDC, amount: String((1n << 160n) - 1n), expiration: '1802592000', nonce: '3' },
      spender: UNIVERSAL_ROUTER,
      sigDeadline: '1800001800',
    },
  },
  swap: tx(UNIVERSAL_ROUTER, '0x3593564c'),
};

const LIFI_PERMIT2_PAYLOAD: EvmSwapTransactionPayload = {
  provider: 'lifi',
  approval: UNISWAP_APPROVAL_PERMIT_PAYLOAD.approval,
  lifiPermit2: {
    token: USDC,
    amount: '2000000',
    permit2: UNISWAP_PERMIT2_ADDRESS,
    permit2Proxy: LIFI_CONTRACTS.ethereum!.permit2Proxy,
    deadlineSeconds: 7 * 24 * 3600,
    transactionRequest: tx(LIFI_CONTRACTS.ethereum!.diamond, '0xa6010a66'),
  },
};

function bind(payload: EvmSwapTransactionPayload, intent = USDC_INTENT) {
  return bindEvmSwapPayload('ethereum', payload, intent, NOW);
}

function binding(payload: EvmSwapTransactionPayload, intent = USDC_INTENT) {
  return () => bind(payload, intent);
}

beforeEach(() => {
  jest.mocked(getTokenByAddress).mockReturnValue({ decimals: 6 } as never);
});

describe('buildEvmSwapIntent', () => {
  it.each([
    ['bounds an exact-in sale by the amount the user entered', { from: USDC, to: 'eth', fromAmount: '2.5' }, {
      sellToken: USDC, buyToken: undefined, maxSellAmount: 2_500_000n, maxNativeFee: 0n,
    }],
    ['adds the slippage to an exact-out sale, rounding up', {
      from: USDC, to: 'eth', fromAmount: '1.000001', swapMode: 'exact_out', slippage: 0.5,
    }, { maxSellAmount: 1_005_002n }],
    ['sells the native coin with its own decimals and keeps the network fee the user saw', {
      from: 'eth', to: USDC, fromAmount: '0.01', networkFee: '0.0002',
    }, { sellToken: undefined, buyToken: USDC, maxSellAmount: 10n ** 16n, maxNativeFee: 2n * 10n ** 14n }],
    ['rounds an 18-decimal exact-out bound up without losing a unit', {
      from: 'eth', to: USDC, fromAmount: '1.000000000000000001', swapMode: 'exact_out', slippage: 0.3,
    }, { maxSellAmount: 1_003_000_000_000_000_002n }],
  ] as const)('%s', (_, order, expected) => {
    expect(buildEvmSwapIntent('ethereum', 1, OWNER, order))
      .toEqual(expect.objectContaining({ chainId: 1, owner: OWNER, ...expected }));
  });

  it('refuses the native coin of another chain', () => {
    expect(() => buildEvmSwapIntent('bnb', 56, OWNER, { from: 'eth', to: USDC, fromAmount: '1' }))
      .toThrow('Sold coin is not native to the swap chain');
  });

  it('refuses a token it cannot price', () => {
    jest.mocked(getTokenByAddress).mockReturnValue(undefined);

    expect(() => buildEvmSwapIntent('ethereum', 1, OWNER, { from: USDC, to: 'eth', fromAmount: '1' }))
      .toThrow('Unknown sell token');
  });
});

describe('bindEvmSwapPayload for Uniswap', () => {
  it('rebuilds the permit for the swap amount with a short lifetime on the canonical Permit2', () => {
    const { permitData } = bind(UNISWAP_APPROVAL_PERMIT_PAYLOAD);

    expect(permitData).toEqual({
      domain: { name: 'Permit2', chainId: 1, verifyingContract: UNISWAP_PERMIT2_ADDRESS },
      types: expect.objectContaining({ PermitSingle: expect.any(Array), PermitDetails: expect.any(Array) }),
      values: {
        details: {
          token: USDC,
          amount: '2000000',
          expiration: String(NOW + SWAP_PERMIT2_LIFETIME_SECONDS),
          nonce: '3',
        },
        spender: UNIVERSAL_ROUTER,
        sigDeadline: String(NOW + SWAP_PERMIT2_LIFETIME_SECONDS),
      },
    });
  });

  it('rebuilds the approval for Permit2 on the sold token and sends every call from the owner', () => {
    const { approval, swap } = bind(UNISWAP_APPROVAL_PERMIT_PAYLOAD);

    expect(approval).toEqual(expect.objectContaining({
      from: OWNER,
      to: USDC,
      value: '0',
      data: erc20Interface.encodeFunctionData('approve', [UNISWAP_PERMIT2_ADDRESS, (1n << 256n) - 1n]),
    }));
    expect(swap?.from).toBe(OWNER);
  });

  it('bounds the Permit2 allowance it grants without a permit signature', () => {
    const bound = bind({
      ...UNISWAP_APPROVAL_PERMIT_PAYLOAD,
      permitData: undefined,
      requiresPermitSignature: false,
    });

    expect(bound.permit2Allowance).toEqual({
      token: USDC,
      spender: UNIVERSAL_ROUTER,
      amount: '2000000',
      expiration: String(NOW + SWAP_PERMIT2_LIFETIME_SECONDS),
    });
  });

  it('grants no Permit2 allowance to a token sale without an approval, whatever the backend sends', () => {
    const bound = bind({
      ...UNISWAP_APPROVAL_PERMIT_PAYLOAD,
      approval: undefined,
      permitData: undefined,
      permit2Allowance: {
        token: USDC, spender: HOSTILE, amount: String((1n << 160n) - 1n), expiration: String((1n << 48n) - 1n),
      },
    });

    expect(bound.permit2Allowance).toBeUndefined();
  });

  it('grants no Permit2 allowance for a native sale', () => {
    const bound = bind({ routing: 'CLASSIC', swap: tx(UNIVERSAL_ROUTER, '0x3593564c', '1') }, ETH_INTENT);

    expect(bound.permit2Allowance).toBeUndefined();
  });

  it.each([
    ['a swap target that is not a Universal Router', {
      swap: tx(USDC, erc20Interface.encodeFunctionData('transfer', [HOSTILE, 1n])),
    }, 'Universal Router'],
    ['the address of the Base router, which is another contract on Ethereum', {
      swap: tx('0xd6145b2D3F379919E8CdEda7B97e37c4b2Ca9c40', '0x06fdde03'),
    }, 'Universal Router'],
    ['an approval on another token', {
      approval: tx(WETH, erc20Interface.encodeFunctionData('approve', [UNISWAP_PERMIT2_ADDRESS, 1n])),
    }, 'sold token'],
    ['an approval for another spender', {
      approval: tx(USDC, erc20Interface.encodeFunctionData('approve', [HOSTILE, 1n])),
    }, 'spender'],
    ['an approval that is not an approve call', {
      approval: tx(USDC, erc20Interface.encodeFunctionData('transfer', [HOSTILE, 1n])),
    }, 'not an ERC-20 approve'],
    ['a permit for another token', {
      permitData: {
        ...UNISWAP_APPROVAL_PERMIT_PAYLOAD.permitData!,
        values: {
          ...UNISWAP_APPROVAL_PERMIT_PAYLOAD.permitData!.values,
          details: { ...UNISWAP_APPROVAL_PERMIT_PAYLOAD.permitData!.values.details, token: WETH },
        },
      },
    }, 'sold token'],
    ['native value on a token sale', { swap: tx(UNIVERSAL_ROUTER, '0x3593564c', '1') }, 'Native value'],
    ['a call on another chain', { swap: { ...tx(UNIVERSAL_ROUTER, '0x3593564c'), chainId: 8453 } }, 'another chain'],
    ['a UniswapX order', { routing: 'DUTCH_V2' }, 'Unsupported Uniswap routing'],
  ])('refuses %s', (_, override, reason) => {
    expect(binding({ ...UNISWAP_APPROVAL_PERMIT_PAYLOAD, ...override } as EvmSwapTransactionPayload)).toThrow(reason);
  });

  it('caps the native value of a native sale by the amount sold', () => {
    const payload = { routing: 'CLASSIC', swap: tx(UNIVERSAL_ROUTER, '0x3593564c', String(10n ** 16n)) };

    expect(binding(payload, ETH_INTENT)).not.toThrow();
    expect(binding({ ...payload, swap: { ...payload.swap, value: String(10n ** 16n + 1n) } }, ETH_INTENT))
      .toThrow('Native value');
  });

  it('accepts unwrapping no more than the amount sold on the sold token', () => {
    const intent = { ...USDC_INTENT, sellToken: WETH, maxSellAmount: 5n };
    const unwrap = (to: string, amount: bigint) => ({
      routing: 'UNWRAP',
      swap: tx(to, wrappedNativeInterface.encodeFunctionData('withdraw', [amount])),
    });

    expect(binding(unwrap(WETH, 5n), intent)).not.toThrow();
    expect(binding(unwrap(WETH, 6n), intent)).toThrow('Wrap call');
    expect(binding(unwrap(USDC, 5n), intent)).toThrow('Wrap target');
  });

  it('accepts wrapping into the bought token with the amount sold', () => {
    const intent = { ...ETH_INTENT, buyToken: WETH };
    const wrap = (data: string, value: bigint) => ({ routing: 'WRAP', swap: tx(WETH, data, String(value)) });

    expect(binding(wrap(wrappedNativeInterface.encodeFunctionData('deposit'), 10n ** 16n), intent)).not.toThrow();
    expect(binding(wrap(erc20Interface.encodeFunctionData('transfer', [HOSTILE, 1n]), 0n), intent))
      .toThrow('Wrap call');
  });
});

describe('bindEvmSwapPayload for LI.FI', () => {
  it('pins the Permit2 contract, the proxy and the lifetime of the transfer it signs', () => {
    const { lifiPermit2 } = bind(LIFI_PERMIT2_PAYLOAD);

    expect(lifiPermit2).toEqual(expect.objectContaining({
      token: USDC,
      amount: '2000000',
      permit2: UNISWAP_PERMIT2_ADDRESS,
      permit2Proxy: LIFI_CONTRACTS.ethereum!.permit2Proxy,
      deadlineSeconds: SWAP_PERMIT2_LIFETIME_SECONDS,
    }));
  });

  it.each([
    ['another Permit2 contract', { permit2: HOSTILE }, 'Permit2 contract'],
    ['another proxy', { permit2Proxy: HOSTILE }, 'proxy'],
    ['another token', { token: WETH }, 'sold token'],
    ['more than the swap amount', { amount: '2000001' }, 'exceeds the swap amount'],
    ['a witness for another Diamond', { witness: { diamondAddress: HOSTILE } }, 'another Diamond'],
    ['native value above the fee the user saw', {
      transactionRequest: tx(LIFI_CONTRACTS.ethereum!.diamond, '0xa6010a66', '1'),
    }, 'Native value'],
  ])('refuses a transfer to %s', (_, override, reason) => {
    expect(binding({
      ...LIFI_PERMIT2_PAYLOAD,
      lifiPermit2: { ...LIFI_PERMIT2_PAYLOAD.lifiPermit2!, ...override },
    })).toThrow(reason);
  });

  it('signs the witness for the pinned LI.FI Diamond', () => {
    const { lifiPermit2 } = bind({
      ...LIFI_PERMIT2_PAYLOAD,
      lifiPermit2: {
        ...LIFI_PERMIT2_PAYLOAD.lifiPermit2!,
        witness: { diamondAddress: LIFI_CONTRACTS.ethereum!.diamond.toLowerCase() },
      },
    });

    expect(lifiPermit2?.witness).toEqual({ diamondAddress: LIFI_CONTRACTS.ethereum!.diamond });
  });

  it('refuses a LI.FI payload without a Permit2 transfer', () => {
    expect(binding({ provider: 'lifi', swap: tx(LIFI_CONTRACTS.ethereum!.diamond, '0x01') }))
      .toThrow('no Permit2 transfer');
  });
});

describe('bindEvmSwapTransactionRequest', () => {
  const request = { ...tx(LIFI_CONTRACTS.base!.diamond, '0xa6010a66', String(10n ** 16n)), chainId: 8453 };
  const intent = { ...ETH_INTENT, chainId: 8453 };

  it('sends a native sale to the LI.FI Diamond from the owner', () => {
    expect(bindEvmSwapTransactionRequest('base', request, intent)).toEqual({ ...request, from: OWNER });
  });

  it.each([
    ['monad', 143],
    ['hyperliquid', 999],
  ] as const)('sends a native sale to the LI.FI Diamond of %s', (chain, chainId) => {
    const sale = { ...tx(LIFI_CONTRACTS[chain]!.diamond, '0xa6010a66', String(10n ** 16n)), chainId };

    expect(bindEvmSwapTransactionRequest(chain, sale, { ...ETH_INTENT, chainId })).toEqual({ ...sale, from: OWNER });
  });

  it('keeps the backend gas limit and drops its gas prices', () => {
    const priced = {
      ...request,
      gasLimit: '500000',
      gasPrice: String(10n ** 18n),
      maxFeePerGas: String(10n ** 18n),
      maxPriorityFeePerGas: String(10n ** 18n),
    };

    expect(bindEvmSwapTransactionRequest('base', priced, intent))
      .toEqual({ ...request, from: OWNER, gasLimit: '500000' });
  });

  it.each([
    ['another target', { to: HOSTILE }, 'LI.FI Diamond'],
    ['another chain', { chainId: 1 }, 'another chain'],
    ['more native value than sold', { value: String(10n ** 16n + 1n) }, 'Native value'],
  ])('refuses %s', (_, override, reason) => {
    expect(() => bindEvmSwapTransactionRequest('base', { ...request, ...override }, intent)).toThrow(reason);
  });

  it('refuses a token sale, which only a Permit2 transfer may carry', () => {
    const tokenSale = { ...USDC_INTENT, chainId: 8453 };

    expect(() => bindEvmSwapTransactionRequest('base', { ...request, value: '0' }, tokenSale))
      .toThrow('Permit2 transfer');
  });
});
