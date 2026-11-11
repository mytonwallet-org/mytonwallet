import { TypedDataEncoder } from 'ethers';

import { perpsWithdrawalFixture } from '../../../../tests/helpers/perpsWithdrawal';
import { HYPERLIQUID_BRIDGE_CHAIN_ID } from '../../common/perps';
import { getEvmChainId } from './constants';
import {
  assertHyperliquidExchangeBuildIntegrity,
  assertHyperliquidWithdrawPermitIntegrity,
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

test('a balance withdrawal is signed only to the wallet it is checked against', () => {
  const { action, nonce, permitData } = perpsWithdrawalFixture(WALLET, '10.5', '');
  const typedData = {
    domain: permitData.domain,
    types: permitData.types as Record<string, Array<{ name: string; type: string }>>,
    primaryType: 'HyperliquidTransaction:SendToEvmWithData',
    message: permitData.values,
  };

  expect(() => assertHyperliquidExchangeBuildIntegrity({ action, nonce, typedData }, {
    expectedWalletRecipient: WALLET,
  })).not.toThrow();
  expect(() => assertHyperliquidExchangeBuildIntegrity({ action, nonce, typedData }, {
    expectedWalletRecipient: ATTACKER,
  })).toThrow(/must match the wallet address/u);
  expect(() => assertHyperliquidExchangeBuildIntegrity({ action, nonce, typedData }))
    .toThrow(/requires the wallet recipient/u);
});

describe('a switch to Unified', () => {
  const nonce = 1_700_000_000_456;
  const message = { hyperliquidChain: 'Mainnet', user: WALLET.toLowerCase(), abstraction: 'unifiedAccount', nonce };
  const payload = {
    action: { type: 'userSetAbstraction', signatureChainId: '0xa4b1', ...message },
    nonce,
    typedData: {
      domain: { name: 'HyperliquidSignTransaction', version: '1', chainId: 42161,
        verifyingContract: '0x0000000000000000000000000000000000000000' },
      types: { 'HyperliquidTransaction:UserSetAbstraction': [
        { name: 'hyperliquidChain', type: 'string' }, { name: 'user', type: 'address' },
        { name: 'abstraction', type: 'string' }, { name: 'nonce', type: 'uint64' },
      ] },
      primaryType: 'HyperliquidTransaction:UserSetAbstraction',
      message,
    },
  };

  test('is signed for the signing account', () => {
    expect(assertHyperliquidExchangeBuildIntegrity(payload, { expectedAccount: WALLET }).message).toEqual(message);
  });

  test('needs the account it is checked against', () => {
    expect(() => assertHyperliquidExchangeBuildIntegrity(payload)).toThrow(/requires the account address/u);
    expect(() => assertHyperliquidExchangeBuildIntegrity(payload, { expectedAccount: ATTACKER }))
      .toThrow(/must be for the signing account/u);
  });

  test.each(['disabled', 'portfolioMargin', 'dexAbstraction'])('refuses a switch to %s', (abstraction) => {
    expect(() => assertHyperliquidExchangeBuildIntegrity({
      ...payload, action: { ...payload.action, abstraction },
    }, { expectedAccount: WALLET })).toThrow(/must switch to a unified account/u);
  });
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
    }, WALLET)).toThrow(/does not match the wire action/u);
  });

  it('rejects permit types outside SendToEvmWithData schema', () => {
    const withdraw = sampleWithdraw(WALLET);

    expect(() => assertHyperliquidWithdrawPermitIntegrity({
      ...withdraw,
      permitData: {
        ...withdraw.permitData,
        types: { 'HyperliquidTransaction:Withdraw': [{ name: 'amount', type: 'string' }] },
      },
    }, WALLET)).toThrow(/does not match the wire action/u);
  });

  it('rejects permit values that disagree with the wire action', () => {
    const withdraw = sampleWithdraw(WALLET);

    expect(() => assertHyperliquidWithdrawPermitIntegrity({
      ...withdraw,
      permitData: {
        ...withdraw.permitData,
        values: { ...withdraw.permitData.values, destinationRecipient: ATTACKER },
      },
    }, WALLET)).toThrow(/does not match the wire action/u);
  });

  it.each([
    ['usdClassTransfer', { amount: '10', toPerp: true }, 'HyperliquidTransaction:UsdClassTransfer', [
      { name: 'hyperliquidChain', type: 'string' }, { name: 'amount', type: 'string' },
      { name: 'toPerp', type: 'bool' }, { name: 'nonce', type: 'uint64' },
    ]],
    ['approveBuilderFee', { maxFeeRate: '0.1%', builder: BUILDER }, 'HyperliquidTransaction:ApproveBuilderFee', [
      { name: 'hyperliquidChain', type: 'string' }, { name: 'maxFeeRate', type: 'string' },
      { name: 'builder', type: 'address' }, { name: 'nonce', type: 'uint64' },
    ]],
  ])('refuses a %s action with a permit that matches it', (type, fields, primaryType, typedFields) => {
    const nonce = 1_700_000_000_456;
    const values = { hyperliquidChain: 'Mainnet', ...fields, nonce };

    expect(() => assertHyperliquidWithdrawPermitIntegrity({
      action: { type, signatureChainId: '0xa4b1', ...values },
      nonce,
      permitData: {
        domain: { name: 'HyperliquidSignTransaction', version: '1', chainId: 42161,
          verifyingContract: '0x0000000000000000000000000000000000000000' },
        types: { [primaryType]: typedFields },
        values,
      },
    }, WALLET)).toThrow(/must be sendToEvmWithData/u);
  });

  it('uses fixed Arbitrum domain chain id in reconstructed permit', () => {
    const withdraw = sampleWithdraw(WALLET);
    const permitData = assertHyperliquidWithdrawPermitIntegrity(withdraw, WALLET);

    expect(Number(permitData.domain.chainId)).toBe(HYPERLIQUID_BRIDGE_CHAIN_ID);
    expect(HYPERLIQUID_BRIDGE_CHAIN_ID).toBe(getEvmChainId('mainnet', 'arbitrum'));
    expect(Object.keys(permitData.types)).toEqual(['HyperliquidTransaction:SendToEvmWithData']);
    expect(Object.keys(permitData.values).sort()).toEqual(Object.keys(withdraw.permitData.values).sort());
    expect(TypedDataEncoder.hash(
      permitData.domain,
      permitData.types as Record<string, Array<{ name: string; type: string }>>,
      permitData.values,
    )).toMatch(/^0x/u);
  });
});
