import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type { ApiToken } from '../../api/types';
import type { ActionPayloads, AssetPairs, GlobalState, UserSwapToken } from '../../global/types';
import type { LangFn } from '../../hooks/useLang';
import type { ExplainedSwapFee } from '../../util/fee/swapFee';
import type { FeePrecision, FeeTerms } from '../../util/fee/types';
import { SwapInputSource, SwapState, SwapType } from '../../global/types';

import {
  ANIMATED_STICKER_TINY_SIZE_PX,
  ANIMATION_LEVEL_MAX,
  CHANGELLY_AML_KYC,
  CHANGELLY_PRIVACY_POLICY,
  CHANGELLY_TERMS_OF_USE,
  INIT_SWAP_ASSETS,
} from '../../config';
import { selectCurrentAccountId, selectSwapTokens, selectSwapType } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { fromDecimal, toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import { explainSwapFee, getMaxSwapAmount, isBalanceSufficientForSwap } from '../../util/fee/swapFee';
import { vibrate } from '../../util/haptics';
import { findNativeToken } from '../../util/tokens';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import { isBackgroundModeActive } from '../../hooks/useBackgroundMode';
import useDebouncedCallback from '../../hooks/useDebouncedCallback';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import FeeDetailsModal from '../common/FeeDetailsModal';
import SelectTokenButton from '../common/SelectTokenButton';
import AmountInputMaxButton from '../ui/AmountInputMaxButton';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import FeeLine from '../ui/FeeLine';
import RichNumberInput from '../ui/RichNumberInput';
import SwapSubmitButton from './components/SwapSubmitButton';
import SwapDexChooser from './SwapDexChooser';
import SwapSettingsModal, { MAX_PRICE_IMPACT_VALUE } from './SwapSettingsModal';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

interface OwnProps {
  isStatic?: boolean;
  isActive?: boolean;
}

interface StateProps {
  currentSwap: GlobalState['currentSwap'];
  tokens?: UserSwapToken[];
  swapType: SwapType;
  isSensitiveDataHidden?: true;
  pairsBySlug?: Record<string, AssetPairs>;
  isComplete?: boolean;
}

const ESTIMATE_REQUEST_INTERVAL = 1_000;
const SET_AMOUNT_DEBOUNCE_TIME = 500;

function SwapInitial({
  currentSwap: {
    tokenInSlug,
    tokenOutSlug,
    amountIn,
    amountOut,
    errorType,
    isEstimating,
    networkFee,
    realNetworkFee,
    priceImpact = 0,
    inputSource,
    limits,
    isLoading,
    dieselStatus,
    ourFee,
    ourFeePercent,
    dieselFee,
    maxAmountFromBackend,
  },
  tokens,
  isActive,
  isStatic,
  isComplete,
  swapType,
  isSensitiveDataHidden,
  pairsBySlug,
}: OwnProps & StateProps) {
  const {
    setDefaultSwapParams,
    setSwapAmountIn,
    setSwapAmountOut,
    switchSwapTokens,
    estimateSwap,
    setSwapScreen,
    setSwapCexAddress,
    authorizeDiesel,
    showToast,
  } = getActions();
  const lang = useLang();

  const inputInRef = useRef<HTMLDivElement>();
  const inputOutRef = useRef<HTMLDivElement>();

  const currentTokenInSlug = tokenInSlug ?? INIT_SWAP_ASSETS.in.slug;
  const currentTokenOutSlug = tokenOutSlug ?? INIT_SWAP_ASSETS.out.slug;

  const tokenIn = useMemo(
    () => tokens?.find((token) => token.slug === currentTokenInSlug),
    [currentTokenInSlug, tokens],
  );
  const tokenOut = useMemo(
    () => tokens?.find((token) => token.slug === currentTokenOutSlug),
    [currentTokenOutSlug, tokens],
  );

  const nativeUserTokenIn = useMemo(
    () => {
      const nativeTokenInSlug = findNativeToken(tokenIn?.chain)?.slug;
      if (!nativeTokenInSlug) return undefined;
      return tokens?.find((token) => token.slug === nativeTokenInSlug);
    },
    [tokenIn?.chain, tokens],
  );
  const nativeTokenInBalance = nativeUserTokenIn?.amount ?? 0n;

  const amountInBigint = amountIn && tokenIn ? fromDecimal(amountIn, tokenIn.decimals) : undefined;
  const amountOutBigint = amountOut && tokenOut ? fromDecimal(amountOut, tokenOut.decimals) : undefined;
  const balanceIn = tokenIn?.amount ?? 0n;

  const explainedFee = useMemo(
    () => explainSwapFee({
      swapType,
      tokenInSlug,
      networkFee,
      realNetworkFee,
      ourFee,
      dieselStatus,
      dieselFee,
      nativeTokenInBalance,
    }),
    [swapType, tokenInSlug, networkFee, realNetworkFee, ourFee, dieselStatus, dieselFee, nativeTokenInBalance],
  );

  const maxAmountFromBackendBigint = maxAmountFromBackend && tokenIn
    ? fromDecimal(maxAmountFromBackend, tokenIn.decimals)
    : undefined;

  const maxAmount = getMaxSwapAmount({
    swapType,
    tokenInBalance: balanceIn,
    tokenIn,
    fullNetworkFee: explainedFee.fullFee?.networkTerms,
    ourFeePercent,
    maxAmountFromBackend: maxAmountFromBackendBigint,
  });

  // Note: this constant has 3 distinct meaningful values
  const isEnoughBalance = isBalanceSufficientForSwap({
    swapType,
    tokenInBalance: balanceIn,
    tokenIn,
    fullNetworkFee: explainedFee.fullFee?.networkTerms,
    amountIn,
    nativeTokenInBalance,
    maxAmountFromBackend: maxAmountFromBackendBigint,
  });

  const networkFeeBigint = networkFee !== undefined && nativeUserTokenIn
    ? fromDecimal(networkFee, nativeUserTokenIn.decimals)
    : 0n;
  const isEnoughNative = nativeTokenInBalance >= networkFeeBigint;

  const isDieselNotAuthorized = explainedFee.isGasless && dieselStatus === 'not-authorized';

  const canSubmit = isDieselNotAuthorized || (
    (amountInBigint ?? 0n) > 0n
    && (amountOutBigint ?? 0n) > 0n
    && isEnoughBalance
    && (!explainedFee.isGasless || dieselStatus === 'available' || dieselStatus === 'stars-fee')
    && !isEstimating
    && errorType === undefined
  );

  const hasAmountInError = amountInBigint !== undefined && maxAmount !== undefined && amountInBigint > maxAmount;
  const amountOutValue = (amountInBigint ?? 0n) <= 0n && inputSource === SwapInputSource.In
    ? ''
    : amountOut?.toString();
  const isAmountGreaterThanBalance = balanceIn !== undefined && amountInBigint !== undefined
    && amountInBigint > balanceIn;
  const hasInsufficientFeeError = isEnoughBalance === false && !isAmountGreaterThanBalance
    && dieselStatus !== 'not-authorized' && dieselStatus !== 'pending-previous';

  const isPriceImpactError = priceImpact >= MAX_PRICE_IMPACT_VALUE;
  const isCrosschain = swapType !== SwapType.OnChain;

  const [isBuyAmountInputDisabled, handleBuyAmountInputClick] = useReverseProhibited(
    isCrosschain,
    pairsBySlug,
    currentTokenInSlug,
    currentTokenOutSlug,
    showToast,
    lang,
  );

  const handleEstimateSwap = useLastCallback(() => {
    if ((!isActive || isBackgroundModeActive()) && !isEstimating) return;

    estimateSwap();
  });

  const debounceSetAmountIn = useDebouncedCallback(
    setSwapAmountIn, [setSwapAmountIn], SET_AMOUNT_DEBOUNCE_TIME, true,
  );
  const debounceSetAmountOut = useDebouncedCallback(
    setSwapAmountOut, [setSwapAmountOut], SET_AMOUNT_DEBOUNCE_TIME, true,
  );

  const [currentSubModal, openSettingsModal, openFeeModal, closeSubModal] = useSubModals(explainedFee);

  useEffect(() => {
    if (!tokenInSlug && !tokenOutSlug) {
      setDefaultSwapParams();
    }
  }, [tokenInSlug, tokenOutSlug]);

  useEffect(() => {
    if (isEstimating) {
      handleEstimateSwap();
    }

    const intervalId = setInterval(handleEstimateSwap, ESTIMATE_REQUEST_INTERVAL);
    return () => clearInterval(intervalId);
  }, [isEstimating]);

  useEffect(() => {
    if (isComplete) clearForm();
  }, [isComplete]);

  function clearForm() {
    setSwapAmountIn({ amount: undefined, isMaxAmount: false });
    setSwapAmountOut({ amount: undefined });
  }

  const handleAmountInChange = useLastCallback(
    (amount: string | undefined) => {
      debounceSetAmountIn({ amount: amount || undefined });
    },
  );

  const handleSelectTokenInModalOpen = useLastCallback(() => {
    setSwapScreen({ state: SwapState.SelectTokenFrom });
  });

  const handleSelectTokenOutModalOpen = useLastCallback(() => {
    setSwapScreen({ state: SwapState.SelectTokenTo });
  });

  const handleAmountOutChange = useLastCallback(
    (amount: string | undefined) => {
      debounceSetAmountOut({ amount: amount || undefined });
    },
  );

  const handleMaxAmountClick = useLastCallback(() => {
    if (maxAmount === undefined) {
      return;
    }

    void vibrate();

    const amount = toDecimal(maxAmount, tokenIn!.decimals);
    setSwapAmountIn({ amount, isMaxAmount: true });
  });

  const handleSubmit = useLastCallback((e: React.FormEvent | React.UIEvent) => {
    stopEvent(e);

    if (!canSubmit) {
      return;
    }

    if (isDieselNotAuthorized) {
      authorizeDiesel();
      return;
    }

    void vibrate();

    if (swapType === SwapType.CrosschainFromWallet) {
      setSwapCexAddress({ toAddress: '' });
      setSwapScreen({ state: SwapState.Blockchain });
    } else {
      setSwapScreen({ state: SwapState.Password });
    }
  });

  const handleSwitchTokens = useLastCallback(() => {
    void vibrate();
    switchSwapTokens();
  });

  function renderBalance() {
    return (
      <AmountInputMaxButton
        maxAmount={maxAmount ?? balanceIn}
        token={tokenIn}
        isSensitiveDataHidden={isSensitiveDataHidden}
        onAmountClick={handleMaxAmountClick}
      />
    );
  }

  function renderFee() {
    const shouldShow = (amountIn && amountOut) // We aim to synchronize the disappearing of the fee with the DEX chooser disappearing
      || ((amountIn || amountOut) && errorType); // Without this sub-condition the fee wouldn't be shown when the amount is outside the Changelly limits

    let terms: FeeTerms | undefined;
    let precision: FeePrecision = 'exact';

    if (shouldShow) {
      const actualFee = hasInsufficientFeeError ? explainedFee.fullFee : undefined;
      if (actualFee) {
        ({ terms, precision } = actualFee);
      }
    }

    return (
      <FeeLine
        isStatic={isStatic}
        terms={terms}
        token={tokenIn}
        precision={precision}
        keepDetailsButtonWithoutFee
        onDetailsClick={openSettingsModal}
        className={styles.feeLine}
      />
    );
  }

  function renderPriceImpactWarning() {
    if (!priceImpact || !isPriceImpactError || isCrosschain) {
      return undefined;
    }

    return (
      <div
        className={buildClassName(styles.priceImpact, isStatic && styles.priceImpactStatic)}
        onClick={openSettingsModal}
      >
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.run}
          previewUrl={ANIMATED_STICKERS_PATHS.runPreview}
          noLoop={false}
          nonInteractive
          size={ANIMATED_STICKER_TINY_SIZE_PX}
          className={styles.priceImpactSticker}
        />
        <div className={styles.priceImpactContent}>
          <span className={styles.priceImpactTitle}>
            {lang('The exchange rate is below market value!', { value: `${priceImpact}%` })}
            <i className={buildClassName(styles.priceImpactArrow, 'icon-chevron-right')} aria-hidden />
          </span>
          <span className={styles.priceImpactDescription}>
            {lang('We do not recommend to perform an exchange, try to specify a lower amount.')}
          </span>
        </div>
      </div>
    );
  }

  function renderChangellyInfo() {
    if (!isCrosschain) {
      return undefined;
    }

    return (
      <div className={buildClassName(styles.changellyInfo, isStatic && styles.changellyInfoStatic)}>
        <span className={styles.changellyInfoTitle}>
          <i className={buildClassName('icon-changelly', styles.changellyIcon)} aria-hidden />
          {lang('Cross-chain exchange provided by Changelly')}
        </span>
        <span className={styles.changellyInfoDescription}>
          {
            lang('$swap_changelly_agreement_message', {
              terms: (
                <a href={CHANGELLY_TERMS_OF_USE} target="_blank" rel="noreferrer">
                  {lang('$swap_changelly_terms_of_use')}
                </a>
              ),
              policy: (
                <a href={CHANGELLY_PRIVACY_POLICY} target="_blank" rel="noreferrer">
                  {lang('$swap_changelly_privacy_policy')}
                </a>
              ),
              kyc: <a href={CHANGELLY_AML_KYC} target="_blank" rel="noreferrer">Changelly AML/KYC</a>,
            })
          }
        </span>
      </div>
    );
  }

  return (
    <>
      <form className={isStatic ? undefined : modalStyles.transitionContent} onSubmit={handleSubmit}>
        <div className={styles.content}>
          <div ref={inputInRef} className={styles.inputContainer}>
            {renderBalance()}
            <RichNumberInput
              id="swap-sell"
              labelText={lang('You sell')}
              className={styles.amountInput}
              hasError={hasAmountInError}
              value={amountIn?.toString()}
              isLoading={isEstimating && inputSource === SwapInputSource.Out}
              onChange={handleAmountInChange}
              onPressEnter={handleSubmit}
              decimals={tokenIn?.decimals}
              labelClassName={styles.inputLabel}
              inputClassName={styles.amountInputInner}
              cornerClassName={buildClassName(styles.swapCornerTop, isStatic && styles.swapCornerStaticTop)}
              isStatic={isStatic}
            >
              <SelectTokenButton token={tokenIn as ApiToken} onClick={handleSelectTokenInModalOpen} />
            </RichNumberInput>
          </div>

          <div className={buildClassName(styles.swapButtonWrapper, isStatic && styles.swapButtonWrapperStatic)}>
            <AnimatedArrows onClick={handleSwitchTokens} />
          </div>

          <div ref={inputOutRef} className={styles.inputContainer}>
            <RichNumberInput
              id="swap-buy"
              labelText={lang('You buy')}
              className={styles.amountInputBuy}
              value={amountOutValue}
              isLoading={isEstimating && inputSource === SwapInputSource.In}
              disabled={isBuyAmountInputDisabled}
              onChange={handleAmountOutChange}
              onPressEnter={handleSubmit}
              onInputClick={handleBuyAmountInputClick}
              decimals={tokenOut?.decimals}
              labelClassName={styles.inputLabel}
              inputClassName={styles.amountInputInner}
              cornerClassName={buildClassName(styles.swapCornerBottom, isStatic && styles.swapCornerStaticBottom)}
              isStatic={isStatic}
            >
              <SelectTokenButton token={tokenOut as ApiToken} onClick={handleSelectTokenOutModalOpen} />
            </RichNumberInput>
          </div>
        </div>
        <SwapDexChooser tokenIn={tokenIn} tokenOut={tokenOut} isStatic={isStatic} />

        <div className={buildClassName(styles.footerBlock, isStatic && styles.footerBlockStatic)}>
          {renderFee()}
          {renderPriceImpactWarning()}
          {renderChangellyInfo()}

          <SwapSubmitButton
            tokenIn={tokenIn}
            tokenOut={tokenOut}
            amountIn={amountIn}
            amountOut={amountOut}
            swapType={swapType}
            isEstimating={isEstimating}
            isNotEnoughNative={!isEnoughNative}
            nativeToken={nativeUserTokenIn}
            dieselStatus={dieselStatus}
            isSending={isLoading}
            isPriceImpactError={isPriceImpactError}
            canSubmit={canSubmit}
            errorType={errorType}
            limits={limits}
          />
        </div>
      </form>
      <SwapSettingsModal
        isOpen={currentSubModal === 'settings'}
        onClose={closeSubModal}
        onNetworkFeeClick={openFeeModal}
        showFullNetworkFee={hasInsufficientFeeError}
      />
      <FeeDetailsModal
        isOpen={currentSubModal === 'feeDetails'}
        onClose={closeSubModal}
        fullFee={explainedFee.fullFee?.networkTerms}
        realFee={explainedFee.realFee?.networkTerms}
        realFeePrecision={explainedFee.realFee?.precision}
        excessFee={explainedFee.excessFee}
        excessFeePrecision="approximate"
        token={tokenIn}
      />
    </>
  );
}

