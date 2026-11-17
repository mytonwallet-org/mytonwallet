import type {
  ApiPerpsAccountPosition,
  ApiPerpsFees,
  ApiPerpsFill,
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsOperationKind,
  ApiPerpsPositionSide,
  ApiPerpsQuote,
  ApiPerpsReceiptDetails,
} from '../../../api/types';

import { Big } from '../../../lib/big.js';
import { isPerpsAmountEqual, isPerpsNumber, isPerpsWithdrawalRejected } from '../../../global/helpers/perps';
import { getPerpsAssetName } from './formatPerps';

export type PerpsReceiptEvent = 'opened' | 'increased' | 'reduced' | 'closed' | 'liquidated' | 'leverage';

/** A receipt value that comes from the reviewed quote, because the execution has not reported it yet */
export type PerpsReceiptEstimate = 'amount' | 'size' | 'price' | 'liquidation' | 'paid' | 'fees' | 'remaining';

/**
 * How a receipt presents its operation, as on iOS: before the submission, submitted, done, or with a message that
 * needs attention or tells why it failed
 */
export type PerpsReceiptStatus = 'pending' | 'submitted' | 'completed' | 'attention' | 'failed';

/** Everything a Perps receipt can show. A field the history or the operation does not know stays empty. */
export type PerpsReceiptData = {
  event: PerpsReceiptEvent;
  /** The state of a local operation. A trade from the history has none, since it has executed. */
  state?: ApiPerpsOperation['state'];
  stage?: ApiPerpsOperation['stage'];
  error?: string;
  symbol: string;
  /** The name of the market, as in "Bitcoin" */
  name: string;
  /** A trade from the history may come without its side, and the receipt then names only the market */
  side?: ApiPerpsPositionSide;
  leverage?: number;
  time: number;
  openedAt?: number;
  amount?: string;
  amountBefore?: string;
  isAmountSigned?: boolean;
  /** The amount is the size of a trade from the history, which does not know the collateral */
  isAmountTradeSize?: boolean;
  /** The amount is the position size of a resize from the history, which does not know the collateral */
  isAmountPositionSize?: boolean;
  invested?: string;
  profit?: string;
  closingValue?: string;
  sizeBefore?: string;
  sizeAfter?: string;
  /** The size is the size of the trade, since the history does not know the size of the position */
  isTradeSize?: boolean;
  price?: string;
  entryPrice?: string;
  exitPrice?: string;
  liquidationBefore?: string;
  liquidationAfter?: string;
  paid?: string;
  received?: string;
  fees?: ApiPerpsFees;
  /** The margin came from the Hyperliquid balance, so nothing crossed the bridge */
  isFromBalance?: boolean;
  /** The fee of a trade whose breakdown is unknown */
  fee?: string;
  feeToken?: string;
  /** The operation has reported no fee yet, since the fee becomes known at execution */
  isFeePending?: boolean;
  remainingCollateral?: string;
  transferId?: string;
  /** The Hyperliquid transaction of the trade, which arrives with the trade in the history */
  txHash?: string;
  filledSize?: string;
  estimates?: PerpsReceiptEstimate[];
};

type PerpsReceiptFacts = {
  fill?: ApiPerpsFill;
  position?: ApiPerpsAccountPosition;
  details?: ApiPerpsReceiptDetails;
};

const EVENT_BY_KIND: Record<ApiPerpsOperationKind, PerpsReceiptEvent> = {
  open: 'opened',
  increase: 'increased',
  reduce: 'reduced',
  close: 'closed',
  leverage: 'leverage',
};

