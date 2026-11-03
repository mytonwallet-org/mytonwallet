import type {
  ApiPerpsCctpDeposit, ApiPerpsLimits, ApiPerpsListedAsset, ApiPerpsPosition, ApiPerpsTradingAvailability,
} from '../types/perps';
import type {
  ApiPerpsAccountPosition, ApiPerpsDraftRequest, ApiPerpsFundingRequirements, ApiPerpsOperationKind,
  ApiPerpsQuote, ApiPerpsTradeIntent,
} from '../types/perpsTrading';

import { Big } from '../../lib/big.js';
import {
  PERPS_CCTP_FORWARD_FEE_USDC,
  PERPS_REVIEW_PRICE_TOLERANCE,
} from './perps';
import { assertPerpsCctpDepositIntegrity } from './perpsDeposit';

type PerpsDraftAmountContext = {
  asset: ApiPerpsListedAsset;
  draft: ApiPerpsDraftRequest;
  position?: ApiPerpsAccountPosition;
  availableUsdc: string;
};

/** A market without the backend's canonical exchange index cannot be traded on any book. */
export function getPerpsMarketTradingAvailability(asset: ApiPerpsListedAsset): ApiPerpsTradingAvailability {
  return asset.isDelisted || getPerpsWireAssetIndex(asset) === undefined
    ? { isAvailable: false, reason: 'PerpsTradingUnavailable' }
    : { isAvailable: true };
}

export function getPerpsWireAssetIndex(asset: ApiPerpsListedAsset): number | undefined {
  return isValidPerpsWireAssetIndex(asset.wireAssetIndex) ? asset.wireAssetIndex : undefined;
}

function isValidPerpsWireAssetIndex(index: unknown): index is number {
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0;
}

function resolveTargetCollateral({ asset, draft, position, availableUsdc }: PerpsDraftAmountContext): Big {
  const oldCollateral = Big(position?.collateral ?? 0);
  const amount = Big(draft.amount || '0');
  const unit = draft.convertFrom ?? draft.unit;
  let target = unit === 'asset' ? amount.mul(asset.context.markPx).div(draft.leverage) : amount;
  if (draft.reset || draft.leverageOnly) target = oldCollateral;
  if (draft.fraction !== undefined) {
    if (![5, 25, 50, 100, -5, -25, -50, -100].includes(draft.fraction)) throw new Error('PerpsInvalidAmount');
    target = position
      ? oldCollateral.mul(Big(100).plus(draft.fraction)).div(100)
      : Big(availableUsdc).minus(PERPS_CCTP_FORWARD_FEE_USDC).mul(draft.fraction).div(100);
  }
  return draft.close ? Big(0) : target;
}

/** Arbitrum funding is required only for orders that deposit more collateral. */
export function getPerpsFundingRequirements(params: PerpsDraftAmountContext & {
  availableEth: string;
  depositLimits: Pick<ApiPerpsLimits, 'minOpenDepositUsdc' | 'minIncreaseDepositUsdc'>;
  leverageDepositAmount?: string;
}): ApiPerpsFundingRequirements {
  const { draft, position, availableUsdc, availableEth, depositLimits } = params;
  const availability = getPerpsMarketTradingAvailability(params.asset);
  if (!availability.isAvailable) throw new Error(availability.reason);
  if (draft.editing && !position) throw new Error('PerpsPositionChanged');
  const availableCollateral = resolveTargetCollateral({
    asset: params.asset, availableUsdc, draft: { ...draft, fraction: 100, close: false },
  });
  const delta = resolveTargetCollateral(params).minus(position?.collateral ?? 0);
  const deposits = params.leverageDepositAmount !== undefined
    ? Big(params.leverageDepositAmount).gt(0) : !draft.close && (!draft.editing || delta.gt(0));
  const minimum = position
    ? depositLimits.minIncreaseDepositUsdc
    : depositLimits.minOpenDepositUsdc;
  const payment = params.leverageDepositAmount !== undefined
    ? Big(params.leverageDepositAmount) : delta.plus(PERPS_CCTP_FORWARD_FEE_USDC).round(6, Big.roundUp);
  const requiredUsdc = deposits ? (payment.gt(minimum) ? payment : Big(minimum)).toFixed() : '0';
  // Display an approximate reserve; positive balances use the execution fee check.
  const requiredEth = deposits ? '0.0001' : '0';
  return {
    requiredUsdc, requiredEth, requiredEthUsd: deposits ? '0.25' : '0',
    usdcBalance: availableUsdc, availableCollateral: availableCollateral.gt(0) ? availableCollateral.toFixed() : '0',
    ethBalance: availableEth,
    needsUsdc: Big(availableUsdc).lt(requiredUsdc),
    needsEth: deposits && Big(availableEth).lte(0),
  };
}

