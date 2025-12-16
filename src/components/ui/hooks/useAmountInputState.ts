import { useRef, useState } from '../../../lib/teact/teact';

import type { ApiBaseCurrency, ApiTokenWithPrice } from '../../../api/types';

import { CURRENCIES } from '../../../config';
import { Big } from '../../../lib/big.js';
import { fromDecimal, toDecimal } from '../../../util/decimals';
import { vibrate } from '../../../util/haptics';
import { DEFAULT_DECIMALS } from '../../../api/chains/ton/constants';

import useLastCallback from '../../../hooks/useLastCallback';
import useSyncEffect from '../../../hooks/useSyncEffect';

type CurrentToken = Pick<ApiTokenWithPrice, 'slug' | 'decimals'> & { price: number };

interface AmountInputStateInput {
  /** The `token` amount from the state. Expressed in `token` regardless of `isBaseCurrency`. */
  amount?: bigint;
  token?: CurrentToken;
  baseCurrency: ApiBaseCurrency;
  isAmountReadonly?: boolean;
  onAmountChange: (amount?: bigint, isValueReplaced?: boolean) => void;
  /** `id` is the token slug unless `id` is specified explicitly in the token dropdown items */
  onTokenChange?: (id: string) => void;
}

export interface AmountInputStateOutput {
  isBaseCurrency: boolean;
  inputValue: string | undefined;
  alternativeValue: string | undefined;
  baseCurrency: ApiBaseCurrency;
  isAmountReadonly?: boolean;
  onInputChange: (value?: string) => void;
  onMaxAmountClick: (maxAmount?: bigint) => void;
  onAlternativeAmountClick: () => void;
  onTokenChange: (id: string, token?: CurrentToken) => void;
}

/**
 * Provides the stateful functionality for `AmountInput`. It is not embedded into `AmountInput`, because sometimes
 * `<AmountInput>` has to be remounted while its state must persist.
 */
export function useAmountInputState(input: AmountInputStateInput): AmountInputStateOutput {
  const { baseCurrency, onAmountChange, isAmountReadonly } = input;
  const { isBaseCurrency, switchCurrency, ...output } = useCurrencySwitch(input);

  const onMaxAmountClick = useLastCallback((maxAmount?: bigint) => {
    if (maxAmount === undefined) {
      return;
    }

    void vibrate();
    switchCurrency(false);
    onAmountChange(maxAmount, true);
  });

  const onAlternativeAmountClick = useLastCallback(() => {
    if (isAmountReadonly) {
      return;
    }

    void vibrate();
    switchCurrency(!isBaseCurrency);
  });

  return {
    ...output,
    isBaseCurrency,
    baseCurrency,
    onMaxAmountClick,
    onAlternativeAmountClick,
  };
}

