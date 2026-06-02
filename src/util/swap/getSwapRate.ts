import type { ApiSwapAsset } from '../../api/types';

import { Big } from '../../lib/big.js';
import { formatNumber } from '../formatNumber';

const BTC = new Set(['jWBTC', 'oWBTC', 'BTC']);
const USD = new Set(['jUSDT', 'oUSDT', 'USDT', 'jUSDC', 'oUSDC', 'USDC', 'USD₮']);
const FIAT = new Set(['USD', 'RUB', 'EUR', 'CNY']);

const LARGE_NUMBER = 1000;

function getCurrencyPriority(symbol: string) {
  if (FIAT.has(symbol)) return 5;
  if (USD.has(symbol)) return 4;
  if (BTC.has(symbol)) return 3;
  // FIXME: TON renaming
  if (symbol === 'TON') return 2;

  return 1;
}

export default function getSwapRate(
  fromAmount?: string,
  toAmount?: string,
  fromToken?: Pick<ApiSwapAsset, 'symbol'>,
  toToken?: Pick<ApiSwapAsset, 'symbol'>,
  shouldTrimLargeNumber = false,
) {
  if (!fromAmount || !toAmount || !fromToken || !toToken) {
    return undefined;
  }

  let firstCurrencySymbol = fromToken.symbol;
  let secondCurrencySymbol = toToken.symbol;
  let price: string;
  const fromAmountBig = new Big(fromAmount);
  const toAmountBig = new Big(toAmount);

  if (fromAmountBig.eq(0) || toAmountBig.eq(0)) {
    return undefined;
  }

  const fromPriority = getCurrencyPriority(firstCurrencySymbol);
  const toPriority = getCurrencyPriority(secondCurrencySymbol);

  if (toPriority < fromPriority) {
    firstCurrencySymbol = toToken.symbol;
    secondCurrencySymbol = fromToken.symbol;
    const ratio = fromAmountBig.div(toAmount);
    const isLargeNumber = shouldTrimLargeNumber && ratio.gte(LARGE_NUMBER);
    price = formatNumber(ratio.toNumber(), isLargeNumber ? 0 : 4);
  } else {
    const ratio = toAmountBig.div(fromAmount);
    const isLargeNumber = shouldTrimLargeNumber && ratio.gte(LARGE_NUMBER);
    price = formatNumber(ratio.toNumber(), isLargeNumber ? 0 : 4);
  }

  return {
    firstCurrencySymbol,
    secondCurrencySymbol,
    price,
  };
}
