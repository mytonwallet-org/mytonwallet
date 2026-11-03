import { TypedDataEncoder } from 'ethers';

import { perpsWithdrawalFixture } from '../../../../tests/helpers/perpsWithdrawal';
import {
  assertHyperliquidExchangeBuildIntegrity,
  assertHyperliquidWithdrawPermitIntegrity,
  HYPERLIQUID_BRIDGE_CHAIN_ID,
} from './hyperliquidPayloadValidation';

const WALLET = '0x1111111111111111111111111111111111111111';
const ATTACKER = '0x2222222222222222222222222222222222222222';
const BUILDER = '0x09e8ed1a77387a6e4be4f0ee7ad2f6e1917a768b';
const BUILDER_ORDER_FEE = 88;

// Fixed vectors from the backend's Hyperliquid SDK actionHash, which follows the official Python SDK.
const l1Vectors: [Record<string, unknown>, string][] = [
  [{
    type: 'order', grouping: 'na',
    builder: { b: BUILDER, f: BUILDER_ORDER_FEE },
    orders: [{ a: 0, b: true, p: '95000', s: '0.1', r: false, t: { limit: { tif: 'Ioc' } } }],
  }, '0x2fbfed4a403d395a56f9ddbad3fc00ecc08a526b941ec6c4ecbc59ab4fead353'],
  [{ type: 'updateLeverage', asset: 110000, isCross: false, leverage: 10 },
    '0x12647633c457799499faf86e6cec8550b0daed85c3626f83d178521deb025095'],
];

function backendAgentTypedData(connectionId: string) {
  return {
    domain: { name: 'Exchange', version: '1', chainId: 1337,
      verifyingContract: '0x0000000000000000000000000000000000000000' },
    types: { Agent: [{ name: 'source', type: 'string' }, { name: 'connectionId', type: 'bytes32' }] },
    primaryType: 'Agent',
    message: { source: 'a', connectionId },
  };
}

test.each(l1Vectors)('accepts the backend Agent payload for %j', (action, connectionId) => {
  const typedData = backendAgentTypedData(connectionId);
  expect(assertHyperliquidExchangeBuildIntegrity({ action, nonce: 1700000000123, typedData })).toBe(typedData);
});

test.each([
  ['p', '1.2840'], ['s', '30.0'], ['p', '01.2'], ['s', '1e-5'],
])('rejects noncanonical order %s before signing', (field, value) => {
  const action = {
    type: 'order',
    orders: [{ a: 25, b: false, p: '1.284', s: '30', r: true, t: { limit: { tif: 'Ioc' } }, [field]: value }],
    grouping: 'na',
    builder: { b: BUILDER, f: BUILDER_ORDER_FEE },
  };
  expect(() => assertHyperliquidExchangeBuildIntegrity({
    action, nonce: 1700000000123, typedData: backendAgentTypedData(l1Vectors[0][1]),
  })).toThrow(/Wire order (price|size) is invalid/u);
  expect(action.orders[0][field as 'p' | 's']).toBe(value);
});