function useCurrencySwitch({
  baseCurrency,
  amount: tokenAmountBI,
  token,
  isAmountReadonly,
  onAmountChange,
  onTokenChange: setToken,
}: AmountInputStateInput) {
  const [isBaseCurrency, setIsBaseCurrency] = useState(false);
  const tokenAmountRef = useRef<string | undefined>();
  const currencyAmountRef = useRef<string | undefined>();
  const currencyDecimals = CURRENCIES[baseCurrency].decimals;

  const setAmountsFromToken = (tokenAmount: string | undefined) => {
    tokenAmountRef.current = tokenAmount;
    currencyAmountRef.current = tokenAmountToCurrencyAmount(tokenAmount, token?.price, currencyDecimals);
  };

  const setAmountsFromCurrency = (currencyAmount: string | undefined) => {
    tokenAmountRef.current = currencyAmountToTokenAmount(currencyAmount, token?.price, token?.decimals);
    currencyAmountRef.current = currencyAmount;
  };

  const setAndReportAmountFromPrice = (price: number | undefined, decimals: number | undefined) => {
    if (isBaseCurrency && !isAmountReadonly) {
      const newTokenAmount = currencyAmountToTokenAmount(currencyAmountRef.current, price, decimals);
      if (newTokenAmount !== formalizeStringAmount(tokenAmountRef.current)) {
        tokenAmountRef.current = newTokenAmount; // If not set, the render following the `onAmountChange` call may change the input value
        onAmountChange(tokenAmountToBigInt(newTokenAmount, decimals));
      }
    } else {
      currencyAmountRef.current = tokenAmountToCurrencyAmount(tokenAmountRef.current, price, currencyDecimals);
    }
  };

  // Actualizes both values when a new token amount arrives from the parent
  useSyncEffect(() => {
    const newTokenAmount = tokenAmountFromBigInt(tokenAmountBI, token?.decimals);
    if (newTokenAmount !== formalizeStringAmount(tokenAmountRef.current)) {
      setAmountsFromToken(newTokenAmount);
    }
  }, [tokenAmountBI, token?.decimals]); // eslint-disable-line react-hooks-static-deps/exhaustive-deps

  // Actualizes the alternative (below the input) value when the token price changes.
  // If the input is readonly, actualizes only the currency value regardless of `isBaseCurrency`
  useSyncEffect(() => {
    setAndReportAmountFromPrice(token?.price, token?.decimals);
  }, [token?.price, token?.decimals, currencyDecimals]); // eslint-disable-line react-hooks-static-deps/exhaustive-deps

  const onInputChange = useLastCallback((value?: string) => {
    value ||= undefined;

    if (isBaseCurrency) {
      setAmountsFromCurrency(value);
    } else {
      setAmountsFromToken(value);
    }

    onAmountChange(tokenAmountToBigInt(tokenAmountRef.current, token?.decimals));
  });

  const onTokenChange = useLastCallback((id: string, newToken?: CurrentToken) => {
    setToken?.(id);

    if (newToken) {
      // The goal is to make the new token and the new amount arrive in the same next render.
      // Otherwise, the token amount won't change until the next render (by an above `useSyncEffect`).
      // This could cause unwanted visual glitches like a blinking balance error.
      setAndReportAmountFromPrice(newToken.price, newToken.decimals);
    }
  });

  return {
    isBaseCurrency,
    isAmountReadonly,
    inputValue: isBaseCurrency ? currencyAmountRef.current : tokenAmountRef.current,
    alternativeValue: isBaseCurrency ? tokenAmountRef.current : currencyAmountRef.current,
    switchCurrency: setIsBaseCurrency,
    onInputChange,
    onTokenChange,
  };
}

function tokenAmountToCurrencyAmount(
  amount: string | undefined,
  tokenPrice: number | undefined,
  currencyDecimals: number,
) {
  return amount && tokenPrice !== undefined
    ? Big(amount).mul(tokenPrice).round(currencyDecimals).toString()
    : undefined;
}

function currencyAmountToTokenAmount(
  amount: string | undefined,
  tokenPrice: number | undefined,
  tokenDecimals: number | undefined,
) {
  // Avoiding dividing by zero for tokens with price 0
  return amount && tokenPrice
    ? Big(amount).div(tokenPrice).round(tokenDecimals ?? DEFAULT_DECIMALS).toString()
    : undefined;
}

function tokenAmountToBigInt(amount: string | undefined, decimals: number | undefined) {
  return amount
    ? fromDecimal(amount, decimals)
    : undefined;
}

function tokenAmountFromBigInt(amount: bigint | undefined, decimals: number | undefined) {
  return amount === undefined
    ? undefined
    : toDecimal(amount, decimals);
}

/** For example, turns '1.2300' into '1.23' */
function formalizeStringAmount(amount: string | undefined) {
  if (!amount) {
    return undefined;
  }

  if (!amount.includes('.')) {
    return amount;
  }

  let end = amount.length;
  while (amount[end - 1] === '0') {
    end--;
  }
  if (amount[end - 1] === '.') {
    end--;
  }

  return amount.slice(0, end);
}