/** The receipt of a trade from the history. The operation this app submitted for it adds its state. */
export function buildFillReceipt(
  fill: ApiPerpsFill,
  asset?: ApiPerpsMarketAsset,
  operation?: ApiPerpsOperation,
): PerpsReceiptData | undefined {
  const event = fill.eventKind;
  if (!event) return undefined;

  const withdrawal = fill.withdrawal?.status === 'completed' ? fill.withdrawal : undefined;
  const isClosing = event === 'closed' || event === 'liquidated';
  const isResize = event === 'increased' || event === 'reduced';
  const positionSize = isClosing ? fill.previousNotional : fill.positionNotional;
  const hasCollateral = isPerpsNumber(fill.collateralAfter);
  // The history reports no collateral, so a resize shows how the position size changed, which the history does report
  const isAmountPositionSize = isResize && !hasCollateral
    && isPerpsNumber(fill.previousNotional) && isPerpsNumber(fill.positionNotional);
  // Any other trade without the collateral is summed up with its size, as on iOS
  const isAmountTradeSize = !isClosing && !hasCollateral && !isAmountPositionSize
    && isPerpsNumber(fill.notional) && Big(fill.notional).gte(0);

  return {
    event,
    state: operation?.state,
    error: operation?.error,
    symbol: asset?.symbol ?? fill.coin,
    name: asset ? getPerpsAssetName(asset) : fill.coin,
    side: fill.positionSide,
    leverage: fill.leverage,
    time: fill.time,
    openedAt: fill.positionOpenedAt,
    amount: isClosing
      ? fill.netPnl
      : isAmountPositionSize ? fill.positionNotional : isAmountTradeSize ? fill.notional : fill.collateralAfter,
    amountBefore: isAmountPositionSize
      ? fill.previousNotional
      : isResize && !isAmountTradeSize ? fill.collateralBefore : undefined,
    isAmountSigned: isClosing,
    isAmountTradeSize,
    isAmountPositionSize,
    invested: isClosing ? fill.collateralBefore : undefined,
    profit: event === 'reduced' || event === 'closed' ? fill.netPnl : undefined,
    closingValue: event === 'liquidated' ? withdrawal?.receivedAmount : undefined,
    sizeBefore: event === 'opened' || isClosing || positionSize === undefined ? undefined : fill.previousNotional,
    sizeAfter: positionSize ?? fill.notional,
    isTradeSize: positionSize === undefined,
    price: event === 'opened' || event === 'increased' ? fill.px : undefined,
    entryPrice: event === 'reduced' || isClosing ? fill.entryPrice : undefined,
    exitPrice: isClosing || event === 'reduced' ? fill.px : undefined,
    paid: fill.deposit?.grossAmount,
    received: withdrawal?.receivedAmount,
    fees: fill.receiptFees,
    fee: fill.fee,
    feeToken: fill.feeToken,
    transferId: fill.deposit?.txHash ?? withdrawal?.txHash,
    txHash: fill.txHash,
    filledSize: operation?.error === 'PerpsPartialFill' ? operation.filledSize : undefined,
  };
}

/**
 * The receipt of an operation this app submitted. Until the fill and the position report the execution, a running or
 * completed operation shows the estimates of its reviewed quote.
 */
export function buildOperationReceipt(
  operation: ApiPerpsOperation,
  quote: ApiPerpsQuote,
  asset?: ApiPerpsMarketAsset,
  { fill, position, details }: PerpsReceiptFacts = {},
): PerpsReceiptData | undefined {
  // A withdrawal from the Hyperliquid balance is not a trade
  if (operation.kind === 'withdraw') return undefined;

  const event = EVENT_BY_KIND[operation.kind];
  const isClose = event === 'closed';
  const isReceiving = isClose || event === 'reduced';
  // The estimates describe a trade that went as reviewed, which a partial fill or a refused withdrawal did not
  const canUseEstimate = operation.error !== 'PerpsPartialFill'
    && !isPerpsWithdrawalRejected(operation)
    && (operation.state === 'running' || operation.state === 'completed');
  const estimates: PerpsReceiptEstimate[] = [];

  function getValue(field: PerpsReceiptEstimate, actual?: string, estimate?: string) {
    if (actual !== undefined || !canUseEstimate || estimate === undefined) return actual;

    estimates.push(field);
    return estimate;
  }

  const withdrawal = fill?.withdrawal;
  const received = withdrawal
    ? (withdrawal.status === 'completed' ? withdrawal.receivedAmount : undefined)
    : details?.receiveAmount;
  const price = getValue('price', fill?.px ?? operation.averagePrice, quote.markPrice);
  const profitLoss = isClose ? getValue('amount', fill?.netPnl, quote.profitLoss) : fill?.netPnl;
  const collateral = isClose
    ? undefined
    : getValue('amount', fill?.collateralAfter ?? position?.collateral, quote.estimatedCollateral ?? quote.collateral);

  return {
    event,
    state: operation.state,
    stage: operation.stage,
    error: operation.error,
    isFromBalance: quote.funding === 'balance' || undefined,
    symbol: asset?.symbol ?? quote.assetId,
    name: asset ? getPerpsAssetName(asset) : quote.assetId,
    side: fill?.positionSide ?? quote.side,
    leverage: fill?.leverage ?? quote.leverage,
    time: fill?.time ?? operation.createdAt,
    openedAt: fill?.positionOpenedAt,
    amount: isClose ? profitLoss : collateral,
    amountBefore: event === 'increased' || event === 'reduced'
      ? (fill?.collateralBefore ?? quote.previousCollateral)
      : undefined,
    isAmountSigned: isClose,
    invested: isClose ? (fill?.collateralBefore ?? quote.previousCollateral) : undefined,
    profit: isReceiving ? profitLoss : undefined,
    sizeBefore: event === 'opened' ? undefined : (fill?.previousNotional ?? quote.previousNotional),
    sizeAfter: isClose
      ? undefined
      : getValue('size', fill?.positionNotional ?? position?.raw.positionValue, quote.notional),
    price: isReceiving ? undefined : price,
    entryPrice: isReceiving ? (fill?.entryPrice ?? quote.entryPrice) : undefined,
    exitPrice: isReceiving ? price : undefined,
    liquidationBefore: event === 'opened' || isClose ? undefined : quote.liquidationPrice,
    liquidationAfter: isClose
      ? undefined
      : getValue('liquidation', position?.raw.liquidationPx ?? undefined, quote.estimatedLiquidationPrice),
    paid: isReceiving ? undefined : getValue('paid', fill?.deposit?.grossAmount, quote.paymentAmount),
    received: isReceiving ? received : undefined,
    ...getOperationFees(quote, { fill, details }, canUseEstimate, estimates),
    remainingCollateral: getValue('remaining', details?.remainingCollateral, quote.estimatedRemainingCollateral),
    transferId: fill?.deposit?.txHash ?? withdrawal?.txHash ?? operation.depositTxHash,
    txHash: fill?.txHash,
    filledSize: operation.error === 'PerpsPartialFill' ? operation.filledSize : undefined,
    estimates,
  };
}

