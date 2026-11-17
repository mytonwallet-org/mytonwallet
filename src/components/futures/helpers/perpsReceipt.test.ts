import type {
  ApiPerpsAccountPosition, ApiPerpsFill, ApiPerpsOperation, ApiPerpsQuote,
} from '../../../api/types';

import {
  buildFillReceipt, buildOperationReceipt, getPerpsReceiptStatus, getPerpsReceiptSummary,
} from './perpsReceipt';

const quote = {
  id: 'quote-1',
  accountId: 'account',
  assetId: 'hyperliquid:hl:BTC',
  kind: 'open',
  side: 'long',
  leverage: 5,
  collateral: '100',
  estimatedCollateral: '99.5',
  notional: '500',
  markPrice: '60000',
  estimatedLiquidationPrice: '48000',
  paymentAmount: '101',
  estimatedFees: { trading: '0.3', bridge: '1', total: '1.3' },
} as ApiPerpsQuote;

const operation = {
  id: 'op-1',
  accountId: 'account',
  assetId: 'hyperliquid:hl:BTC',
  kind: 'open',
  state: 'running',
  stage: 'trade',
  createdAt: 1,
  orderId: 7,
} as ApiPerpsOperation;

describe('buildOperationReceipt', () => {
  it('shows the estimates of the quote until the execution reports', () => {
    const receipt = buildOperationReceipt(operation, quote);

    expect(receipt).toMatchObject({
      amount: '99.5', sizeAfter: '500', price: '60000', liquidationAfter: '48000', fees: quote.estimatedFees,
    });
    expect(receipt?.estimates).toEqual(expect.arrayContaining(['amount', 'size', 'price', 'liquidation', 'fees']));
  });

  it('replaces the estimates with the fill and the position', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, px: '60100', collateralAfter: '98.7', positionNotional: '501', fee: '0.31',
      feeToken: 'USDC', eventKind: 'opened', deposit: { grossAmount: '100.9', bridgeFee: '1', creditedAmount: '99.9' },
    } as ApiPerpsFill;
    const position = {
      collateral: '98.7', raw: { positionValue: '502', liquidationPx: '48100' },
    } as ApiPerpsAccountPosition;

    const receipt = buildOperationReceipt({ ...operation, state: 'completed' }, quote, undefined, { fill, position });

    expect(receipt).toMatchObject({
      amount: '98.7', sizeAfter: '501', price: '60100', liquidationAfter: '48100', paid: '100.9', fee: '0.31',
    });
    expect(receipt?.fees).toBeUndefined();
    expect(receipt?.estimates).toEqual([]);
  });

  it('marks the payment of the quote as an estimate', () => {
    const receipt = buildOperationReceipt(operation, quote);

    expect(receipt?.paid).toBe('101');
    expect(receipt?.estimates).toContain('paid');
  });

  it('shows no estimates for a failed operation', () => {
    const receipt = buildOperationReceipt({ ...operation, state: 'failed' }, quote);

    expect(receipt?.amount).toBeUndefined();
    expect(receipt?.estimates).toEqual([]);
  });

  it('shows no payment of the quote when the outcome is unknown', () => {
    expect(buildOperationReceipt({ ...operation, state: 'unknown' }, quote)?.paid).toBeUndefined();
  });

  it('adds the bridge fee of the reconciled details to the trading fee of the fill', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, feeToken: 'USDC', eventKind: 'opened',
      receiptFees: { trading: '0.05', total: '0.05' },
    } as ApiPerpsFill;
    const details = { fees: { trading: '0.050', bridge: '1', total: '1.05' } };

    const receipt = buildOperationReceipt({ ...operation, state: 'completed' }, quote, undefined, { fill, details });

    expect(receipt?.fees).toEqual({ trading: '0.05', bridge: '1', total: '1.05' });
  });

  it('builds no receipt for a withdrawal from the balance', () => {
    expect(buildOperationReceipt({ ...operation, kind: 'withdraw' }, quote)).toBeUndefined();
  });

  it('marks the fee as pending while nothing reports it', () => {
    const receipt = buildOperationReceipt({ ...operation, state: 'failed' }, quote);

    expect(receipt).toMatchObject({ isFeePending: true });
    expect(receipt?.fees).toBeUndefined();
  });

  it('does not mark the fee of the quote as pending', () => {
    expect(buildOperationReceipt(operation, quote)?.isFeePending).toBeUndefined();
  });
});

