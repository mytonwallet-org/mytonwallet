import { test } from '@jest/globals';
import { Interface } from 'ethers';
import assert from 'node:assert/strict';

import type { VtIntent, VtPlan } from './types';

import ethFee from './fixtures/eth-0.1-partner-fee.json';
import taxi from './fixtures/taxi.json';
import usdcFee from './fixtures/usdc-100-partner-fee.json';
import usdt0 from './fixtures/usdt0-100.json';
import usdt0Fee from './fixtures/usdt0-100-partner-fee.json';
import deployments from './deployments.json';
import { findOftRoute, validateVtPlan, VT_CHAINS, VT_FEE_RECIPIENT } from './validation';

const WRAPPER = new Interface([
  'function execute((address target,uint256 value,bytes data)[] calls,bytes32 quoteId)',
]);
const INTENT: VtIntent = {
  sourceChain: 'base',
  destinationChain: 'arbitrum',
  owner: '0x0000000000000000000000000000000000000001',
  recipient: '0x0000000000000000000000000000000000000001',
  sourceToken: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
  destinationToken: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
  sourceDecimals: 6,
  destinationDecimals: 6,
  amount: '100000000',
  minimum: '98939906',
  feeAmount: '0',
  nativeFeeBudget: '1000000000000000',
};
function buildPlan(): VtPlan {
  return {
    provider: 'layerzero',

    quote: JSON.parse(JSON.stringify(taxi)),
    expiresAt: Date.now() + 60000,
  };
}

test('builds the real authorized Taxi payload with no fee for a zero policy', () => {
  const input = buildPlan();
  const tx = validateVtPlan(input, INTENT);
  assert.equal(tx.to, VT_CHAINS.base.wrapper);
  assert.equal(tx.data, input.quote.userSteps[1].transaction!.encoded.data);
});

test('validates API partner fees without adding a second wallet charge', () => {
  for (const [quote, token, decimals, amount, fee] of [
    [usdcFee, INTENT.sourceToken, 6, '100000000', '880000'],
    [ethFee, '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE', 18, '100000000000000000', '880000000000000'],
  ] as const) {
    const plan = { ...buildPlan(), quote };
    const intent = { ...INTENT, sourceToken: token, destinationToken: token === INTENT.sourceToken
      ? INTENT.destinationToken : token, sourceDecimals: decimals, destinationDecimals: decimals,
    amount, minimum: '0', feeAmount: fee };
    const tx = validateVtPlan(plan, intent);
    const original = quote.userSteps[quote.userSteps.length - 1].transaction.encoded;
    assert.equal(tx.data, original.data);
    assert.equal(BigInt(tx.value!), BigInt(original.value!));
    assert.throws(() => validateVtPlan(plan, { ...intent, feeAmount: '0' }), /partner fee mismatch/);
    const altered = JSON.parse(JSON.stringify(plan)) as VtPlan;
    const encoded = altered.quote.userSteps[altered.quote.userSteps.length - 1].transaction!.encoded;
    const [decoded, quoteId] = WRAPPER.decodeFunctionData('execute', encoded.data);
    const calls = decoded.map((call: { target: string; value: { toString(): string }; data: string }) => ({
      target: call.target, value: call.value.toString(), data: call.data,
    }));
    if (decimals === 18) calls[0].target = INTENT.owner;
    else {
      const token = new Interface(['function transfer(address to,uint256 amount)']);
      calls[1].data = token.encodeFunctionData('transfer', [INTENT.owner, fee]);
    }
    encoded.data = WRAPPER.encodeFunctionData('execute', [calls, quoteId]);
    assert.throws(() => validateVtPlan(altered, intent), /Invalid VT partner fee/);
  }
});

for (const [field, value] of Object.entries({
  recipient: VT_FEE_RECIPIENT,
  destinationChain: 'optimism',
  amount: '200000000',
  minimum: '100000000',
  sourceToken: VT_FEE_RECIPIENT,
  nativeFeeBudget: '0',
})) {
  test(`rejects backend calldata which does not match the local ${field}`, () => {
    assert.throws(() => validateVtPlan(buildPlan(), { ...INTENT, [field]: value }));
  });
}

