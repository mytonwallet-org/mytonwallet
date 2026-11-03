import type { ApiPerpsQuote } from '../types/perpsTrading';

import { getPerpsReceiptDetails } from './perpsReceipt';

const quote = {
  accountId: 'a', assetId: 'hyperliquid:hl:BTC', kind: 'increase', side: 'long', leverage: 2,
  collateral: '30', previousCollateral: '19.886434', size: '0.00075', previousSize: '0.0005',
  markPrice: '80124', paymentAmount: '10.313566', bridgeFee: '0.2', previousFunding: '0.000748',
} as ApiPerpsQuote;

const receipt = {
  quote,
  operation: { accountId: 'a', assetId: quote.assetId, kind: 'increase',
    state: 'completed', orderId: 123, depositTxHash: '0xdeposit' },
  fill: { oid: 123, coin: 'BTC', fee: '0.026293', builderFee: '0.017636', feeToken: 'USDC', positionSize: '0.00075' },
  position: { id: `a/${quote.assetId}`, side: 'long', size: '0.00075', collateral: '29.883141', funding: '0.000748' },
} as Parameters<typeof getPerpsReceiptDetails>[0];

test('settled receipt includes bridge fees once and reconciles the live rounding remainder', () => {
  expect(getPerpsReceiptDetails(receipt)).toEqual({
    fees: { exchange: '0.008657', service: '0.017636', trading: '0.026293', bridge: '0.2', total: '0.226293' },
    remainingCollateral: '0.090566',
  });
});

test.each([
  { bridge: undefined, expectedBridge: '0.2', total: '0.226293' },
  { bridge: '0', expectedBridge: '0', total: '0.026293' },
  { bridge: '0.22', expectedBridge: '0.22', total: '0.246293' },
])('grouped receipt preserves known bridge fees without overriding backend bridge $bridge', ({
  bridge, expectedBridge, total,
}) => {
  const receiptFees = { trading: '0.026293', service: '0.017636', exchange: '0.008657', bridge,
    total: bridge === undefined ? '0.026293' : total };
  const input = { ...receipt, fill: { ...receipt.fill!, receiptFees } };
  expect(getPerpsReceiptDetails(input).fees).toEqual({ ...receiptFees, bridge: expectedBridge, total });
  if (bridge === undefined) {
    expect(getPerpsReceiptDetails({ ...input, operation: { ...input.operation, depositTxHash: undefined } }).fees)
      .toEqual(receiptFees);
  }
});

test('funding paid during settlement does not inflate the unallocated remainder', () => {
  expect(getPerpsReceiptDetails({ ...receipt,
    position: { ...receipt.position!, collateral: '29.882141', funding: '0.001748' } })
    .remainingCollateral).toBe('0.090566');
});

test('receipt rejects unrelated fills and accounts, and does not invent old bridge or funding history', () => {
  expect(getPerpsReceiptDetails({ ...receipt, fill: { ...receipt.fill!, oid: 456 } })).toEqual({});
  expect(getPerpsReceiptDetails({ ...receipt, quote: { ...quote, accountId: 'b' } })).toEqual({});
  const old = getPerpsReceiptDetails({ ...receipt, quote: { ...quote, previousFunding: undefined },
    operation: { ...receipt.operation, depositTxHash: undefined } });
  expect(old.remainingCollateral).toBeUndefined();
  expect(old.fees?.bridge).toBeUndefined();
});

test('a completed reduction reports net received USDC and never double-subtracts trading fees', () => {
  const reduced = { ...receipt, quote: { ...quote, kind: 'reduce' as const },
    operation: { ...receipt.operation, kind: 'reduce' as const, withdrawalAmount: '5' } };
  expect(getPerpsReceiptDetails(reduced).receiveAmount).toBe('4.8');
  expect(getPerpsReceiptDetails({ ...reduced, fill: undefined }).receiveAmount).toBe('4.8');
  expect(getPerpsReceiptDetails({ ...reduced, operation: { ...reduced.operation, state: 'partial' } })
    .receiveAmount).toBeUndefined();
});

test('grouped activities use the execution result size for receipt reconciliation', () => {
  const grouped = { ...receipt, operation: { ...receipt.operation, positionSize: '0.00075' },
    fill: { ...receipt.fill!, positionSize: undefined } };
  expect(getPerpsReceiptDetails(grouped).remainingCollateral).toBe('0.090566');
  expect(getPerpsReceiptDetails({ ...grouped, operation: { ...grouped.operation, positionSize: '0.001' } })
    .remainingCollateral).toBeUndefined();
  expect(getPerpsReceiptDetails({ ...grouped, operation: { ...grouped.operation, orderId: undefined },
    fill: { ...grouped.fill, oid: undefined } })).toEqual({});
});

test('saved receipts recover the rounding remainder from backend grouped execution size', () => {
  expect(getPerpsReceiptDetails({ ...receipt, fill: { ...receipt.fill!, positionSize: undefined, sz: '0.00025' } })
    .remainingCollateral).toBe('0.090566');
});

test('backend settled withdrawal and fee amounts replace local receipt calculations', () => {
  const fees = { trading: '0.04', service: '0.01', exchange: '0.03', bridge: '0.22', total: '0.26' };
  const reduced = { ...receipt, quote: { ...quote, kind: 'reduce' as const },
    operation: { ...receipt.operation, kind: 'reduce' as const, withdrawalAmount: '5' },
    fill: { ...receipt.fill!, receiptFees: fees,
      withdrawal: { amount: '4.95', bridgeFee: '0.22', receivedAmount: '4.73', status: 'completed' as const } } };
  expect(getPerpsReceiptDetails(reduced)).toEqual({ receiveAmount: '4.73', fees });
  expect(getPerpsReceiptDetails({ ...reduced,
    fill: { ...reduced.fill, withdrawal: { ...reduced.fill.withdrawal, status: 'pending' } } }).receiveAmount)
    .toBeUndefined();
});

test('backend deposit and collateral values take precedence when reconciling the remainder', () => {
  const actual = { ...receipt, quote: { ...quote, paymentAmount: '99', previousCollateral: '2' },
    fill: { ...receipt.fill!, collateralBefore: '19.886434', collateralAfter: '29.883141',
      deposit: { grossAmount: '10.313566', bridgeFee: '0.2', creditedAmount: '10.113566' } } };
  expect(getPerpsReceiptDetails(actual).remainingCollateral).toBe('0.090566');
});

test('funded leverage changes include the actual bridge fee and do not invent a free transfer', () => {
  const leverage = { ...receipt, quote: { ...quote, kind: 'leverage' as const, paymentAmount: '10.2' },
    operation: { ...receipt.operation, kind: 'leverage' as const }, fill: undefined };
  expect(getPerpsReceiptDetails(leverage).fees).toEqual({
    exchange: '0', service: '0', trading: '0', bridge: '0.2', total: '0.2',
  });
  expect(getPerpsReceiptDetails({ ...leverage,
    operation: { ...leverage.operation, depositTxHash: undefined } }).fees).toBeUndefined();
  expect(getPerpsReceiptDetails({ ...leverage,
    quote: { ...leverage.quote, paymentAmount: '0' } }).fees?.total).toBe('0');
});
