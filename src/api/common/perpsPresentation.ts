import type {
  ApiPerpsCctpDeposit, ApiPerpsLimits, ApiPerpsListedAsset, ApiPerpsPosition, ApiPerpsTradingAvailability,
} from '../types/perps';
import type {
  ApiPerpsAccountPosition, ApiPerpsBalanceWithdrawalPreview, ApiPerpsDraftRequest, ApiPerpsFundingRequirements,
  ApiPerpsOperationKind, ApiPerpsQuote, ApiPerpsTradeIntent,
} from '../types/perpsTrading';

import { Big } from '../../lib/big.js';
import {
  HYPERLIQUID_BUILDER_ORDER_FEE,
  PERPS_CCTP_FORWARD_FEE_USDC,
  PERPS_CCTP_WITHDRAW_GAS_RESERVE_USDC,
  PERPS_LEVERAGE_MARGIN_HEADROOM,
  PERPS_REVIEW_PRICE_TOLERANCE,
} from './perps';
import { assertPerpsCctpDepositIntegrity } from './perpsDeposit';

/** Highest Hyperliquid perps taker rate: tier 0 on a validator-operated book. */
const PERPS_MAX_TAKER_FEE_RATE = '0.00045';
/** A HIP-3 deployer's fee scale raises its book's fees to at most six times the validator-operated rate. */
const PERPS_HIP3_MAX_FEE_MULTIPLIER = 6;
/** A balance withdrawal is offered above this balance, which delivers 0.02 USDC after the reserve and the bridge fee. */
const PERPS_BALANCE_WITHDRAWAL_MIN_BALANCE = 0.25;