export function normalizePerpsPosition(
  accountId: string,
  asset: ApiPerpsListedAsset,
  raw: ApiPerpsPosition,
): ApiPerpsAccountPosition {
  const pnl = Big(raw.unrealizedPnl);
  const margin = Big(raw.marginUsed);
  const isolated = raw.leverage.type === 'isolated';
  const collateral = isolated ? margin.minus(pnl) : margin;
  return {
    id: `${accountId}/${asset.id}`,
    assetId: asset.id,
    dex: asset.dex,
    side: Big(raw.szi).lt(0) ? 'short' : 'long',
    size: Big(raw.szi).abs().toFixed(),
    collateral: collateral.toFixed(),
    equity: (isolated ? margin : margin.plus(pnl)).toFixed(),
    isNearLiquidation: isPerpsPositionNearLiquidation(asset.context.markPx, raw),
    returnOnEquity: collateral.gt(0) ? pnl.div(collateral).toFixed() : undefined,
    funding: raw.cumFunding?.sinceOpen,
    raw,
  };
}

export function getPerpsOpenInterestUsd(asset: ApiPerpsListedAsset): string | undefined {
  try {
    const quantity = Big(asset.context.openInterest);
    const price = Big(asset.context.markPx);
    return quantity.gte(0) && price.gt(0) ? quantity.mul(price).toFixed() : undefined;
  } catch {
    return undefined;
  }
}

/** Warn after consuming 80% of the entry-to-liquidation price distance, in either direction. */
export function isPerpsPositionNearLiquidation(markPrice: string, position: ApiPerpsPosition): boolean {
  if (!position.entryPx || !position.liquidationPx) return false;
  try {
    const entry = Big(position.entryPx);
    const liquidation = Big(position.liquidationPx);
    const mark = Big(markPrice);
    const isShort = Big(position.szi).lt(0);
    if (entry.lte(0) || liquidation.lte(0) || mark.lte(0) || Big(position.szi).eq(0)) return false;
    const distance = isShort ? liquidation.minus(entry) : entry.minus(liquidation);
    const movement = isShort ? mark.minus(entry) : entry.minus(mark);
    return distance.gt(0) && movement.gte(distance.mul('0.8'));
  } catch {
    return false;
  }
}

function getPerpsPositionMargin(position: ApiPerpsPosition): Big {
  try {
    const rawUsd = Big(position.leverage.rawUsd ?? '0');
    if (rawUsd.gt(0)) return rawUsd;
  } catch { /* The backend falls back to marginUsed when rawUsd is unavailable. */ }
  const margin = Big(position.marginUsed);
  return margin.gt(0) ? margin : Big(0);
}

