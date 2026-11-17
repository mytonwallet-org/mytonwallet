import type {
  ApiPerpsMarketAsset,
  ApiPerpsOperation,
  ApiPerpsOperationKind,
  ApiPerpsPositionSide,
  ApiPerpsQuote,
} from '../../../api/types';
import type { PerpsErrorDetails } from '../../../global/types';
import type { LangFn } from '../../../util/langProvider';

import { ARBITRUM, ARBITRUM_USDC_MAINNET, DEFAULT_PRICE_CURRENCY } from '../../../config';
import { Big } from '../../../lib/big.js';
import {
  getPerpsErrorKey, isPerpsNumber, isPerpsWithdrawalRejected, PERPS_AMOUNT_DECIMALS,
} from '../../../global/helpers/perps';
import { formatTimeUnit } from '../../../util/dateFormat';
import { formatCurrency, formatCurrencyExtended, getShortCurrencySymbol } from '../../../util/formatNumber';
import { toNativeDigits } from '../../../util/nativeDigits';

// Hyperliquid quotes every market and settles every position in USDC, so the screens show amounts in dollars
export const PERPS_CURRENCY_SYMBOL = getShortCurrencySymbol(DEFAULT_PRICE_CURRENCY);

export const MISSING_VALUE = '—';
const MIN_SHOWN_FEE = '0.01';
const ONE_CENT = '0.01';
const QUANTITY_DECIMALS = 12;
const FUNDING_DECIMALS = 6;

const SIDE_LABEL_KEYS: Record<ApiPerpsPositionSide, string> = {
  long: 'Long',
  short: 'Short',
};

const OPERATION_TITLE_KEYS: Record<ApiPerpsOperationKind, string> = {
  open: 'Open Position',
  increase: 'Increase Position',
  reduce: 'Reduce Position',
  close: 'Close Position',
  leverage: 'PerpsChangeLeverage',
};

export function getSideLabel(lang: LangFn, side: ApiPerpsPositionSide) {
  return lang(SIDE_LABEL_KEYS[side]);
}

export function formatLeverage(leverage: number) {
  return toNativeDigits(`${leverage}x`);
}

/** The leverage and the side, as in "5x Long" */
export function formatLeverageDirection(lang: LangFn, leverage: number, side: ApiPerpsPositionSide) {
  return lang('$perps_leverage_direction', {
    leverage: toNativeDigits(String(leverage)),
    direction: getSideLabel(lang, side),
  }) as string;
}

/** The ticker, the leverage and the side, as in "BTC 5x Long" */
export function formatPositionLabel(lang: LangFn, symbol: string, leverage: number, side: ApiPerpsPositionSide) {
  return `${symbol} ${formatLeverageDirection(lang, leverage, side)}`;
}

export function getPerpsAssetName(asset: Pick<ApiPerpsMarketAsset, 'displayName' | 'symbol'>) {
  return asset.displayName ?? asset.symbol;
}

/** The ticker of a market before the catalogue loads, as in "SKHX" for the coin "xyz:SKHX" of a HIP-3 market */
export function getPerpsCoinSymbol(coin: string) {
  return coin.slice(coin.indexOf(':') + 1);
}

export function getOperationTitle(lang: LangFn, kind: ApiPerpsOperationKind) {
  return lang(OPERATION_TITLE_KEYS[kind]);
}

/** A USDC amount the user pays or receives on Arbitrum */
export function formatPerpsUsdc(value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  return formatCurrency(value, ARBITRUM_USDC_MAINNET.symbol);
}

/** A USDC amount the SDK estimates, as in "≈ 12.5 USDC" */
export function formatPerpsUsdcEstimate(value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  return `≈ ${formatPerpsUsdc(value)}`;
}

/**
 * The Arbitrum gas of the deposit an order makes, or `undefined` for an order that deposits nothing and pays no gas.
 * A wallet without enough ETH pays the gas in USDC. A deposit the SDK could not estimate shows a dash.
 */
