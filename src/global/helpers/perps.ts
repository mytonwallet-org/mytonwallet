import type { ApiPerpsDraftRequest, ApiPerpsFill, ApiPerpsOperation, ApiPerpsQuote } from '../../api/types';
import type { Account, PerpsAccountSnapshot, PerpsErrorDetails, PerpsTradeState } from '../types';

import { Big } from '../../lib/big.js';
import { getIsViewAccountDisabled } from '../../util/isViewAccount';
import { PERPS_ERROR_AMOUNT_KEYS } from '../../util/perpsErrorFields';
import { errorCodeToMessage, isApiDisplayError } from './errors';

export const PERPS_DEFAULT_LEVERAGE = 2;
export const PERPS_AMOUNT_DECIMALS = 2;
export const PERPS_ONBOARDING_BANNER_ID = 'perps-onboarding';

const NON_ZERO_DIGIT_REGEX = /[1-9]/;
const PERPS_ERROR_CODE_REGEX = /\bPerps[A-Za-z]+/;
// Digits with at most one point and no sign or exponent, as the iOS app accepts them
const PERPS_DECIMAL_REGEX = /^(\d+(\.\d*)?|\.\d+)$/;
const PERPS_ERROR_KEYS = [
  'PerpsReviewChanged', 'PerpsWithdrawalPending', 'PerpsQuoteExpired', 'PerpsInsufficientUsdc', 'PerpsInsufficientGas',
  'PerpsAmountTooSmall', 'PerpsUnchanged', 'PerpsOrderTooSmall', 'PerpsOrderNotFilled', 'PerpsInsufficientMargin',
  'PerpsOrderRejected', 'PerpsPositionChanged', 'PerpsPositionExists', 'PerpsOperationPending',
  'PerpsUnsupportedAccount', 'PerpsInvalidLeverage', 'PerpsInvalidAmount', 'PerpsChangeLeverageSeparately',
  'PerpsTradingUnavailable', 'PerpsIncompleteData', 'PerpsReviewUpdated', 'PerpsExecutionUnknown',
  'PerpsInsufficientBalance', 'PerpsMarketNeedsUnifiedAccount', 'PerpsNothingToWithdraw', 'PerpsWithdrawalRejected',
  'PerpsRequiresMultichainWallet', 'PerpsRequiresOwnWallet',
];

/** The wallet cannot open a Futures position: it has no Arbitrum address, or the app cannot sign with it */
export function getIsPerpsAccountDisabled(account: Account) {
  return getIsViewAccountDisabled(account) || account.type === 'hardware' || !account.byChain.arbitrum;
}

/**
 * The SDK draft of the trade form. An edit changes only the amount and keeps the leverage. A percentage goes as
 * `fraction`, which the SDK applies to the exact balance or collateral, while the field shows the amount in cents.
 */
export function buildPerpsDraft(trade: PerpsTradeState, options?: { leverage?: number }): ApiPerpsDraftRequest {
  const base = {
    assetId: trade.assetId,
    side: trade.side,
    leverage: options?.leverage ?? trade.leverage,
    ...(trade.fundingSource === 'balance' && { funding: trade.fundingSource }),
  };
  const fraction = trade.fraction !== undefined ? { fraction: trade.fraction } : undefined;

  if (trade.kind === 'close') {
    return { ...base, amount: '0', editing: true, close: true };
  }

  if (trade.kind !== 'edit') {
    return { ...base, amount: trade.amount || '0', ...fraction };
  }

  // A share resizes from the current collateral
  if (fraction) {
    return { ...base, amount: trade.currentCollateral!, editing: true, ...fraction };
  }

  return { ...base, amount: trade.amount || '0', editing: true };
}

/**
 * The amount a percentage button puts into the field at once: a share of the collateral the wallet can open with, or
 * the current collateral changed by that percentage, in cents
 */
export function getPerpsFractionAmount(trade: PerpsTradeState, fraction: number) {
  const base = trade.kind === 'edit' ? trade.currentCollateral : trade.funding?.availableCollateral;
  if (base === undefined) return undefined;

  const share = trade.kind === 'edit' ? 100 + fraction : fraction;
  // Cents round down, as in `currentAmount`, so 100% of the available collateral never exceeds it
  const amount = Big(base).times(share).div(100).round(PERPS_AMOUNT_DECIMALS, Big.roundDown);

  return amount.gt(0) ? amount.toFixed() : '';
}