export function resolvePerpsTradeIntent(
  request: ApiPerpsDraftRequest | ApiPerpsTradeIntent, position?: ApiPerpsAccountPosition,
): ApiPerpsDraftRequest {
  if (!('kind' in request)) return request;
  if (request.kind === 'open') {
    const amount = Big(request.depositAmount).minus(PERPS_CCTP_FORWARD_FEE_USDC);
    if (amount.lte(0)) throw new Error('PerpsInvalidAmount');
    return {
      assetId: request.assetId, side: request.side, amount: amount.toFixed(), unit: 'currency',
      leverage: request.leverage,
    };
  }
  if (!position) throw new Error('PerpsPositionChanged');
  const draft: ApiPerpsDraftRequest = {
    assetId: request.assetId, side: position.side, amount: position.collateral, unit: 'currency',
    leverage: position.raw.leverage.value, editing: true,
  };
  switch (request.kind) {
    case 'increase': {
      const credit = Big(request.amount).minus(PERPS_CCTP_FORWARD_FEE_USDC);
      if (credit.lte(0)) throw new Error('PerpsInvalidAmount');
      draft.amount = Big(position.collateral).plus(credit).toFixed();
      break;
    }
    case 'reduce': {
      const released = Big(request.amount);
      if (released.lte(0)) throw new Error('PerpsInvalidAmount');
      draft.amount = Big(position.collateral).minus(released).toFixed();
      break;
    }
    case 'leverage':
      draft.leverage = request.leverage;
      draft.leverageOnly = true;
      break;
    case 'close':
      draft.close = true;
      break;
  }
  return draft;
}

