import type { RefObject, TeactNode } from '../../lib/teact/teact';
import { useMemo } from '../../lib/teact/teact';
import React, { memo, useEffect, useRef } from '../../lib/teact/teact';

import type { ApiTokenWithPrice } from '../../api/types';
import type { AmountInputStateOutput } from './hooks/useAmountInputState';
import type { TokenWithId } from './TokenDropdown';

import { CURRENCIES } from '../../config';
import buildClassName from '../../util/buildClassName';
import { formatCurrency, getShortCurrencySymbol } from '../../util/formatNumber';
import { setCancellableTimeout } from '../../util/schedulers';
import { SEC } from '../../api/constants';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useUniqueId from '../../hooks/useUniqueId';

import AmountInputMaxButton from './AmountInputMaxButton';
import RichNumberInput, { focusAtTheEnd } from './RichNumberInput';
import TokenDropdown from './TokenDropdown';
import Transition from './Transition';

import styles from './AmountInput.module.scss';

export type AmountInputToken = TokenWithId & Pick<ApiTokenWithPrice, 'decimals'> & { price: number };

interface OwnProps extends AmountInputStateOutput {
  /** Expressed in `token` regardless of `isBaseCurrency` */
  ref?: RefObject<HTMLInputElement | undefined>;
  maxAmount?: bigint;
  token: AmountInputToken | undefined;
  allTokens?: AmountInputToken[];
  isStatic?: boolean;
  hasError: boolean;
  isMultichainAccount?: boolean;
  isSensitiveDataHidden?: true;
  isMaxAmountLoading?: boolean;
  /** If true, the max amount label will say "All" instead of "Max" and all the amount digits will be shown (made for unstaking) */
  isMaxAmountAllMode?: boolean;
  labelText?: TeactNode;
  renderBottomRight: (className: string) => TeactNode;
  onPressEnter?: (e: React.KeyboardEvent<HTMLDivElement>) => void;
}

function AmountInput({
  ref,
  isBaseCurrency,
  inputValue,
  alternativeValue,
  baseCurrency,
  maxAmount,
  token,
  allTokens,
  isStatic,
  hasError,
  isMultichainAccount,
  isSensitiveDataHidden,
  isMaxAmountLoading,
  isMaxAmountAllMode,
  renderBottomRight,
  isAmountReadonly,
  labelText,
  onTokenChange,
  onPressEnter,
  onInputChange,
  onMaxAmountClick,
  onAlternativeAmountClick,
}: OwnProps) {
  const lang = useLang();
  const transitionKey = isBaseCurrency ? 0 : 1;
  const { inputId, onInputFocus, onInputBlur, onClick: keepInputFocus } = useKeepInputFocus(transitionKey);
  const availableTokens = useMemo(() => {
    if (isAmountReadonly && token) {
      return [token];
    }

    return allTokens;
  }, [allTokens, isAmountReadonly, token]);

  const handleMaxAmountClick = useLastCallback(() => {
    onMaxAmountClick(maxAmount);
    keepInputFocus();
  });

  function renderBalance() {
    return (
      <AmountInputMaxButton
        maxAmount={maxAmount}
        token={token}
        isLoading={isMaxAmountLoading}
        isAllMode={isMaxAmountAllMode}
        isSensitiveDataHidden={isSensitiveDataHidden}
        isDisabled={isAmountReadonly}
        onAmountClick={handleMaxAmountClick}
      />
    );
  }

  function renderInput() {
    let prefix: string | undefined;
    let suffix: string | undefined;

    if (isBaseCurrency) {
      const { shortSymbol } = CURRENCIES[baseCurrency];
      if (shortSymbol) {
        prefix = shortSymbol;
      } else {
        suffix = baseCurrency;
      }
    }

    return (
      <RichNumberInput
        id={inputId}
        ref={ref}
        hasError={hasError}
        value={inputValue}
        labelText={labelText ?? lang('Amount')}
        decimals={isBaseCurrency ? CURRENCIES[baseCurrency].decimals : token?.decimals}
        className={styles.input}
        isStatic={isStatic}
        prefix={prefix}
        suffix={suffix}
        disabled={isAmountReadonly}
        onChange={onInputChange}
        onPressEnter={onPressEnter}
        onFocus={onInputFocus}
        onBlur={onInputBlur}
      >
        {renderTokens()}
      </RichNumberInput>
    );
  }

  function renderTokens() {
    return (
      <TokenDropdown<AmountInputToken>
        selectedToken={token}
        allTokens={availableTokens}
        isInMode={isBaseCurrency}
        isMultichainAccount={isMultichainAccount}
        onChange={onTokenChange}
      />
    );
  }

  function renderAlternativeAmount() {
    const symbol = isBaseCurrency
      ? (token?.symbol ?? '')
      : getShortCurrencySymbol(baseCurrency);

    const onClick = () => {
      onAlternativeAmountClick();
      keepInputFocus();
    };

    // The main reason to use <button> is preventing the comment type selector (which is also a <button>) from hijacking
    // the clicks on touch screens.
    return (
      <button
        type="button"
        disabled={isAmountReadonly}
        className={styles.alternative}
        onClick={isAmountReadonly ? undefined : onClick}
      >
        ≈&thinsp;
        {formatCurrency(alternativeValue ?? 0, symbol, undefined, true)}
        {!isAmountReadonly && <i className={buildClassName(styles.alternative__icon, 'icon-switch')} aria-hidden />}
      </button>
    );
  }

  return (
    <Transition
      activeKey={transitionKey}
      name="semiFade"
      shouldCleanup
      className={styles.container}
      slideClassName={styles.container__slide}
    >
      {renderBalance()}
      {renderInput()}
      <div className={styles.bottom}>
        {renderAlternativeAmount()}
        {renderBottomRight(styles.bottom__right)}
      </div>
    </Transition>
  );
}

export default memo(AmountInput);

/**
 * Clicking the currency switch button un-focuses the input. This creates a bad UX with virtual keyboard.
 * To improve the UX, we focus the input back when the user clicks the currency switch button.
 * We focus only if the input was focused before the click to avoid forcing the virtual keyboard open on a cold tap.
 */
function useKeepInputFocus(transitionKey: number) {
  const inputId = `${useUniqueId()}_${transitionKey}`;
  const isFocused = useRef(false);
  const cancelFocusTimer = useRef<NoneToVoidFunction>();
  const inputFocusPersistDuration = 0.5 * SEC;

  const onInputFocus = useLastCallback(() => {
    cancelFocusTimer.current?.();
    isFocused.current = true;
  });

  const onInputBlur = useLastCallback(() => {
    cancelFocusTimer.current?.();
    cancelFocusTimer.current = setCancellableTimeout(inputFocusPersistDuration, () => {
      isFocused.current = false;
    });
  });

  const onClick = () => {
    if (isFocused.current) {
      focusAtTheEnd(inputId); // To keep the virtual keyboard open
    }
  };

  // The input element is replaced as a result of the transition, so we need to focus the new input
  useEffect(() => {
    if (isFocused.current) {
      focusAtTheEnd(inputId);
    }
  }, [transitionKey]); // eslint-disable-line react-hooks-static-deps/exhaustive-deps

  return { inputId, onInputFocus, onInputBlur, onClick };
}
