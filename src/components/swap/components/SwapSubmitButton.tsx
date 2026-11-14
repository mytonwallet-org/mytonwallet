import React, { memo, useRef } from '../../../lib/teact/teact';

import type { DieselStatus, UserSwapToken } from '../../../global/types';
import type { SwapError } from '../helpers/resolveSwapError';
import { SwapErrorType, SwapType } from '../../../global/types';

import { ANIMATION_END_DELAY } from '../../../config';
import buildClassName from '../../../util/buildClassName';
import { formatCurrencySimple } from '../../../util/formatNumber';
import getTestId from '../../../util/getTestId';
import { resolveSwapError } from '../helpers/resolveSwapError';

import { useThrottledSignal } from '../../../hooks/useAsyncResolvers';
import useDerivedSignal from '../../../hooks/useDerivedSignal';
import useDerivedState from '../../../hooks/useDerivedState';
import useLang from '../../../hooks/useLang';

import Button from '../../ui/Button';
import Transition from '../../ui/Transition';

import styles from '../Swap.module.scss';

interface OwnProps {
  tokenIn?: UserSwapToken;
  tokenOut?: UserSwapToken;
  amountIn?: string;
  amountOut?: string;
  swapType?: SwapType;
  isEstimating?: boolean;
  isSending?: boolean;
  isNotEnoughNative?: boolean;
  isAmountGreaterThanBalance?: boolean;
  hasInsufficientFeeError?: boolean;
  dieselStatus?: DieselStatus;
  isPriceImpactError?: boolean;
  canSubmit?: boolean;
  errorType?: SwapErrorType;
  limits?: {
    fromMin?: string;
    fromMax?: string;
  };
  /** The resting caption. The swap form captions the button with "from → to" when it is absent */
  label?: string;
  /** Replaces the caption while a check outside the swap estimate fails */
  errorText?: string;
  /** The button keeps this color while disabled by an error. A bad exchange rate paints the button red regardless */
  kind?: 'green' | 'red';
}

const BUTTON_ANIMATION_DURATION = 250 + ANIMATION_END_DELAY;

function SwapSubmitButton({
  tokenIn,
  tokenOut,
  amountIn,
  amountOut,
  swapType,
  isEstimating,
  isSending,
  isNotEnoughNative,
  isAmountGreaterThanBalance = false,
  hasInsufficientFeeError = false,
  dieselStatus,
  isPriceImpactError,
  canSubmit,
  errorType,
  limits,
  label,
  errorText,
  kind,
}: OwnProps) {
  const lang = useLang();

  const shouldSendingBeVisible = isSending && swapType === SwapType.CrosschainToWallet;
  const isDisabled = !canSubmit || shouldSendingBeVisible;
  const isLoading = isEstimating || shouldSendingBeVisible;

  const isTouched = Boolean(amountIn || amountOut);
  const error = resolveSwapError({ errorType, isAmountGreaterThanBalance, hasInsufficientFeeError });

  let text: string | string[] = label ?? '$swap_from_to';

  if (errorText) {
    text = errorText;
  } else if (isTouched) {
    if (error !== undefined) {
      text = getErrorText(error) as string;
    } else if (tokenIn?.tokenAddress && isNotEnoughNative) {
      if (dieselStatus === 'pending-previous') {
        text = lang('Awaiting Previous Fee');
      } else if (dieselStatus === 'not-authorized') {
        text = lang('$authorize_token_fee_capitalized', { token: tokenIn?.symbol }) as string;
      }
    }
  }

  const textStr = Array.isArray(text) ? text.join('') : text;

  // A bad exchange rate is a warning: the button stays enabled, and the red color asks the user to think twice
  const isDestructive = kind === 'red' || (isTouched && !isEstimating && isPriceImpactError);
  const buttonKind = kind === 'green' && !isDestructive ? 'green' : undefined;

  function getErrorText(swapError: SwapError) {
    switch (swapError) {
      case 'insufficientBalance':
        return lang('Insufficient Balance');
      case 'insufficientFee':
      case SwapErrorType.NotEnoughForFee:
        return lang('Insufficient Fee');
      case SwapErrorType.UnexpectedError:
        return lang('Unexpected Error');
      case SwapErrorType.QuoteUnavailable:
        return lang('$swap_quote_unavailable');
      case SwapErrorType.ServiceUnavailable:
        return lang('$swap_service_unavailable');
      case SwapErrorType.InvalidPair:
        return lang('Unsupported Pair');
      case SwapErrorType.NotEnoughLiquidity:
        return lang('Insufficient Liquidity');
      case SwapErrorType.TooSmallAmount:
        return lang('Too Small Amount');
      case SwapErrorType.ChangellyMinSwap:
        return lang('Minimum amount', {
          value: formatCurrencySimple(limits?.fromMin ?? '0', tokenIn?.symbol ?? '', tokenIn?.decimals),
        });
      case SwapErrorType.ChangellyMaxSwap:
        return lang('Maximum amount', {
          value: formatCurrencySimple(limits?.fromMax ?? '0', tokenIn?.symbol ?? '', tokenIn?.decimals),
        });
    }
  }

  const transitionKeyRef = useRef(0);
  const render = useDerivedSignal(() => {
    const renderedText = textStr === '$swap_from_to'
      ? lang('$swap_from_to', {
        from: tokenIn?.symbol,
        icon: <i className={buildClassName('icon-chevron-right', styles.swapArrowIcon)} aria-hidden />,
        to: tokenOut?.symbol,
      })
      : textStr;

    return (
      <Transition
        name="semiFade"
        className={styles.footerButtonWrapper}
        activeKey={transitionKeyRef.current++}
      >
        {(isActive: boolean) => (
          <Button
            isPrimary
            isSubmit
            kind={buttonKind}
            className={styles.footerButton}
            testId={isActive ? getTestId('swap_continue') : undefined}
            isDisabled={isDisabled}
            isLoading={isLoading}
            isDestructive={isDestructive}
          >
            {/* The <span> is to have inline content positioning to align the icon properly */}
            <span className={styles.footerButtonInner}>{renderedText}</span>
          </Button>
        )}
      </Transition>
    );
  }, [buttonKind, isDestructive, isDisabled, isLoading, lang, textStr, tokenIn?.symbol, tokenOut?.symbol]);

  const renderThrottled = useThrottledSignal(render, BUTTON_ANIMATION_DURATION);
  const rendered = useDerivedState(renderThrottled);

  return rendered;
}

export default memo(SwapSubmitButton);