/** Resolve target collateral into the backend's gross USDC resize intent. */
export function resolvePerpsDraft(params: {
  accountId: string;
  address: string;
  asset: ApiPerpsListedAsset;
  draft: ApiPerpsDraftRequest;
  position?: ApiPerpsAccountPosition;
  requestedKind?: ApiPerpsOperationKind;
  availableUsdc: string;
  /** `limitsByChain` for this asset's chain from `GET /perps/assets`. */
  depositLimits: ApiPerpsLimits;
  now: number;
  id: string;
}): ApiPerpsQuote {
  const { accountId, address, asset, draft, position, now, id } = params;
  const availability = getPerpsMarketTradingAvailability(asset);
  if (!availability.isAvailable) throw new Error(availability.reason);
  const price = Big(asset.context.markPx);
  if (price.lte(0)) throw new Error('PerpsMarketUnavailable');
  if (draft.editing && !position) throw new Error('PerpsPositionChanged');
  if (draft.leverageOnly && (!draft.editing || !position)) throw new Error('PerpsPositionChanged');
  if (!draft.editing && position) throw new Error('PerpsPositionExists');
  const keepsLeverage = position && draft.leverage === position.raw.leverage.value && !draft.leverageOnly;
  if (!Number.isInteger(draft.leverage) || draft.leverage < 1
    || (!keepsLeverage && draft.leverage > asset.maxLeverage)) {
    throw new Error('PerpsInvalidLeverage');
  }
  if (position && !draft.close && draft.leverageOnly === false && draft.leverage !== position.raw.leverage.value) {
    throw new Error('PerpsPositionChanged');
  }
  const leverage = draft.leverage;
  const side = position?.side ?? draft.side;
  const oldCollateral = position ? Big(position.collateral) : Big(0);
  const oldSize = position ? Big(position.raw.szi).abs() : Big(0);
  const fee = Big(PERPS_CCTP_FORWARD_FEE_USDC);
  const target = resolveTargetCollateral(params);
  if ((target.lt(0) && !params.requestedKind) || (!position && target.lte(0))) {
    throw new Error('PerpsInvalidAmount');
  }
  if (position && oldCollateral.lte(0) && !draft.close && !params.requestedKind) {
    throw new Error('PerpsPositionChanged');
  }
  const delta = target.minus(oldCollateral);
  const requestedKind = params.requestedKind === 'leverage' && leverage === position?.raw.leverage.value
    ? 'unchanged' : params.requestedKind;
  const kind = requestedKind ?? (!position
    ? 'open'
    : target.eq(0)
      ? 'close'
      : delta.gt(0)
        ? 'increase'
        : delta.lt(0)
          ? 'reduce'
          : leverage !== position.raw.leverage.value
            ? 'leverage'
            : 'unchanged');
  if (position && kind !== 'leverage' && kind !== 'close' && leverage !== position.raw.leverage.value) {
    throw new Error('PerpsChangeLeverageSeparately');
  }
  const reducing = kind === 'reduce' || kind === 'close';
  const orderPrice = price.toFixed();
  const payment = kind === 'open' || kind === 'increase' ? delta.plus(fee).round(6, Big.roundUp) : Big(0);
  const released = delta.abs().round(6, Big.roundDown);
  const tradeSize = kind === 'close' ? oldSize
    : (reducing ? released : payment.gt(0) ? payment.minus(fee) : Big(0))
      .mul(leverage).div(orderPrice).round(asset.szDecimals, reducing ? Big.roundUp : Big.roundDown);
  if (kind === 'reduce' && released.lte(fee)) throw new Error('PerpsAmountTooSmall');
  if (payment.gt(params.availableUsdc)) throw new Error('PerpsInsufficientUsdc');

  if (kind === 'open' && payment.lt(params.depositLimits.minOpenDepositUsdc)) throw new Error('PerpsAmountTooSmall');
  if (kind === 'increase' && !payment.gt(params.depositLimits.minIncreaseDepositUsdc)) {
    throw new Error('PerpsAmountTooSmall');
  }
  const minPositionMargin = params.depositLimits.minPositionMarginUsdc;
  const targetMargin = position ? getPerpsPositionMargin(position.raw).plus(delta) : target;
  if ((kind === 'open' || kind === 'increase' || kind === 'reduce') && targetMargin.lt(minPositionMargin)) {
    throw new Error('PerpsAmountTooSmall');
  }
  const targetSize
    = kind === 'leverage' || kind === 'unchanged'
      ? oldSize : reducing ? oldSize.minus(tradeSize) : oldSize.plus(tradeSize);
  const input = (amount: Big) =>
    draft.unit === 'asset'
      ? amount.mul(leverage).div(price).round(asset.szDecimals, Big.roundDown).toFixed()
      : amount.round(6, Big.roundDown).toFixed();
  const quote: ApiPerpsQuote = {
    id,
    accountId,
    assetId: asset.id,
    wireAssetIndex: getPerpsWireAssetIndex(asset),
    kind,
    side,
    leverage,
    previousLeverage: position?.raw.leverage.value,
    isCross: position?.raw.leverage.type === 'cross',
    inputAmount: input(target),
    currentInputAmount: position ? input(oldCollateral) : undefined,
    collateral: target.toFixed(),
    previousCollateral: position?.collateral,
    previousFunding: position?.funding,
    equity: position?.equity,
    profitLoss: position?.raw.unrealizedPnl,
    returnOnEquity: position?.returnOnEquity,
    size: targetSize.toFixed(),
    orderSize: tradeSize.toFixed(),
    previousSize: position ? oldSize.toFixed() : undefined,
    notional: targetSize.mul(price).toFixed(),
    previousNotional: position ? oldSize.mul(price).toFixed() : undefined,
    markPrice: price.toFixed(),
    entryPrice: position?.raw.entryPx ?? undefined,
    liquidationPrice: position?.raw.liquidationPx ?? undefined,
    paymentAmount: payment.toFixed(),
    receiveStatus: reducing ? 'pending' : undefined,
    bridgeFee: payment.gt(0) ? fee.toFixed() : '0',
    createdAt: now,
    expiresAt: now + 60_000,
  };
  const common = { chain: asset.chain, address, asset: asset.id, slippage: Number(PERPS_REVIEW_PRICE_TOLERANCE) };
  if (kind === 'open') {
    quote.open = {
      ...common,
      side,
      depositAmount: payment.toFixed(),
      leverage,
      isCross: false,
    };
  } else if (kind === 'close') {
    quote.close = { ...common };
  } else if (kind === 'leverage') {
    quote.modify = { ...common, leverage };
  } else if (kind !== 'unchanged') {
    quote.modify = {
      ...common,
      depositAmount: reducing ? released.toFixed() : payment.toFixed(),
      reduceOnly: reducing,
    };
  }
  return quote;
}