/** The amount field holds more than zero, which a typed number like "0.00" does not */
export function hasPerpsAmount(amount?: string) {
  return NON_ZERO_DIGIT_REGEX.test(amount ?? '');
}

/** Both amounts are numbers of the same value, as "100" and "100.0" are */
export function isPerpsAmountEqual(amount?: string, other?: string) {
  return isPerpsNumber(amount) && isPerpsNumber(other) && Big(amount).eq(other);
}

export function isPerpsNumber(value?: string): value is string {
  if (value === undefined || value === '') return false;

  try {
    Big(value);
    return true;
  } catch {
    return false;
  }
}

/**
 * The SDK code of a failed Perps call, such as `PerpsQuoteExpired` from `PerpsQuoteExpired: …`, or a general API code
 * such as `ServerError`. Transport failures and other messages become `PerpsUnavailable`, so the screens never show
 * raw English text.
 */
export function getPerpsErrorCode(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const code = message.match(PERPS_ERROR_CODE_REGEX)?.[0];
  if (code) return code;

  return isApiDisplayError(message) ? message : 'PerpsUnavailable';
}

/**
 * The amounts the SDK attaches to a failed Perps call, which the trade screens show instead of the general text of the
 * code. An amount that is not a plain decimal and an `isMinimumExclusive` that is not a boolean are dropped.
 */
export function getPerpsErrorDetails(error: unknown): PerpsErrorDetails | undefined {
  if (!(error instanceof Error)) return undefined;

  const fields = error as Error & Record<string, unknown>;
  const details: PerpsErrorDetails = {};
  for (const key of PERPS_ERROR_AMOUNT_KEYS) {
    const value = fields[key];
    if (typeof value === 'string' && PERPS_DECIMAL_REGEX.test(value)) details[key] = value;
  }
  if (details.minimumAmount !== undefined && typeof fields.isMinimumExclusive === 'boolean') {
    details.isMinimumExclusive = fields.isMinimumExclusive;
  }

  return Object.keys(details).length ? details : undefined;
}

/** The text key of an SDK or API error code. A code the app does not know gets the generic unavailability text. */
export function getPerpsErrorKey(code?: string) {
  const key = code && PERPS_ERROR_KEYS.find((errorKey) => code.includes(errorKey));
  if (key) return key;

  return code && isApiDisplayError(code) ? errorCodeToMessage(code) : 'PerpsUnavailable';
}

/** A trade whose proceeds Hyperliquid refused to withdraw, so the USDC stayed on the Hyperliquid balance */
export function isPerpsWithdrawalRejected(operation: ApiPerpsOperation) {
  return operation.kind !== 'withdraw' && Boolean(operation.error?.startsWith('PerpsWithdrawalRejected'));
}

/** Trades without `activityId` are told apart by their time, market and order */
export function getPerpsFillKey(fill: ApiPerpsFill) {
  return fill.activityId ?? `${fill.time}:${fill.coin}:${fill.oid}`;
}

/** The fill of the operation in the loaded history, which carries its actual fees and withdrawal */
export function findPerpsOperationFill(operation: ApiPerpsOperation, fills?: ApiPerpsFill[]) {
  if (operation.orderId === undefined) return undefined;

  return fills?.find(({ oid }) => oid === operation.orderId);
}

/**
 * The position right after the operation, once the snapshot shows it. The receipt keeps this position, since a later
 * snapshot also reflects price moves and later trades.
 */
export function findPerpsReceiptPosition(
  operation: ApiPerpsOperation,
  quote: ApiPerpsQuote,
  snapshot?: PerpsAccountSnapshot,
  fill?: ApiPerpsFill,
) {
  if ((operation.state !== 'completed' && operation.state !== 'partial') || !snapshot) return undefined;
  if (snapshot.timestamp < operation.createdAt) return undefined;

  const position = snapshot.positions.find(({ assetId }) => assetId === operation.assetId);
  if (!position || snapshot.unavailableDexs.includes(position.dex)) return undefined;
  if (position.side !== quote.side || position.raw.leverage.value !== quote.leverage) return undefined;

  // A trade changes the size, so the position shows the trade only when its size is the size after the fill. The sizes
  // are compared by value without sign, since `position.size` has none and one size may come as `0.20` and `0.2`.
  const sizeAfterFill = fill && (operation.positionSize ?? fill.positionSize);
  const isPositionAfterFill = isPerpsNumber(sizeAfterFill) && Big(sizeAfterFill).abs().eq(position.size);
  if (operation.kind !== 'leverage' && !isPositionAfterFill) return undefined;

  return position;
}
