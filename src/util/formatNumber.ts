import type { ApiBaseCurrency, ApiCurrencyRates, ApiTokenWithPrice } from '../api/types';

import { CURRENCIES, DEFAULT_PRICE_CURRENCY, WHOLE_PART_DELIMITER } from '../config';
import { Big } from '../lib/big.js';
import { bigintAbs } from './bigint';
import { calculateTokenPrice } from './calculatePrice';
import { toDecimal } from './decimals';
import withCache from './withCache';

// Short symbols sit before the amount by default (e.g. `$100`); a currency can opt into the end (e.g. `100 GRAM`)
const DEFAULT_SHORT_SYMBOL_POSITION = 'start' as const;

const SHORT_SYMBOL_POSITIONS = new Map(
  Object.values(CURRENCIES)
    .filter((currency) => currency.shortSymbol)
    .map((currency) => [currency.shortSymbol!, currency.shortSymbolPosition ?? DEFAULT_SHORT_SYMBOL_POSITION] as const),
);

export const formatNumber = withCache((
  value: number | Big | string,
  fractionDigits = 2,
  noTruncate?: boolean,
) => {
  let bigValue = new Big(value);

  if (bigValue.eq(0)) return '0';

  const isNegative = bigValue.lt(0);
  if (isNegative) bigValue = bigValue.neg();

  const method = bigValue.lt(1) ? 'toPrecision' : 'round';
  let formatted = bigValue[method](fractionDigits, noTruncate ? Big.roundHalfUp : Big.roundDown)
    .toString()
    // Remove extra zeros after rounding to the specified accuracy
    .replace(/(\.\d*?)0+$/, '$1')
    .replace(/\.$/, '');

  formatted = applyThousandsGrouping(formatted);

  if (isNegative) formatted = `-${formatted}`;

  return formatted;
});

export function formatCurrency(
  value: number | string | Big,
  currency: string,
  fractionDigits?: number,
  noTruncate?: boolean,
) {
  const formatted = formatNumber(value, fractionDigits, noTruncate);
  return addCurrency(formatted, currency);
}

export function formatCurrencyExtended(
  value: number | string, currency: string, noSign = false, fractionDigits?: number, isZeroNegative?: boolean,
) {
  const numericValue = Number(value);
  const isNegative = numericValue === 0 ? isZeroNegative : (numericValue < 0);
  const prefix = !noSign ? (!isNegative ? '+\u202F' : '\u2212\u202F') : '';

  value = value.toString();
  return prefix + formatCurrency(noSign ? value : value.replace(/^-/, ''), currency, fractionDigits);
}

export function formatCurrencySimple(value: number | bigint | string, currency: string, decimals?: number) {
  if (typeof value !== 'string') {
    value = toDecimal(value, decimals);
  }
  return addCurrency(value, currency);
}

function addCurrency(value: number | string, currency: string) {
  return SHORT_SYMBOL_POSITIONS.get(currency) === 'start'
    ? `${currency}${value}`.replace(`${currency}-`, `-${currency}`)
    : `${value} ${currency}`;
}

export function getShortCurrencySymbol(currency?: ApiBaseCurrency) {
  if (!currency) currency = DEFAULT_PRICE_CURRENCY;
  return CURRENCIES[currency].shortSymbol ?? currency;
}

function applyThousandsGrouping(str: string) {
  const [wholePart, fractionPart = ''] = str.split('.');
  const groupedWhole = wholePart.replace(/\B(?=(\d{3})+(?!\d))/g, `$&${WHOLE_PART_DELIMITER}`);

  return [groupedWhole, fractionPart].filter(Boolean).join('.');
}

// Round to integer at ≥10%, keep one decimal below. `roundHalfUp` keeps negative ties symmetric with positives
export function formatPercent(value: number): string {
  const dp = Math.abs(value) >= 10 ? 0 : 1;
  return `${new Big(value).round(dp, Big.roundHalfUp).toString()}%`;
}

export function formatBaseCurrencyAmount(
  amount: bigint,
  baseCurrency: ApiBaseCurrency,
  token: Pick<ApiTokenWithPrice, 'decimals' | 'priceUsd'>,
  currencyRates: ApiCurrencyRates,
) {
  const price = calculateTokenPrice(token.priceUsd || 0, baseCurrency, currencyRates);
  const baseCurrencyAmount = Big(toDecimal(bigintAbs(amount), token.decimals, true)).mul(price);
  const shortBaseSymbol = getShortCurrencySymbol(baseCurrency);
  // The rounding logic should match the original amount rounding logic implemented by formatCurrencyExtended.
  // It's for cases when the base currency matches the transaction currency.
  return formatCurrency(baseCurrencyAmount, shortBaseSymbol);
}