/** Gross USDC from `/perps/position/modify/estimate`. `"0"` leaves the position size unchanged. */
export function applyPerpsLeverageChangeDeposit(
  quote: ApiPerpsQuote,
  depositAmount: string,
  availableUsdc: string,
) {
  if (quote.kind !== 'leverage' || quote.modify?.leverage === undefined) {
    throw new Error('PerpsReviewChanged');
  }

  const trimmed = depositAmount.trim();
  if (!/^\d+(\.\d{1,6})?$/.test(trimmed)) throw new Error('PerpsInvalidAmount');
  const deposit = Big(trimmed);
  if (deposit.eq(0)) {
    quote.modify = { ...quote.modify, depositAmount: '0' };
    quote.paymentAmount = '0';
    quote.bridgeFee = '0';
    return;
  }

  const fee = Big(PERPS_CCTP_FORWARD_FEE_USDC);
  if (deposit.lte(fee)) throw new Error('PerpsAmountTooSmall');
  if (deposit.gt(availableUsdc)) throw new Error('PerpsInsufficientUsdc');

  quote.paymentAmount = trimmed;
  quote.bridgeFee = fee.toFixed();
  quote.collateral = Big(quote.collateral).plus(deposit.minus(fee)).toFixed();
  quote.modify = { ...quote.modify, depositAmount: trimmed };
}

export function getPerpsReviewedLimitPrice(price: Big, szDecimals: number, buying: boolean): string {
  const limit = Number(price) * (1 + Number(PERPS_REVIEW_PRICE_TOLERANCE) * (buying ? 1 : -1));
  if (!Number.isFinite(limit) || limit <= 0) throw new Error('PerpsMarketUnavailable');
  // Match the backend's significant-digit rounding followed by the asset's price decimals.
  return String(Number(Number(limit.toPrecision(5)).toFixed(Math.max(0, 6 - szDecimals))));
}

/** Bounds the signed or estimated quantity by the reviewed collateral intent, including one lot of rounding. */
export function validatePerpsOrderSize(quote: ApiPerpsQuote, asset: ApiPerpsListedAsset, quantity: string) {
  const size = Big(quantity);
  if (size.lte(0)) throw new Error('PerpsAmountTooSmall');
  if (quote.kind === 'close' || quote.kind === 'leverage') {
    if (!quote.previousSize || !size.eq(quote.previousSize)) throw new Error('PerpsReviewChanged');
    return;
  }
  const reducing = quote.kind === 'reduce';
  const collateral = reducing
    ? Big(quote.modify?.depositAmount ?? '0') : Big(quote.paymentAmount).minus(PERPS_CCTP_FORWARD_FEE_USDC);
  const reference = Big(asset.context.midPx ?? asset.context.markPx);
  const referenceSize = collateral.mul(quote.leverage).div(reference);
  const slippage = Big(PERPS_REVIEW_PRICE_TOLERANCE);
  const lot = Big(10).pow(-asset.szDecimals);
  const minimum = referenceSize.div(Big(1).plus(slippage)).minus(lot);
  const maximum = referenceSize.div(Big(1).minus(slippage)).plus(reducing ? lot : 0);
  if (collateral.lte(0) || size.lt(minimum) || size.gt(maximum)
    || (reducing && (!quote.previousSize || size.gt(quote.previousSize)))) {
    throw new Error('PerpsReviewChanged');
  }
}