test('rejects altered Agent field types and imprecise nonces', () => {
  const action = l1Vectors[1][0];
  const nonce = 1700000000123;
  const typedData = backendAgentTypedData(l1Vectors[1][1]);
  typedData.types.Agent = [{ name: 'source', type: 'string' }, { name: 'connectionId', type: 'bytes' }];
  expect(() => assertHyperliquidExchangeBuildIntegrity({ action, nonce, typedData })).toThrow(/fields are invalid/);
  for (const value of [-1, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    expect(() => assertHyperliquidExchangeBuildIntegrity({ action, nonce: value, typedData })).toThrow(/nonce/);
  }
});

test.each([
  ['chainId', /chainId must be 1337/u],
  ['source', /source must be mainnet/u],
  ['connectionId', /32-byte hex/u],
] as const)('rejects an invalid backend Agent %s', (field, error) => {
  const typedData = backendAgentTypedData(l1Vectors[1][1]);
  if (field === 'chainId') typedData.domain.chainId = 1;
  else if (field === 'source') typedData.message.source = 'b';
  else typedData.message.connectionId = 'not-a-hash';
  expect(() => assertHyperliquidExchangeBuildIntegrity({
    action: l1Vectors[1][0], nonce: 1700000000123, typedData,
  })).toThrow(error);
});

test('derives approveBuilderFee typed data from its action fields', () => {
  const nonce = 1_700_000_000_456;
  const action = {
    type: 'approveBuilderFee', hyperliquidChain: 'Mainnet', signatureChainId: '0xa4b1',
    maxFeeRate: '0.1%', builder: BUILDER, nonce,
  };
  const message = { hyperliquidChain: 'Mainnet', maxFeeRate: '0.1%', builder: BUILDER, nonce };
  const typedData = {
    domain: { name: 'HyperliquidSignTransaction', version: '1', chainId: 42161,
      verifyingContract: '0x0000000000000000000000000000000000000000' },
    types: { 'HyperliquidTransaction:ApproveBuilderFee': [
      { name: 'hyperliquidChain', type: 'string' }, { name: 'maxFeeRate', type: 'string' },
      { name: 'builder', type: 'address' }, { name: 'nonce', type: 'uint64' },
    ] },
    primaryType: 'HyperliquidTransaction:ApproveBuilderFee',
    message,
  };

  expect(assertHyperliquidExchangeBuildIntegrity({ action, nonce, typedData })).toMatchObject({
    primaryType: 'HyperliquidTransaction:ApproveBuilderFee', message,
  });
  expect(() => assertHyperliquidExchangeBuildIntegrity({
    action, nonce, typedData: { ...typedData, message: { ...message, maxFeeRate: '1%' } },
  })).toThrow(/does not match/u);
});

describe('assertHyperliquidWithdrawPermitIntegrity', () => {
  const sampleWithdraw = (recipient: string) => perpsWithdrawalFixture(recipient, '10.5', '');

  it('accepts a locally consistent withdraw permit for the wallet', () => {
    expect(() => assertHyperliquidWithdrawPermitIntegrity(sampleWithdraw(WALLET), WALLET)).not.toThrow();
  });

  it('rejects when action recipient differs from the wallet', () => {
    expect(() => assertHyperliquidWithdrawPermitIntegrity(sampleWithdraw(ATTACKER), WALLET))
      .toThrow(/must match the wallet address/u);
  });

  it('rejects permit domain chainId tampering', () => {
    const withdraw = sampleWithdraw(WALLET);

    expect(() => assertHyperliquidWithdrawPermitIntegrity({
      ...withdraw,
      permitData: { ...withdraw.permitData, domain: { ...withdraw.permitData.domain, chainId: 1 } },
    }, WALLET)).toThrow(/domain chainId/u);
  });

  it('rejects permit types outside SendToEvmWithData schema', () => {
    const withdraw = sampleWithdraw(WALLET);

    expect(() => assertHyperliquidWithdrawPermitIntegrity({
      ...withdraw,
      permitData: {
        ...withdraw.permitData,
        types: { 'HyperliquidTransaction:Withdraw': [{ name: 'amount', type: 'string' }] },
      },
    }, WALLET)).toThrow(/SendToEvmWithData/u);
  });

  it('rejects permit values that disagree with the wire action', () => {
    const withdraw = sampleWithdraw(WALLET);

    expect(() => assertHyperliquidWithdrawPermitIntegrity({
      ...withdraw,
      permitData: {
        ...withdraw.permitData,
        values: { ...withdraw.permitData.values, destinationRecipient: ATTACKER },
      },
    }, WALLET)).toThrow(/does not match wire action/u);
  });

  it('uses fixed Arbitrum domain chain id in reconstructed permit', () => {
    const withdraw = sampleWithdraw(WALLET);
    const permitData = assertHyperliquidWithdrawPermitIntegrity(withdraw, WALLET);

    expect(Number(permitData.domain.chainId)).toBe(HYPERLIQUID_BRIDGE_CHAIN_ID);
    expect(Object.keys(permitData.types)).toEqual(['HyperliquidTransaction:SendToEvmWithData']);
    expect(Object.keys(permitData.values).sort()).toEqual(Object.keys(withdraw.permitData.values).sort());
    expect(TypedDataEncoder.hash(
      permitData.domain,
      permitData.types as Record<string, Array<{ name: string; type: string }>>,
      permitData.values,
    )).toMatch(/^0x/u);
  });
});