test('rejects Aori signatures and unknown route formats', () => {
  const input = buildPlan();
  input.quote.routeSteps[0].type = 'AORI_V1';
  assert.throws(() => validateVtPlan(input, INTENT), /Unsupported VT protocol/);
});

test('rejects expired plans and fee changes', () => {
  assert.throws(() => validateVtPlan({ ...buildPlan(), expiresAt: 0 }, INTENT), /Expired/);
  const altered = buildPlan();
  altered.quote.fees.push({ type: 'GENERAL', address: INTENT.sourceToken, chainKey: 'base', amount: '1' });
  assert.throws(() => validateVtPlan(altered, INTENT), /partner fee mismatch/);
});

test('rejects extra nested calls rather than trusting the outer target', () => {
  const input = buildPlan();
  const tx = input.quote.userSteps[1].transaction!.encoded;
  const [calls, id] = WRAPPER.decodeFunctionData('execute', tx.data);
  tx.data = WRAPPER.encodeFunctionData('execute', [
    [...calls, { target: VT_FEE_RECIPIENT, value: 0, data: '0x' }],
    id,
  ]);
  assert.throws(() => validateVtPlan(input, INTENT), /Unsupported nested/);
});

test('rejects a sweep which leaves native refunds in the public wrapper', () => {
  const input = buildPlan();
  const tx = input.quote.userSteps[1].transaction!.encoded;
  const [decoded, id] = WRAPPER.decodeFunctionData('execute', tx.data);
  const calls = decoded.map((call: { target: string; value: bigint; data: string }) => ({
    target: call.target,
    value: call.value,
    data: call.data,
  }));
  const sweep = new Interface(['function sweep(address[] tokens,address recipient)']);
  calls[3].data = sweep.encodeFunctionData('sweep', [[INTENT.sourceToken], INTENT.owner]);
  tx.data = WRAPPER.encodeFunctionData('execute', [calls, id]);
  assert.throws(() => validateVtPlan(input, INTENT), /Incomplete VT refund/);
});

test('routes a deployment shared by two OFT groups through the group that reaches the destination', () => {
  const usde = deployments.assets.filter((entry) => entry.group === 'oft-USDe-1');
  const ethereum = usde.find((entry) => entry.chain === 'ethereum')!;
  const hyperliquid = usde.find((entry) => entry.chain === 'hyperliquid')!;
  const { asset, output } = findOftRoute({
    ...INTENT,
    sourceChain: 'ethereum',
    destinationChain: 'hyperliquid',
    sourceToken: ethereum.token,
    destinationToken: hyperliquid.token,
  }, ethereum.address);
  assert.equal(asset?.group, 'oft-USDe-1');
  assert.equal(output, hyperliquid);
});

test('validates OFT_V2 with the VT OFT fee collected beside our partner fee', () => {
  const intent = { ...INTENT, sourceChain: 'arbitrum', destinationChain: 'ethereum',
    sourceToken: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    destinationToken: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    amount: '100000000', minimum: '98000000' };
  for (const [quote, feeAmount, mislabelled] of [[usdt0, '0', '880000'], [usdt0Fee, '880000', '0']] as const) {
    const plan = { ...buildPlan(), quote: JSON.parse(JSON.stringify(quote)) as VtPlan['quote'] };
    const tx = validateVtPlan(plan, { ...intent, feeAmount });
    assert.equal(tx.data, quote.userSteps[quote.userSteps.length - 1].transaction.encoded.data);
    // Only the 2 bps VT fee may accompany our partner fee: a mislabelled partner fee is rejected
    assert.throws(() => validateVtPlan(plan, { ...intent, feeAmount: mislabelled }), /partner fee mismatch/);
  }
  const excessive = { ...buildPlan(), quote: JSON.parse(JSON.stringify(usdt0)) as VtPlan['quote'] };
  excessive.quote.fees.find((fee) => fee.type === 'GENERAL')!.amount = '30000';
  assert.throws(() => validateVtPlan(excessive, { ...intent, feeAmount: '0' }), /partner fee mismatch/);
});