export default memo(
  withGlobal<OwnProps>(
    (global): StateProps => {
      return {
        currentSwap: global.currentSwap,
        tokens: selectSwapTokens(global),
        swapType: selectSwapType(global),
        isSensitiveDataHidden: global.settings.isSensitiveDataHidden,
        pairsBySlug: global.swapPairs?.bySlug,
        isComplete: global.currentSwap.state === SwapState.Complete,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(SwapInitial),
);

function useReverseProhibited(
  isCrosschain: boolean,
  pairsBySlug: Record<string, AssetPairs> | undefined,
  currentTokenInSlug: string,
  currentTokenOutSlug: string,
  showToast: (arg: ActionPayloads['showToast']) => void,
  lang: LangFn,
) {
  const isReverseProhibited = isCrosschain
    || pairsBySlug?.[currentTokenInSlug]?.[currentTokenOutSlug]?.isReverseProhibited;
  const isBuyAmountInputDisabled = isReverseProhibited;

  const handleBuyAmountInputClick = useMemo(() => {
    return isReverseProhibited
      ? () => {
        void vibrate();
        showToast({ message: lang('$swap_reverse_prohibited') });
      }
      : undefined;
  }, [isReverseProhibited, lang, showToast]);

  return [isBuyAmountInputDisabled, handleBuyAmountInputClick] as const;
}

function AnimatedArrows({ onClick }: { onClick?: NoneToVoidFunction }) {
  const animationLevel = getGlobal().settings.animationLevel;
  const shouldAnimate = (animationLevel === ANIMATION_LEVEL_MAX);
  const [hasAnimation, startAnimation, stopAnimation] = useFlag(false);

  const handleClick = useLastCallback(() => {
    if (shouldAnimate) {
      startAnimation();
      window.setTimeout(() => {
        stopAnimation();
      }, 350);
    }

    onClick?.();
  });

  function renderArrow(isInverted?: boolean) {
    return (
      <div className={buildClassName(styles.arrowContainer, isInverted && styles.arrowContainerInverted)}>
        <div className={styles.arrow}>
          <i className="icon-arrow-up-swap" aria-hidden />
        </div>
        <div className={buildClassName(styles.arrowOld, hasAnimation && styles.animateDisappear)}>
          <i className="icon-arrow-up-swap" aria-hidden />
        </div>
        <div className={buildClassName(styles.arrowNew, hasAnimation && styles.animateAppear)}>
          <i className="icon-arrow-up-swap" aria-hidden />
        </div>
      </div>
    );
  }

  return (
    <div className={styles.swapButton} onClick={handleClick}>
      {renderArrow()}
      {renderArrow(true)}
    </div>
  );
}

function useSubModals(explainedFee: ExplainedSwapFee) {
  const isFeeModalAvailable = explainedFee.realFee?.precision !== 'exact';
  const [currentModal, setCurrentModal] = useState<'settings' | 'feeDetails'>();

  const openSettings = useLastCallback(() => setCurrentModal('settings'));
  const openFeeDetailsIfAvailable = useMemo(
    () => (isFeeModalAvailable ? () => setCurrentModal('feeDetails') : undefined),
    [isFeeModalAvailable],
  );
  const close = useLastCallback(() => setCurrentModal(undefined));

  return [currentModal, openSettings, openFeeDetailsIfAvailable, close] as const;
}
