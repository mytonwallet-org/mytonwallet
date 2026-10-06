import { Wallet } from 'ethers';

import { UNISWAP_PERMIT2_ADDRESS } from './constants';
import {
  buildPermit2PermitCall,
  buildUniswapBatchCalls,
  getUniswapAllowedTargets,
  hasUniswapPermitData,
  parseUniswapTransactionPayload,
  resolveSwapGasLimit,
  shouldIncludePermit2AllowanceCall,
  signUniswapPermit2,
} from './swap';

const SAMPLE_PAYLOAD = {
  routing: 'CLASSIC',
  requiresPermitSignature: false,
  approval: {
    to: '0xToken',
    from: '0xWallet',
    data: '0xapprove',
    value: '0',
    chainId: 11155111,
  },
  swap: {
    to: '0xRouter',
    from: '0xWallet',
    data: '0xswap',
    value: '0',
    chainId: 11155111,
  },
};

const PERMIT2_APPROVAL_PAYLOAD = {
  ...SAMPLE_PAYLOAD,
  approval: {
    ...SAMPLE_PAYLOAD.approval,
    to: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    // eslint-disable-next-line @stylistic/max-len
    data: '0x095ea7b3000000000000000000000000000000000022d473030f116ddee9f6b43ac78ba3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  },
  swap: {
    ...SAMPLE_PAYLOAD.swap,
    to: '0x23617e59A5925b2A4Bf75d73ff6711cD0b29De85',
  },
};

const PERMIT_DATA = {
  domain: {
    name: 'Permit2',
    chainId: 1,
    verifyingContract: UNISWAP_PERMIT2_ADDRESS,
  },
  types: {
    PermitSingle: [
      { name: 'details', type: 'PermitDetails' },
      { name: 'spender', type: 'address' },
      { name: 'sigDeadline', type: 'uint256' },
    ],
    PermitDetails: [
      { name: 'token', type: 'address' },
      { name: 'amount', type: 'uint160' },
      { name: 'expiration', type: 'uint48' },
      { name: 'nonce', type: 'uint48' },
    ],
  },
  values: {
    details: {
      token: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      amount: '100000',
      expiration: '1790073185',
      nonce: '0',
    },
    spender: '0x23617e59A5925b2A4Bf75d73ff6711cD0b29De85',
    sigDeadline: '1790073185',
  },
};

const PERMIT_WALLET = Wallet.createRandom();

const PERMIT2_PERMIT_PAYLOAD = {
  ...PERMIT2_APPROVAL_PAYLOAD,
  requiresPermitSignature: true,
  permitData: PERMIT_DATA,
  approval: {
    ...PERMIT2_APPROVAL_PAYLOAD.approval,
    from: PERMIT_WALLET.address,
  },
  swap: {
    ...PERMIT2_APPROVAL_PAYLOAD.swap,
    from: PERMIT_WALLET.address,
  },
};

describe('buildUniswapBatchCalls', () => {
  it('builds approve + swap calls from backend payload', () => {
    expect(buildUniswapBatchCalls(SAMPLE_PAYLOAD)).toEqual([
      { to: '0xToken', value: 0n, data: '0xapprove' },
      { to: '0xRouter', value: 0n, data: '0xswap' },
    ]);
  });

  it('inserts Permit2.approve fallback when permitData is absent', () => {
    const calls = buildUniswapBatchCalls(PERMIT2_APPROVAL_PAYLOAD);

    expect(calls).toHaveLength(3);
    expect(calls[1].to).toBe(UNISWAP_PERMIT2_ADDRESS);
    expect(calls[1].data).toMatch(/^0x87517c45/);
  });

  it('uses a signed Permit2.permit call for backend permitData batches', async () => {
    const permitSignature = await signUniswapPermit2('mainnet', PERMIT_WALLET.privateKey, PERMIT_DATA);
    const calls = buildUniswapBatchCalls(PERMIT2_PERMIT_PAYLOAD, permitSignature);

    expect(calls).toHaveLength(3);
    expect(calls[1]).toEqual(buildPermit2PermitCall(
      PERMIT2_PERMIT_PAYLOAD.swap.from,
      PERMIT_DATA,
      permitSignature,
    ));
    expect(calls[1].data).toMatch(/^0x2b67b570/);
    expect(calls[2].to).toBe(PERMIT2_PERMIT_PAYLOAD.swap.to);
  });

  it('builds swap-only batch when approval is absent', () => {
    const payload = { ...SAMPLE_PAYLOAD, approval: undefined };

    expect(buildUniswapBatchCalls(payload)).toEqual([
      { to: '0xRouter', value: 0n, data: '0xswap' },
    ]);
  });
});

describe('hasUniswapPermitData', () => {
  it('detects backend permitData payloads', () => {
    expect(hasUniswapPermitData(PERMIT2_PERMIT_PAYLOAD)).toBe(true);
    expect(hasUniswapPermitData(PERMIT2_APPROVAL_PAYLOAD)).toBe(false);
  });
});

describe('shouldIncludePermit2AllowanceCall', () => {
  it('returns false when permitData is provided', () => {
    expect(shouldIncludePermit2AllowanceCall(PERMIT2_PERMIT_PAYLOAD)).toBe(false);
  });

  it('returns true when ERC20 approve targets Permit2 without permitData', () => {
    expect(shouldIncludePermit2AllowanceCall(PERMIT2_APPROVAL_PAYLOAD)).toBe(true);
  });
});

describe('parseUniswapTransactionPayload', () => {
  it('round-trips backend JSON payload', () => {
    const parsed = parseUniswapTransactionPayload(JSON.stringify(PERMIT2_PERMIT_PAYLOAD));

    expect(parsed.routing).toBe('CLASSIC');
    expect(parsed.permitData?.values.spender).toBe(PERMIT2_PERMIT_PAYLOAD.swap.to);
  });
});

describe('getUniswapAllowedTargets', () => {
  it('includes approval and swap targets', () => {
    expect(getUniswapAllowedTargets(SAMPLE_PAYLOAD)).toEqual(new Set([
      '0xtoken',
      '0xrouter',
    ]));
  });

  it('includes Permit2 for permitData batches', () => {
    expect(getUniswapAllowedTargets(PERMIT2_PERMIT_PAYLOAD)).toEqual(new Set([
      '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
      '0x23617e59a5925b2a4bf75d73ff6711cd0b29de85',
      UNISWAP_PERMIT2_ADDRESS.toLowerCase(),
    ]));
  });
});

describe('resolveSwapGasLimit', () => {
  it('applies swap gas headroom to eth_estimateGas result', () => {
    expect(resolveSwapGasLimit(182_181n)).toBe(273_271n);
  });

  it('prefers backend gasLimit when it is higher than buffered estimate', () => {
    expect(resolveSwapGasLimit(182_181n, '300000')).toBe(300_000n);
  });
});