export function formatPerpsNetworkFee(quote: ApiPerpsQuote) {
  const { estimatedNetworkFeeUsdc, estimatedNetworkFeeUsd, estimatedNetworkFeeEth } = quote;
  if (isPerpsNumber(estimatedNetworkFeeUsdc)) return formatPerpsUsdcEstimate(estimatedNetworkFeeUsdc);
  if (isPerpsNumber(estimatedNetworkFeeUsd)) return formatPerpsFeeEstimate(estimatedNetworkFeeUsd);
  if (isPerpsNumber(estimatedNetworkFeeEth)) return `≈ ${formatCurrency(estimatedNetworkFeeEth, ARBITRUM.symbol)}`;

  // A reduce or a close returns the margin, and the Hyperliquid balance pays without a deposit
  const isDeposit = quote.funding !== 'balance' && quote.receiveStatus !== 'pending' && Number(quote.paymentAmount) > 0;

  return isDeposit ? MISSING_VALUE : undefined;
}

/** A dollar amount from the SDK. A missing or broken value shows a dash, never zero. */
export function formatPerpsMoney(value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  return formatCurrency(value, PERPS_CURRENCY_SYMBOL);
}

/** An estimated price or amount, as in "≈ $64,000" */
export function formatPerpsMoneyEstimate(value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  return `≈ ${formatPerpsMoney(value)}`;
}

/** An estimated fee, as in "≈ $0.56". A fee that rounds to zero shows as "<$0.01". */
export function formatPerpsFeeEstimate(value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  const amount = Big(value);
  if (amount.gt(0) && amount.lt(MIN_SHOWN_FEE)) {
    return `<${formatCurrency(MIN_SHOWN_FEE, PERPS_CURRENCY_SYMBOL)}`;
  }

  return formatPerpsMoneyEstimate(value);
}

/** A signed dollar amount, as in "+ $30". Zero has no sign. */
export function formatPerpsSignedMoney(value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  const amount = Big(value);
  if (amount.eq(0)) return formatPerpsMoney(value);

  return formatCurrencyExtended(value, PERPS_CURRENCY_SYMBOL, false, undefined, amount.lt(0));
}

/** The colour role of a signed amount. Zero is neutral. */
export function getPerpsValueTone(value?: string): 'positive' | 'negative' | undefined {
  if (!isPerpsNumber(value)) return undefined;

  const amount = Big(value);
  if (amount.eq(0)) return undefined;

  return amount.gt(0) ? 'positive' : 'negative';
}

/** A coin amount, as in "1,250.005 BTC" */
export function formatPerpsQuantity(symbol: string, value?: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  return toNativeDigits(formatCurrency(Big(value).abs(), symbol, QUANTITY_DECIMALS, false, true));
}

/** An amount the SDK reports in full precision, rounded for a notice, as in "0.000125" */
export function formatPerpsRequiredAmount(value: string) {
  if (!isPerpsNumber(value)) return MISSING_VALUE;

  return toNativeDigits(Big(value).round(FUNDING_DECIMALS, Big.roundHalfUp).toFixed());
}

/** A ratio from the SDK, such as `returnOnEquity`, as a percentage */
export function getPerpsRatioPercent(ratio?: string) {
  return isPerpsNumber(ratio) ? Number(Big(ratio).times(100)) : undefined;
}

/** The funding rate of the market, as in "0.0013%" */
export function formatPerpsFundingPercent({ context }: ApiPerpsMarketAsset) {
  if (!isPerpsNumber(context.fundingPercent)) return MISSING_VALUE;

  return toNativeDigits(`${Big(context.fundingPercent).round(FUNDING_DECIMALS, Big.roundHalfUp).toFixed()}%`);
}

/** The funding rate together with its interval, as in "0.0013% · 1h" */
export function formatPerpsFundingRate(lang: LangFn, asset: ApiPerpsMarketAsset) {
  const rate = formatPerpsFundingPercent(asset);
  const { fundingIntervalHours } = asset.context;
  if (rate === MISSING_VALUE || !fundingIntervalHours) return rate;

  return `${rate} · ${formatTimeUnit(lang.code!, fundingIntervalHours, 'hour')}`;
}