type PerpsDraftAmountContext = {
  asset: ApiPerpsListedAsset;
  draft: ApiPerpsDraftRequest;
  position?: ApiPerpsAccountPosition;
  /** Wallet USDC. Required for a wallet fraction; without it, the order is not checked against the balance. */
  availableUsdc?: string;
  /** The book's spendable HyperCore USDC. Required for the fraction of a new balance-funded order. */
  spendableUsdc?: string;
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

function resolveTargetCollateral({
  asset, draft, position, availableUsdc, spendableUsdc,
}: PerpsDraftAmountContext): Big {
  const oldCollateral = Big(position?.collateral ?? 0);
  let target = Big(draft.amount || '0');
  if (draft.reset || draft.leverageOnly) target = oldCollateral;
  if (draft.fraction !== undefined) {
    if (![5, 25, 50, 100, -5, -25, -50, -100].includes(draft.fraction)) throw new Error('PerpsInvalidAmount');
    if (position) {
      target = oldCollateral.mul(Big(100).plus(draft.fraction)).div(100);
    } else {
      const available = draft.funding === 'balance'
        ? getPerpsBalanceAvailableCollateral(asset, draft.leverage, spendableUsdc!)
        : Big(availableUsdc!).minus(PERPS_CCTP_FORWARD_FEE_USDC);
      target = available.mul(draft.fraction).div(100);
    }
  }
  return draft.close ? Big(0) : target;
}

/** The book's spendable HyperCore USDC from `spendableUsdcByDex`; a missing or malformed figure spends nothing. */
export function readPerpsSpendableUsdc(spendableUsdcByDex: Record<string, string> | undefined, dex: string): string {
  return readPositiveDecimal(spendableUsdcByDex?.[dex])?.toFixed() ?? '0';
}

/**
 * What one withdrawal can send, read from the two sources `/perps/withdraw/build` debits. `spendableUsdcByDex` plays no
 * part: it repeats the same money under each book on unified accounts and omits spot USDC on standard ones. A missing
 * or malformed source holds nothing.
 */
export function getPerpsBalanceWithdrawalPreview(
  { withdrawable, spotUsdcAvailable, firstTransferFeeUsdc }: {
    withdrawable?: string; spotUsdcAvailable?: string; firstTransferFeeUsdc?: string;
  },
): ApiPerpsBalanceWithdrawalPreview | undefined {
  const native = readPositiveDecimal(withdrawable) ?? Big(0);
  const spot = readPositiveDecimal(spotUsdcAvailable) ?? Big(0);
  const balance = native.gt(spot) ? native : spot;
  const firstTransferFee = readPositiveDecimal(firstTransferFeeUsdc);
  const sendable = balance.minus(firstTransferFee ?? 0);
  if (!sendable.gt(PERPS_BALANCE_WITHDRAWAL_MIN_BALANCE)) return undefined;
  const amount = sendable.minus(PERPS_CCTP_WITHDRAW_GAS_RESERVE_USDC).round(6, Big.roundDown);
  return {
    balance: balance.toFixed(),
    amount: amount.toFixed(),
    bridgeFee: String(PERPS_CCTP_FORWARD_FEE_USDC),
    ...(firstTransferFee && { firstTransferFee: firstTransferFee.toFixed() }),
    receiveAmount: amount.minus(PERPS_CCTP_FORWARD_FEE_USDC).toFixed(),
  };
}

/**
 * What a reduce or close should deliver to the wallet: its share of the position's value, less the estimated trading and
 * bridge fees. Unknown without the fee estimate, and when that leaves nothing, in which case no withdrawal is made.
 */
export function getPerpsReceiveEstimate(
  { kind, equity, orderSize, previousSize, estimatedFees }: ApiPerpsQuote,
): string | undefined {
  if (kind !== 'reduce' && kind !== 'close') return undefined;
  if (!estimatedFees || !equity || !orderSize || !previousSize) return undefined;
  const share = kind === 'close' ? Big(1) : Big(orderSize).div(previousSize);
  const amount = Big(equity).mul(share).minus(estimatedFees.total);
  return amount.gt(0) ? amount.round(6, Big.roundDown).toFixed() : undefined;
}

/** A balance-funded draft needs no wallet funds, so no wallet balance is read for it. */
export function getPerpsBalanceFundingRequirements(
  asset: ApiPerpsListedAsset, leverage: number, spendableUsdc: string,
): ApiPerpsFundingRequirements {
  return {
    requiredUsdc: '0',
    requiredBridgeFeeUsdc: '0',
    requiredGasUsdc: '0',
    requiredEth: '0',
    requiredEthUsd: '0',
    usdcBalance: spendableUsdc,
    availableCollateral: getPerpsBalanceAvailableCollateral(asset, leverage, spendableUsdc).toFixed(),
    ethBalance: '0',
    needsUsdc: false,
    needsEth: false,
  };
}

/**
 * Refuses a balance-funded quote whose margin and estimated trading fee exceed the book's spendable USDC. Without the
 * backend's fee estimate, the margin may not exceed the most the headroom leaves.
 */
export function assertPerpsBalanceCovers(quote: ApiPerpsQuote, asset: ApiPerpsListedAsset, spendableUsdc: string) {
  if (quote.funding !== 'balance') return;
  const margin = Big(quote.paymentAmount);
  // A leverage change places no order.
  const tradingFee = quote.kind === 'leverage' ? '0' : quote.estimatedFees?.trading;
  const requiredBalance = tradingFee === undefined ? undefined : margin.plus(tradingFee);
  if (requiredBalance !== undefined
    ? requiredBalance.gt(spendableUsdc)
    : margin.gt(getPerpsBalanceAvailableCollateral(asset, quote.leverage, spendableUsdc))) {
    throw Object.assign(new Error('PerpsInsufficientBalance'), {
      requiredBalance: requiredBalance?.toFixed(),
      availableBalance: spendableUsdc,
    });
  }
}

/**
 * The most a balance-funded order can post as margin from the book's spendable USDC, leaving room for its trading
 * fee on the full notional: `spendable / (1 + leverage × rate)`, rounded down to micro-USDC.
 */
function getPerpsBalanceAvailableCollateral(asset: ApiPerpsListedAsset, leverage: number, spendableUsdc: string): Big {
  const available = Big(spendableUsdc).div(getPerpsBalanceFeeRate(asset).mul(leverage).plus(1))
    .round(6, Big.roundDown);
  return available.gt(0) ? available : Big(0);
}

/**
 * Trading-fee rate the balance headroom reserves: the book's highest taker rate plus the builder fee every order
 * carries, rounded up to 0.01% so the backend's fee estimate, rounded to micro-USDC, stays within it.
 */
function getPerpsBalanceFeeRate(asset: ApiPerpsListedAsset): Big {
  const taker = Big(PERPS_MAX_TAKER_FEE_RATE).mul(asset.dex ? PERPS_HIP3_MAX_FEE_MULTIPLIER : 1);
  return taker.plus(Big(HYPERLIQUID_BUILDER_ORDER_FEE).div(100_000)).round(4, Big.roundUp);
}

/** Arbitrum funding is required only for orders that deposit more collateral. */
export function getPerpsFundingRequirements(params: PerpsDraftAmountContext & {
  availableUsdc: string;
  availableEth: string;
  depositLimits: Pick<ApiPerpsLimits, 'minOpenDepositUsdc' | 'minIncreaseDepositUsdc'>;
  leverageDepositAmount?: string;
  /** Paymaster cost in USDC. Set when the deposit is gasless. */
  requiredGasUsdc?: string;
  /** Deposit gas in ETH. Set when the wallet pays that gas; `usd` is absent while the ETH price is unknown. */
  nativeFee?: { eth: string; usd?: string };
}): ApiPerpsFundingRequirements {
  const { draft, position, availableUsdc, availableEth, depositLimits } = params;
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
  let requiredGasUsdc = '0';
  let requiredEth = '0';
  let requiredEthUsd = '0';
  let needsEth = false;
  if (deposits && params.nativeFee) {
    // Without an ETH price, the requirement uses a display reserve of 0.0001 ETH
    const priced = params.nativeFee.usd !== undefined ? params.nativeFee : { eth: '0.0001', usd: '0.25' };
    requiredEth = priced.eth;
    requiredEthUsd = priced.usd ?? '0';
    needsEth = Big(availableEth).lte(0);
  } else if (deposits && params.requiredGasUsdc !== undefined) {
    try {
      const reserve = Big(params.requiredGasUsdc);
      requiredGasUsdc = reserve.gte(0) ? reserve.toFixed() : '0';
    } catch {
      requiredGasUsdc = '0';
    }
  }
  const totalUsdc = Big(requiredUsdc).plus(requiredGasUsdc);
  return {
    requiredUsdc,
    requiredBridgeFeeUsdc: deposits ? String(PERPS_CCTP_FORWARD_FEE_USDC) : '0',
    requiredGasUsdc,
    requiredEth,
    requiredEthUsd,
    usdcBalance: availableUsdc,
    availableCollateral: availableCollateral.gt(0) ? availableCollateral.toFixed() : '0',
    ethBalance: availableEth,
    needsUsdc: totalUsdc.gt(0) && Big(availableUsdc).lt(totalUsdc),
    needsEth,
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
    funding: raw.cumFunding && Big(0).minus(raw.cumFunding.sinceOpen).toFixed(),
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

export function resolvePerpsTradeIntent(
  request: ApiPerpsDraftRequest | ApiPerpsTradeIntent, position?: ApiPerpsAccountPosition,
): ApiPerpsDraftRequest {
  if (!('kind' in request)) return request;
  if (request.kind === 'open') {
    const amount = Big(request.depositAmount).minus(PERPS_CCTP_FORWARD_FEE_USDC);
    if (amount.lte(0)) throw new Error('PerpsInvalidAmount');
    return { assetId: request.assetId, side: request.side, amount: amount.toFixed(), leverage: request.leverage };
  }
  if (!position) throw new Error('PerpsPositionChanged');
  const draft: ApiPerpsDraftRequest = {
    assetId: request.assetId, side: position.side, amount: position.collateral,
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
  /** Wallet USDC. Display previews omit it unless the draft is a wallet fraction, and skip the balance check. */
  availableUsdc?: string;
  /** The book's spendable HyperCore USDC, which a balance draft's fraction shares. */
  spendableUsdc?: string;
  /** `limitsByChain` for this asset's chain from `GET /perps/assets`. */
  depositLimits: ApiPerpsLimits;
  now: number;
  id: string;
}): ApiPerpsQuote {
  const { accountId, address, asset, draft, position, now, id } = params;
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
  // A reduction or close always releases its margin to the wallet, whatever the draft's funding.
  const fromBalance = draft.funding === 'balance' && (kind === 'open' || kind === 'increase' || kind === 'leverage');
  const depositFee = fromBalance ? Big(0) : fee;
  const orderPrice = price.toFixed();
  const payment = kind === 'open' || kind === 'increase' ? delta.plus(depositFee).round(6, Big.roundUp) : Big(0);
  const released = delta.abs().round(6, Big.roundDown);
  const tradeSize = kind === 'close' ? oldSize
    : (reducing ? released : payment.gt(0) ? payment.minus(depositFee) : Big(0))
      .mul(leverage).div(orderPrice).round(asset.szDecimals, reducing ? Big.roundUp : Big.roundDown);
  if (kind === 'reduce' && released.lte(fee)) {
    throw Object.assign(new Error('PerpsAmountTooSmall'), { minimumReduction: fee.toFixed() });
  }
  if (!fromBalance && params.availableUsdc !== undefined && payment.gt(params.availableUsdc)) {
    throw new Error('PerpsInsufficientUsdc');
  }

  const minPositionMargin = params.depositLimits.minPositionMarginUsdc;
  const targetMargin = position ? Big(position.raw.marginUsed).plus(delta) : target;
  // Deposit minimums are bridge limits; an order paid from the balance bridges nothing
  const isDepositTooSmall = !fromBalance && (
    (kind === 'open' && payment.lt(params.depositLimits.minOpenDepositUsdc))
    || (kind === 'increase' && !payment.gt(params.depositLimits.minIncreaseDepositUsdc))
  );
  const isMarginTooSmall = (kind === 'open' || kind === 'increase' || kind === 'reduce')
    && targetMargin.lt(minPositionMargin);
  if (isDepositTooSmall || isMarginTooSmall) {
    // The input edits invested collateral; the margin minimum also accounts for unrealized profit or loss
    let minimumAmount = position
      ? oldCollateral.plus(minPositionMargin).minus(position.raw.marginUsed) : Big(minPositionMargin);
    let isMinimumExclusive = false;
    if (!fromBalance && (kind === 'open' || kind === 'increase')) {
      const depositMinimum = oldCollateral.plus(kind === 'open'
        ? params.depositLimits.minOpenDepositUsdc : params.depositLimits.minIncreaseDepositUsdc).minus(depositFee);
      if (depositMinimum.gte(minimumAmount)) {
        minimumAmount = depositMinimum;
        isMinimumExclusive = kind === 'increase';
      }
    }
    throw Object.assign(new Error('PerpsAmountTooSmall'), {
      minimumAmount: minimumAmount.toFixed(), isMinimumExclusive,
    });
  }
  const targetSize
    = kind === 'leverage' || kind === 'unchanged'
      ? oldSize : reducing ? oldSize.minus(tradeSize) : oldSize.plus(tradeSize);
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
    inputAmount: target.round(6, Big.roundDown).toFixed(),
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
    // The released margin of a reduce or close crosses the same CCTP bridge as a deposit.
    bridgeFee: !fromBalance && (payment.gt(0) || reducing) ? fee.toFixed() : '0',
    createdAt: now,
    expiresAt: now + 60_000,
  };
  if (fromBalance) quote.funding = 'balance';
  const common = { chain: asset.chain, address, asset: asset.id, slippage: Number(PERPS_REVIEW_PRICE_TOLERANCE) };
  const funding = fromBalance ? { fundingSource: 'balance' as const } : undefined;
  if (kind === 'open' && fromBalance) {
    quote.openFromBalance = { ...common, side, amount: payment.toFixed(), leverage, isCross: false };
  } else if (kind === 'open') {
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
    quote.modify = { ...common, leverage, ...funding };
  } else if (kind !== 'unchanged') {
    quote.modify = {
      ...common,
      depositAmount: reducing ? released.toFixed() : payment.toFixed(),
      reduceOnly: reducing,
      ...funding,
    };
  }
  return quote;
}

/**
 * Gross USDC from `/perps/position/modify/estimate`, which the deposit covers with headroom. `"0"` leaves the position
 * size unchanged. Without `availableUsdc` (display previews), the deposit is not checked against the wallet balance.
 */
export function applyPerpsLeverageChangeDeposit(
  quote: ApiPerpsQuote,
  depositAmount: string,
  availableUsdc?: string,
) {
  if (quote.kind !== 'leverage' || quote.modify?.leverage === undefined) {
    throw new Error('PerpsReviewChanged');
  }

  const trimmed = depositAmount.trim();
  if (!/^\d+(\.\d{1,6})?$/.test(trimmed)) throw new Error('PerpsInvalidAmount');
  const needed = Big(trimmed);
  if (needed.eq(0)) {
    quote.modify = { ...quote.modify, depositAmount: '0' };
    quote.paymentAmount = '0';
    quote.bridgeFee = '0';
    return;
  }

  const fee = Big(PERPS_CCTP_FORWARD_FEE_USDC);
  if (needed.lte(fee)) throw new Error('PerpsAmountTooSmall');
  if (availableUsdc !== undefined && needed.gt(availableUsdc)) throw new Error('PerpsInsufficientUsdc');

  const deposit = addPerpsLeverageMarginHeadroom(quote, needed, availableUsdc);
  quote.paymentAmount = deposit.toFixed();
  quote.bridgeFee = fee.toFixed();
  quote.collateral = Big(quote.collateral).plus(deposit.minus(fee)).toFixed();
  quote.modify = { ...quote.modify, depositAmount: deposit.toFixed() };
}

/**
 * Margin a balance-funded leverage change takes from the book's spendable USDC: `marginAmount` from
 * `/perps/position/modify/estimate` with headroom. Its build sends no `depositAmount`.
 */
export function applyPerpsLeverageChangeMargin(quote: ApiPerpsQuote, marginAmount: string, availableUsdc?: string) {
  if (quote.kind !== 'leverage' || quote.modify?.leverage === undefined || quote.funding !== 'balance') {
    throw new Error('PerpsReviewChanged');
  }
  const trimmed = marginAmount.trim();
  if (!/^\d+(\.\d{1,6})?$/.test(trimmed)) throw new Error('PerpsInvalidAmount');
  const needed = Big(trimmed);
  const margin = needed.gt(0) ? addPerpsLeverageMarginHeadroom(quote, needed, availableUsdc) : needed;
  quote.paymentAmount = margin.toFixed();
  quote.collateral = Big(quote.collateral).plus(margin).toFixed();
}

/** A display preview reads the wallet after quoting, and what it holds limits the headroom as it does at Review. */
export function limitPerpsLeverageChangeDeposit(quote: ApiPerpsQuote, neededAmount: string, availableUsdc: string) {
  const deposit = Big(quote.paymentAmount);
  const limited = limitPerpsLeverageMargin(deposit, Big(neededAmount), availableUsdc);
  quote.paymentAmount = limited.toFixed();
  quote.collateral = Big(quote.collateral).minus(deposit.minus(limited)).toFixed();
  quote.modify = { ...quote.modify!, depositAmount: limited.toFixed() };
}

/**
 * What a leverage decrease needs moves with the price, so its review adds headroom for a move against the position.
 * The surplus stays in the position's margin.
 */
function addPerpsLeverageMarginHeadroom(quote: ApiPerpsQuote, needed: Big, availableUsdc?: string) {
  const reviewed = needed.plus(Big(quote.notional).mul(PERPS_LEVERAGE_MARGIN_HEADROOM)).round(2, Big.roundUp);
  return availableUsdc !== undefined ? limitPerpsLeverageMargin(reviewed, needed, availableUsdc) : reviewed;
}

/** Funds that cover the need but not the headroom limit it, to the micro-USDC that can be signed. */
function limitPerpsLeverageMargin(reviewed: Big, needed: Big, availableUsdc: string) {
  return reviewed.gt(availableUsdc) && needed.lte(availableUsdc)
    ? Big(availableUsdc).round(6, Big.roundDown)
    : reviewed;
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
  // An order paid from the balance posts its whole payment; a deposit posts its credit after the bridge fee.
  const collateral = reducing ? Big(quote.modify?.depositAmount ?? '0')
    : Big(quote.paymentAmount).minus(quote.funding === 'balance' ? 0 : PERPS_CCTP_FORWARD_FEE_USDC);
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

type PerpsWireOrder = {
  a?: unknown;
  b?: unknown;
  p?: unknown;
  r?: unknown;
  s?: unknown;
  t?: { limit?: { tif?: unknown } };
};

/** A positive decimal string. Anything else, including a number, reads as absent. */
export function readPositiveDecimal(value: unknown): Big | undefined {
  if (typeof value !== 'string') return undefined;
  try {
    const decimal = Big(value);
    return decimal.gt(0) ? decimal : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The single IOC limit order of a market build, in the expected direction, with a positive size and price.
 * Signing then requires canonical decimals, the `na` grouping and the service builder fee.
 */
export function readPerpsMarketOrder(
  action: Record<string, unknown> | undefined, buying: boolean, reducing: boolean,
): { order: PerpsWireOrder; size: Big; price: Big } {
  const orders = action?.orders;
  const order = Array.isArray(orders) && orders.length === 1 ? orders[0] as PerpsWireOrder | undefined : undefined;
  const size = readPositiveDecimal(order?.s);
  const price = readPositiveDecimal(order?.p);
  if (
    !order?.t?.limit
    || !size
    || !price
    || order.b !== buying
    || order.r !== reducing
    || order.t.limit.tif !== 'Ioc'
    || Object.keys(order.t).length !== 1
    || Object.keys(order.t.limit).length !== 1
  ) {
    throw new Error('PerpsReviewChanged');
  }
  return { order, size, price };
}

export function validatePerpsReviewedBuild(
  quote: ApiPerpsQuote,
  asset: ApiPerpsListedAsset,
  build: {
    marketReferencePrice?: string;
    action?: Record<string, unknown>;
    deposit?: ApiPerpsCctpDeposit;
    spotToPerp?: { action: Record<string, unknown> };
    setAbstraction?: { action: Record<string, unknown> };
    updateLeverage?: { action: Record<string, unknown> };
    updateIsolatedMargin?: { action: Record<string, unknown> };
  },
) {
  if (quote.kind === 'unchanged') throw new Error('PerpsUnchanged');
  if (quote.expiresAt < Date.now()) throw new Error('PerpsQuoteExpired');
  const wireAssetIndex = getPerpsWireAssetIndex(asset);
  if (asset.id !== quote.assetId || quote.wireAssetIndex !== wireAssetIndex) {
    throw new Error('PerpsReviewChanged');
  }
  const fromBalance = quote.funding === 'balance';
  if (fromBalance && (build.deposit || build.spotToPerp)) throw new Error('PerpsReviewChanged');
  if (Boolean(build.setAbstraction) !== Boolean(quote.switchesToUnified)) throw new Error('PerpsReviewChanged');
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
    if (fromBalance) {
      const margin = Big(quote.paymentAmount);
      // A cross position margins the new leverage from the balance itself; only an isolated one is topped up.
      if (quote.isCross || margin.eq(0)) {
        if (build.updateIsolatedMargin) throw new Error('PerpsReviewChanged');
        return;
      }
      assertPerpsIsolatedMarginTopUp(build.updateIsolatedMargin?.action, leverageAction, margin);
      return;
    }
    const depositAmount = String(quote.modify?.depositAmount ?? '0');
    const needsDeposit = Big(depositAmount).gt(0);
    if (!needsDeposit) {
      if (build.deposit || build.updateIsolatedMargin) throw new Error('PerpsReviewChanged');
      return;
    }
    if (!Big(quote.paymentAmount).eq(depositAmount)) throw new Error('PerpsReviewChanged');
    const address = quote.modify?.address;
    if (!build.deposit || !address) throw new Error('PerpsReviewChanged');
    assertPerpsCctpDepositIntegrity(build.deposit, address, depositAmount);
    assertPerpsIsolatedMarginTopUp(
      build.updateIsolatedMargin?.action, leverageAction, Big(depositAmount).minus(PERPS_CCTP_FORWARD_FEE_USDC),
    );
    return;
  }
  const marginAction = build.updateIsolatedMargin?.action;
  const reducing = quote.kind === 'reduce' || quote.kind === 'close';
  const buying = reducing ? quote.side === 'short' : quote.side === 'long';
  const { order, size, price } = readPerpsMarketOrder(build.action, buying, reducing);
  if (build.marketReferencePrice === undefined) throw new Error('PerpsReviewChanged');
  const marketReference = Big(asset.context.midPx ?? asset.context.markPx);
  const reference = Big(build.marketReferencePrice);
  if (reference.lte(0) || marketReference.lte(0)) throw new Error('PerpsMarketUnavailable');
  if (reference.div(marketReference).minus(1).abs().gt(PERPS_REVIEW_PRICE_TOLERANCE)) {
    throw new Error('PerpsReviewChanged');
  }
  const limit = Big(getPerpsReviewedLimitPrice(reference, asset.szDecimals, buying));
  if (
    order.a !== wireAssetIndex
    || (marginAction && marginAction.asset !== order.a)
    || (buying ? price.gt(limit) : price.lt(limit))
  ) {
    throw new Error('PerpsReviewChanged');
  }
  validatePerpsOrderSize(quote, asset, size.toFixed());
  if (fromBalance) return;
  if (quote.kind === 'open' || quote.kind === 'increase') {
    const address = quote.open?.address ?? quote.modify?.address;
    if (!build.deposit || !address) {
      throw new Error('PerpsReviewChanged');
    }
    assertPerpsCctpDepositIntegrity(build.deposit, address, quote.paymentAmount);
  } else if (build.deposit) throw new Error('PerpsReviewChanged');
}

/** `updateIsolatedMargin` adds exactly `margin` to the position whose leverage the same build changes. */
function assertPerpsIsolatedMarginTopUp(
  marginAction: Record<string, unknown> | undefined,
  leverageAction: Record<string, unknown>,
  margin: Big,
) {
  const ntli = margin.mul(1_000_000).round(0, Big.roundHalfUp);
  if (
    marginAction?.type !== 'updateIsolatedMargin'
    || marginAction.asset !== leverageAction.asset
    || marginAction.isBuy !== true
    || typeof marginAction.ntli !== 'number'
    || !ntli.eq(marginAction.ntli)
  ) {
    throw new Error('PerpsReviewChanged');
  }
}