export function validatePerpsReviewedBuild(
  quote: ApiPerpsQuote,
  asset: ApiPerpsListedAsset,
  build: {
    marketReferencePrice?: string;
    action?: Record<string, unknown>;
    deposit?: ApiPerpsCctpDeposit;
    updateLeverage?: { action: Record<string, unknown> };
    updateIsolatedMargin?: { action: Record<string, unknown> };
  },
) {
  if (quote.kind === 'unchanged') throw new Error('PerpsUnchanged');
  if (quote.expiresAt < Date.now()) throw new Error('PerpsQuoteExpired');
  const wireAssetIndex = getPerpsWireAssetIndex(asset);
  if (asset.id !== quote.assetId || !getPerpsMarketTradingAvailability(asset).isAvailable
    || quote.wireAssetIndex !== wireAssetIndex) {
    throw new Error('PerpsReviewChanged');
  }
  const leverageAction = build.updateLeverage?.action;
  if (quote.kind === 'open' && !leverageAction) throw new Error('PerpsReviewChanged');
  if (
    leverageAction
    && (leverageAction.asset !== wireAssetIndex
      || leverageAction.leverage !== quote.leverage
      || leverageAction.isCross !== quote.isCross)
  ) {
    throw new Error('PerpsReviewChanged');
  }
  if (quote.kind === 'leverage') {
    if (!leverageAction || build.action) throw new Error('PerpsReviewChanged');
    const depositAmount = String(quote.modify?.depositAmount ?? '0');
    const needsDeposit = Big(depositAmount).gt(0);
    if (!needsDeposit) {
      if (build.deposit || build.updateIsolatedMargin) throw new Error('PerpsReviewChanged');
      return;
    }
    if (!Big(quote.paymentAmount).eq(depositAmount)) throw new Error('PerpsReviewChanged');
    const marginAction = build.updateIsolatedMargin?.action;
    const address = quote.modify?.address;
    if (!build.deposit || !address || !marginAction) throw new Error('PerpsReviewChanged');
    assertPerpsCctpDepositIntegrity(build.deposit, address, depositAmount);
    const ntli = Big(depositAmount).minus(PERPS_CCTP_FORWARD_FEE_USDC).mul(1_000_000).round(0, Big.roundHalfUp);
    if (
      marginAction.type !== 'updateIsolatedMargin'
      || marginAction.asset !== leverageAction.asset
      || marginAction.isBuy !== true
      || typeof marginAction.ntli !== 'number'
      || !ntli.eq(marginAction.ntli)
    ) {
      throw new Error('PerpsReviewChanged');
    }
    return;
  }
  const marginAction = build.updateIsolatedMargin?.action;
  const orders = build.action?.orders;
  if (!Array.isArray(orders) || orders.length !== 1) throw new Error('PerpsReviewChanged');
  const order = orders[0];
  const reducing = quote.kind === 'reduce' || quote.kind === 'close';
  const buying = reducing ? quote.side === 'short' : quote.side === 'long';
  if (build.marketReferencePrice === undefined) throw new Error('PerpsReviewChanged');
  const marketReference = Big(asset.context.midPx ?? asset.context.markPx);
  const reference = Big(build.marketReferencePrice);
  if (reference.lte(0) || marketReference.lte(0)) throw new Error('PerpsMarketUnavailable');
  if (reference.div(marketReference).minus(1).abs().gt(PERPS_REVIEW_PRICE_TOLERANCE)) {
    throw new Error('PerpsReviewChanged');
  }
  const limit = Big(getPerpsReviewedLimitPrice(reference, asset.szDecimals, buying));
  const size = Big(order.s);
  if (
    order.a !== wireAssetIndex
    || (marginAction && marginAction.asset !== order.a)
    || order.b !== buying
    || order.r !== reducing
    || order.t?.limit?.tif !== 'Ioc'
    || Object.keys(order.t).length !== 1
    || Object.keys(order.t.limit).length !== 1
    || size.lte(0)
    || Big(order.p).lte(0)
    || (buying ? Big(order.p).gt(limit) : Big(order.p).lt(limit))
  ) {
    throw new Error('PerpsReviewChanged');
  }
  validatePerpsOrderSize(quote, asset, order.s);
  if (quote.kind === 'open' || quote.kind === 'increase') {
    const address = quote.open?.address ?? quote.modify?.address;
    if (!build.deposit || !address) {
      throw new Error('PerpsReviewChanged');
    }
    assertPerpsCctpDepositIntegrity(build.deposit, address, quote.paymentAmount);
  } else if (build.deposit) throw new Error('PerpsReviewChanged');
}