/** The text of an SDK or API error code. The amounts the SDK named in the error make the text exact, as on iOS. */
export function getPerpsErrorText(lang: LangFn, code?: string, details?: PerpsErrorDetails) {
  return (code && details && getPerpsErrorDetailsText(lang, code, details)) || lang(getPerpsErrorKey(code));
}

export function getOperationMessage(lang: LangFn, operation: ApiPerpsOperation) {
  if (isPerpsWithdrawalRejected(operation)) return getPerpsErrorText(lang, operation.error);
  if (operation.kind === 'withdraw') return getWithdrawalMessage(lang, operation);

  switch (operation.state) {
    case 'running':
      return lang('PerpsProcessing');
    case 'partial':
      return lang('PerpsWithdrawalPending');
    case 'unknown':
      return lang('PerpsExecutionUnknown');
    case 'failed':
      return getPerpsErrorText(lang, operation.error);
    default:
      return lang(operation.error === 'PerpsPartialFill' ? 'PerpsPartialFill' : 'PerpsReconciled');
  }
}

/** The operation and its market, as in "Increase Position · BTC" */
export function getOperationBannerTitle(lang: LangFn, operation: ApiPerpsOperation, symbol?: string) {
  if (operation.kind === 'withdraw') return formatTitleWithSymbol(lang('Withdrawal'), ARBITRUM_USDC_MAINNET.symbol);

  const title = operation.kind === 'leverage' ? lang('Edit Position') : getOperationTitle(lang, operation.kind);

  return formatTitleWithSymbol(title, symbol);
}

/** A title together with its market, as in "Increase Position · BTC" */
function formatTitleWithSymbol(title: string, symbol?: string) {
  return symbol ? `${title} · ${symbol}` : title;
}

function getPerpsErrorDetailsText(lang: LangFn, code: string, details: PerpsErrorDetails) {
  const { minimumAmount, isMinimumExclusive, minimumReduction, requiredBalance, availableBalance } = details;

  if (code === 'PerpsAmountTooSmall' && minimumAmount !== undefined) {
    const amount = formatPerpsRequiredAmount(getPerpsShownMinimum(minimumAmount, isMinimumExclusive));

    return lang('$perps_minimum_amount', { amount }) as string;
  }
  if (code === 'PerpsAmountTooSmall' && minimumReduction !== undefined) {
    return lang('$perps_minimum_reduction', { amount: formatPerpsRequiredAmount(minimumReduction) }) as string;
  }
  if (code !== 'PerpsInsufficientBalance' || availableBalance === undefined) return undefined;

  const available = formatPerpsRequiredAmount(availableBalance);
  if (requiredBalance === undefined) return lang('$perps_available_balance', { available }) as string;

  return lang('$perps_required_balance', { required: formatPerpsRequiredAmount(requiredBalance), available }) as string;
}

// The field takes whole cents, so the minimum rounds up to an amount that passes. An exclusive minimum is passed only
// by an amount above it, which is one cent more than its value rounded down.
function getPerpsShownMinimum(minimumAmount: string, isExclusive?: boolean) {
  if (!isExclusive) return Big(minimumAmount).round(PERPS_AMOUNT_DECIMALS, Big.roundUp).toFixed();

  return Big(minimumAmount).round(PERPS_AMOUNT_DECIMALS, Big.roundDown).plus(ONE_CENT).toFixed();
}

// A withdrawal from the Hyperliquid balance reaches the wallet minutes after Hyperliquid accepts it
function getWithdrawalMessage(lang: LangFn, operation: ApiPerpsOperation) {
  switch (operation.state) {
    case 'running':
      return lang('PerpsWithdrawalProcessing');
    case 'unknown':
      return lang('PerpsWithdrawalUnknown');
    case 'failed':
      return getPerpsErrorText(lang, operation.error);
    default:
      return lang('PerpsWithdrawalOnItsWay');
  }
}