describe('buildFillReceipt', () => {
  it('sums up a trade with its size when the history does not know its collateral', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, notional: '500', feeToken: 'USDC', eventKind: 'increased', positionSide: 'long',
      collateralBefore: '50',
    } as ApiPerpsFill;

    expect(buildFillReceipt(fill)).toMatchObject({ amount: '500', isAmountTradeSize: true });
    expect(buildFillReceipt(fill)?.amountBefore).toBeUndefined();
  });

  it('shows how a resize changed the position size when the history does not know its collateral', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, notional: '125', feeToken: 'USDC', eventKind: 'increased', positionSide: 'long',
      previousNotional: '500', positionNotional: '625',
    } as ApiPerpsFill;

    expect(getPerpsReceiptSummary(buildFillReceipt(fill)!)).toMatchObject({
      amount: '625', prevAmount: '500', captionKey: 'Position Size',
    });
  });

  it('shows an unchanged position size once', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, notional: '61', feeToken: 'USDC', eventKind: 'reduced', positionSide: 'short',
      previousNotional: '25.16', positionNotional: '25.16',
    } as ApiPerpsFill;

    expect(getPerpsReceiptSummary(buildFillReceipt(fill)!)).toMatchObject({ amount: '25.16', prevAmount: undefined });
  });

  it('sums up a trade with its collateral when the history knows it', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, notional: '500', feeToken: 'USDC', eventKind: 'opened', positionSide: 'long',
      collateralAfter: '100',
    } as ApiPerpsFill;

    expect(buildFillReceipt(fill)).toMatchObject({ amount: '100', isAmountTradeSize: false });
  });
});

describe('getPerpsReceiptSummary', () => {
  const closeQuote = { ...quote, kind: 'close', profitLoss: '5', previousCollateral: '100' } as ApiPerpsQuote;
  const closeOperation = { ...operation, kind: 'close', state: 'completed' } as ApiPerpsOperation;
  const closeFill = {
    coin: 'BTC', oid: 7, time: 2, netPnl: '5', feeToken: 'USDC', eventKind: 'closed',
    withdrawal: { status: 'completed', receivedAmount: '105' },
  } as ApiPerpsFill;

  it('names the outcome of a closed position', () => {
    expect(getPerpsReceiptSummary(buildFillReceipt(closeFill)!)).toEqual({
      amount: '5', captionKey: 'Profit and Loss', isEstimated: false,
    });
  });

  it('shows what a closed position brought to the wallet in its details', () => {
    expect(getPerpsReceiptSummary(buildFillReceipt(closeFill)!, true)).toEqual({
      amount: '105', captionKey: 'You Received',
    });
  });

  it('keeps the estimated outcome in the details until the withdrawal reports the amount', () => {
    const receipt = buildOperationReceipt(closeOperation, closeQuote)!;

    expect(getPerpsReceiptSummary(receipt, true)).toEqual({
      amount: '5', captionKey: 'Profit and Loss', isEstimated: true,
    });
  });

  it('names the size of a trade the history knows without its collateral', () => {
    const fill = {
      coin: 'BTC', oid: 7, time: 2, notional: '500', feeToken: 'USDC', eventKind: 'opened', positionSide: 'long',
    } as ApiPerpsFill;

    expect(getPerpsReceiptSummary(buildFillReceipt(fill)!)).toMatchObject({ amount: '500', captionKey: 'Trade Size' });
  });

  it('leaves out an unknown amount together with its caption', () => {
    expect(getPerpsReceiptSummary(buildOperationReceipt({ ...closeOperation, state: 'failed' }, closeQuote)!))
      .toEqual({});
  });
});

describe('getPerpsReceiptStatus', () => {
  function getStatus(changes: Partial<ApiPerpsOperation>) {
    return getPerpsReceiptStatus(buildOperationReceipt({ ...operation, ...changes }, quote)!);
  }

  it.each([
    ['in progress before the submission', { stage: 'preparing' as const }, 'pending'],
    ['submitted once the deposit or the order goes out', { stage: 'deposit' as const }, 'submitted'],
    ['done once the operation completes', { state: 'completed' as const }, 'completed'],
  ])('is %s', (_, changes, status) => {
    expect(getStatus(changes)).toEqual({ status });
  });

  it('tells that the USDC stayed on Hyperliquid when the withdrawal of a close was refused', () => {
    const error = 'PerpsWithdrawalRejected: insufficient balance';

    expect(getStatus({ kind: 'close', state: 'completed', error })).toEqual({ status: 'attention', errorCode: error });
  });

  it('shows no estimates for a refused withdrawal', () => {
    const receipt = buildOperationReceipt(
      { ...operation, state: 'completed', error: 'PerpsWithdrawalRejected: refused' }, quote, undefined,
    );

    expect(receipt?.estimates).toEqual([]);
  });

  it.each([
    ['a partial fill', { state: 'completed' as const, error: 'PerpsPartialFill' }, 'PerpsPartialFill'],
    ['a pending withdrawal', { state: 'partial' as const }, 'PerpsWithdrawalPending'],
    ['an unknown outcome', { state: 'unknown' as const }, 'PerpsExecutionUnknown'],
  ])('asks for attention after %s', (_, changes, messageKey) => {
    expect(getStatus(changes)).toEqual({ status: 'attention', messageKey });
  });

  it('marks the remaining collateral of the quote as an estimate', () => {
    const receipt = buildOperationReceipt(operation, { ...quote, estimatedRemainingCollateral: '0.4' });

    expect(receipt).toMatchObject({ remainingCollateral: '0.4' });
    expect(receipt?.estimates).toContain('remaining');
  });
});
