import { useEffect, useLayoutEffect, useRef, useState } from '../../../lib/teact/teact';

import useLastCallback from '../../../hooks/useLastCallback';
import {
  currencyAmountToTokenAmount,
  formalizeStringAmount,
  tokenAmountToCurrencyAmount,
} from '../../ui/hooks/useAmountInputState';

interface TradeAmountFieldInput {
  /** The amount stored globally, in the screen token */
  tradeAmount?: string;
  isTokenUnit: boolean;
  /** The screen token price in the field currency */
  price: number;
  currencyDecimals: number;
  tokenDecimals?: number;
  onAmountChange: (amount?: string) => void;
}

interface Amounts {
  token?: string;
  currency?: string;
  /** Whether `token` is the source and `currency` is only its rounded display, rather than the other way round */
  isTokenSource?: boolean;
}

const SET_AMOUNT_DEBOUNCE_TIME = 500;
const EMPTY_AMOUNTS: Amounts = {};

/**
 * Keeps the text of the amount field in both units: the screen token and the fiat currency.
 *
 * What the user types is sent to the global state with a delay, so that the swap is not re-estimated on every
 * keystroke. In the other direction, the global `tradeAmount` is copied into the field only when it was changed
 * outside the field: by a percent button, the clear button or an account switch.
 */
export default function useTradeAmountField({
  tradeAmount,
  isTokenUnit,
  price,
  currencyDecimals,
  tokenDecimals,
  onAmountChange,
}: TradeAmountFieldInput) {
  const [amounts, setAmounts] = useState(EMPTY_AMOUNTS);
  // The last token amount handed over to the global state, or received from it
  const knownTokenAmountRef = useRef<string | undefined>();
  const emitTimeoutRef = useRef<number | undefined>();

  const cancelPendingAmount = useLastCallback(() => {
    window.clearTimeout(emitTimeoutRef.current);
    emitTimeoutRef.current = undefined;
  });

  const emitAmount = useLastCallback((tokenAmount: string | undefined, isImmediate = false) => {
    cancelPendingAmount();
    knownTokenAmountRef.current = tokenAmount;

    if (isImmediate) {
      onAmountChange(tokenAmount);
      return;
    }

    emitTimeoutRef.current = window.setTimeout(() => {
      emitTimeoutRef.current = undefined;
      onAmountChange(tokenAmount);
    }, SET_AMOUNT_DEBOUNCE_TIME);
  });

  const applyTokenAmount = useLastCallback((tokenAmount: string | undefined) => {
    cancelPendingAmount();
    knownTokenAmountRef.current = tokenAmount;
    setAmounts({
      token: tokenAmount,
      currency: tokenAmountToCurrencyAmount(tokenAmount, price, currencyDecimals),
      isTokenSource: true,
    });
  });

  // A new `tradeAmount` and a new `price` are handled by the same effect on purpose. If they arrived in the same
  // render and were handled by two effects, the price effect would recalculate the field from the text of the
  // previous render and overwrite the amount that has just come from the global state.
  useLayoutEffect(() => {
    if (formalizeStringAmount(tradeAmount) !== formalizeStringAmount(knownTokenAmountRef.current)) {
      applyTokenAmount(tradeAmount);
      return;
    }

    // A token amount that was typed in the token unit or set from outside (a percent button, the global state)
    // stays exact, and only its fiat text follows the price. Rebuilding it from the fiat text would lose the
    // precision beyond the fiat decimals and, with it, the Max flag of the swap. Typed fiat is what the user
    // meant, so there the token amount follows the price instead.
    if (isTokenUnit || amounts.isTokenSource) {
      const currencyAmount = tokenAmountToCurrencyAmount(amounts.token, price, currencyDecimals);
      if (currencyAmount !== amounts.currency) {
        setAmounts({ ...amounts, currency: currencyAmount });
      }
      return;
    }

    const tokenAmount = currencyAmountToTokenAmount(amounts.currency, price, tokenDecimals);
    if (tokenAmount !== formalizeStringAmount(amounts.token)) {
      setAmounts({ ...amounts, token: tokenAmount });
      emitAmount(tokenAmount, true);
    }
  }, [tradeAmount, price, currencyDecimals, tokenDecimals]); // eslint-disable-line react-hooks-static-deps/exhaustive-deps

  // A pending amount must reach the global state even if the screen is left for the asset picker
  useEffect(() => () => {
    if (emitTimeoutRef.current === undefined) return;

    cancelPendingAmount();
    onAmountChange(knownTokenAmountRef.current);
  }, []); // eslint-disable-line react-hooks-static-deps/exhaustive-deps

  const handleInputChange = useLastCallback((value?: string) => {
    value ||= undefined;

    const tokenAmount = isTokenUnit ? value : currencyAmountToTokenAmount(value, price, tokenDecimals);
    const currencyAmount = isTokenUnit ? tokenAmountToCurrencyAmount(value, price, currencyDecimals) : value;

    setAmounts({ token: tokenAmount, currency: currencyAmount, isTokenSource: isTokenUnit });
    emitAmount(tokenAmount);
  });

  return {
    inputValue: isTokenUnit ? amounts.token : amounts.currency,
    tokenAmount: amounts.token,
    currencyAmount: amounts.currency,
    handleInputChange,
    applyTokenAmount,
    cancelPendingAmount,
  };
}