function getOperationFees(
  quote: ApiPerpsQuote,
  { fill, details }: PerpsReceiptFacts,
  canUseEstimate: boolean,
  estimates: PerpsReceiptEstimate[],
): Pick<PerpsReceiptData, 'fees' | 'fee' | 'feeToken' | 'isFeePending'> {
  const settled = fill?.receiptFees ?? details?.fees;
  const reconciled = details?.fees;

  if (settled) {
    // The fill knows the trading fee, and the reconciled details add the bridge fee it lacks
    const isBridgeMissing = settled.bridge === undefined && reconciled?.bridge !== undefined
      && isPerpsAmountEqual(reconciled.trading, settled.trading);

    return { fees: isBridgeMissing ? { ...settled, bridge: reconciled.bridge, total: reconciled.total } : settled };
  }

  if (fill) return { fee: fill.fee, feeToken: fill.feeToken };

  if (canUseEstimate && quote.estimatedFees) {
    estimates.push('fees');
    return { fees: quote.estimatedFees };
  }

  return { isFeePending: true };
}

/**
 * The amount at the top of a receipt and the caption that names it, as on iOS. An unknown amount is left out. The
 * details of a closed position sum it up with what the wallet received, once the withdrawal reports it.
 */
export function getPerpsReceiptSummary(data: PerpsReceiptData, isExpanded?: boolean): {
  amount?: string;
  prevAmount?: string;
  captionKey?: string;
  isEstimated?: boolean;
} {
  const { event, amount, amountBefore, received } = data;

  if (isExpanded && event === 'closed' && isPerpsNumber(received)) {
    return { amount: received, captionKey: 'You Received' };
  }

  if (!isPerpsNumber(amount)) return {};

  const isClosing = event === 'closed' || event === 'liquidated';

  return {
    amount,
    // An amount that did not change shows once, without an arrow
    prevAmount: isPerpsNumber(amountBefore) && !isPerpsAmountEqual(amountBefore, amount) ? amountBefore : undefined,
    captionKey: isClosing
      ? 'Profit and Loss'
      : data.isAmountTradeSize ? 'Trade Size' : data.isAmountPositionSize ? 'Position Size' : undefined,
    isEstimated: isReceiptEstimate(data, 'amount'),
  };
}

export function isReceiptEstimate({ estimates }: PerpsReceiptData, field: PerpsReceiptEstimate) {
  return Boolean(estimates?.includes(field));
}

/**
 * The status of a receipt and its message, as on iOS: a text key, or an error code. A trade from the history has
 * executed.
 */
export function getPerpsReceiptStatus({ state, stage, error }: PerpsReceiptData): {
  status: PerpsReceiptStatus;
  messageKey?: string;
  errorCode?: string;
} {
  const isPartialFill = error === 'PerpsPartialFill';

  switch (state) {
    case undefined:
      return { status: 'completed' };
    case 'running':
      if (isPartialFill) return { status: 'attention', messageKey: 'PerpsPartialFill' };

      return { status: stage === 'preparing' ? 'pending' : 'submitted' };
    case 'failed':
      return { status: 'failed', errorCode: error };
    case 'partial':
      return { status: 'attention', messageKey: 'PerpsWithdrawalPending' };
    case 'completed':
      if (error?.startsWith('PerpsWithdrawalRejected')) return { status: 'attention', errorCode: error };
      if (isPartialFill) return { status: 'attention', messageKey: 'PerpsPartialFill' };

      return { status: 'completed' };
    default:
      return { status: 'attention', messageKey: 'PerpsExecutionUnknown' };
  }
}
