import React, { memo, useEffect, useMemo, useRef, useState } from '../../lib/teact/teact';
import { getActions, getGlobal, withGlobal } from '../../global';

import type { ApiSwapCexLabel, ApiToken } from '../../api/types';
import type { ActionPayloads, AppTheme, AssetPairs, GlobalState, Theme, UserSwapToken } from '../../global/types';
import type { LangFn } from '../../hooks/useLang';
import type { ExplainedSwapFee } from '../../util/fee/swapFee';
import type { FeePrecision, FeeTerms } from '../../util/fee/types';
import { SwapInputSource, SwapState, SwapType } from '../../global/types';

import {
  ANIMATED_STICKER_TINY_SIZE_PX,
  ANIMATION_LEVEL_MAX,
} from '../../config';
import { selectCurrentAccountId, selectSwapTokens, selectSwapType } from '../../global/selectors';
import buildClassName from '../../util/buildClassName';
import { toDecimal } from '../../util/decimals';
import { stopEvent } from '../../util/domEvents';
import { vibrate } from '../../util/haptics';
import { isSwapReverseProhibited } from '../../util/swap/isSwapReverseProhibited';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useAppTheme from '../../hooks/useAppTheme';
import useDebouncedCallback from '../../hooks/useDebouncedCallback';
import useFlag from '../../hooks/useFlag';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';
import useSwapEstimatePolling from './hooks/useSwapEstimatePolling';
import useSwapFormState from './hooks/useSwapFormState';

import FeeDetailsModal from '../common/FeeDetailsModal';
import SelectTokenButton from '../common/SelectTokenButton';
import AmountInputMaxButton from '../ui/AmountInputMaxButton';
import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import FeeLine from '../ui/FeeLine';
import RichNumberInput from '../ui/RichNumberInput';
import CexLegalDescription from './components/CexLegalDescription';
import SwapHint from './components/SwapHint';
import SwapSubmitButton from './components/SwapSubmitButton';
import SwapSettingsModal from './SwapSettingsModal';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Swap.module.scss';

import changellyLogoDark from '../../assets/swap_provider_changelly_dark.svg';
import changellyLogoLight from '../../assets/swap_provider_changelly_light.svg';
import nearIntentsLogoDark from '../../assets/swap_provider_near_dark.svg';
import nearIntentsLogoLight from '../../assets/swap_provider_near_light.svg';

interface OwnProps {
  isActive?: boolean;
}

interface StateProps {
  currentSwap: GlobalState['currentSwap'];
  tokens?: UserSwapToken[];
  swapType: SwapType;
  isSensitiveDataHidden?: true;
  pairsBySlug?: Record<string, AssetPairs>;
  isComplete?: boolean;
  theme: Theme;
}

const SET_AMOUNT_DEBOUNCE_TIME = 500;

const CEX_PROVIDER_LOGOS: Record<ApiSwapCexLabel, Record<AppTheme, string> & { width: number; height: number }> = {
  changelly: {
    light: changellyLogoLight, dark: changellyLogoDark, width: 87, height: 18,
  },
  'near-intents': {
    light: nearIntentsLogoLight, dark: nearIntentsLogoDark, width: 81, height: 11,
  },
};

function SwapInitial({
  currentSwap,
  currentSwap: {
    tokenInSlug,
    tokenOutSlug,
    amountIn,
    amountOut,
    errorType,
    isEstimating,
    priceImpact = 0,
    inputSource,
    limits,
    isLoading,
    dieselStatus,
    currentCexLabel,
    currentCexProviderName,
    currentCexTermsOfUseUrl,
    currentCexPrivacyPolicyUrl,
    currentCexAmlKycPolicyUrl,
    swapHint,
  },
  tokens,
  isActive,
  isComplete,
  swapType,
  isSensitiveDataHidden,
  pairsBySlug,
  theme,
}: OwnProps & StateProps) {
  const {
    setDefaultSwapParams,
    setSwapAmountIn,
    setSwapAmountOut,
    switchSwapTokens,
    setSwapScreen,
    setSwapCexAddress,
    setSwapTokenOut,
    authorizeDiesel,
    showToast,
  } = getActions();
  const lang = useLang();
  const appTheme = useAppTheme(theme);

  const inputInRef = useRef<HTMLDivElement>();
  const inputOutRef = useRef<HTMLDivElement>();

  const {
    currentTokenInSlug,
    currentTokenOutSlug,
    tokenIn,
    tokenOut,
    nativeUserTokenIn,
    balanceIn,
    explainedFee,
    maxAmount,
    isEnoughNative,
    isDieselNotAuthorized,
    canSubmit,
    hasAmountInError,
    amountOutValue,
    hasInsufficientFeeError,
    isPriceImpactError,
    isCrosschain,
  } = useSwapFormState(currentSwap, tokens, swapType);

  const handleIntermediateHintClick = useLastCallback((tokenSlug: string) => {
    setSwapTokenOut({ tokenSlug });
  });

  const [isBuyAmountInputDisabled, handleBuyAmountInputClick] = useReverseProhibited(
    swapType,
    pairsBySlug,
    currentTokenInSlug,
    currentTokenOutSlug,
    showToast,
    lang,
  );

  useSwapEstimatePolling(currentSwap, isActive);

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

    vibrate();

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

    vibrate();

    if (swapType === SwapType.CrosschainFromWallet) {
      setSwapCexAddress({ toAddress: '' });
      setSwapScreen({ state: SwapState.Blockchain });
    } else {
      setSwapScreen({ state: SwapState.Password });
    }
  });

  const handleSwitchTokens = useLastCallback(() => {
    vibrate();
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
    const shouldShow = (amountIn && amountOut)
      || ((amountIn || amountOut) && errorType); // Without this sub-condition the fee wouldn't be shown when the amount is outside the CEX limits

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
      <div className={styles.priceImpact} onClick={openSettingsModal}>
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

  function renderCexProviderInfo() {
    if (!isCrosschain || !currentCexLabel) {
      return undefined;
    }

    const providerName = currentCexProviderName;
    if (!providerName) {
      return undefined;
    }

    // `cexLabel` comes from the backend, so it can name a provider this app version has no logo for
    const logo = CEX_PROVIDER_LOGOS[currentCexLabel];
    const provider = logo ? (
      <img
        src={logo[appTheme]}
        alt={providerName}
        width={logo.width}
        height={logo.height}
        className={styles.providerLogo}
      />
    ) : providerName;

    return (
      <div className={styles.providerInfo}>
        <span className={styles.providerInfoTitle}>
          {lang('Cross-chain exchange provided by %provider%', { provider })}
        </span>
        <CexLegalDescription
          providerName={providerName}
          termsOfUseUrl={currentCexTermsOfUseUrl}
          privacyPolicyUrl={currentCexPrivacyPolicyUrl}
          amlKycPolicyUrl={currentCexAmlKycPolicyUrl}
          className={styles.providerInfoDescription}
        />
      </div>
    );
  }

  return (
    <>
      <form className={modalStyles.transitionContent} onSubmit={handleSubmit}>
        <div className={styles.content}>
          <div ref={inputInRef} className={styles.inputContainer}>
            {renderBalance()}
            <RichNumberInput
              id="swap-sell"
              labelText={lang('You Sell')}
              className={styles.amountInput}
              hasError={hasAmountInError}
              value={amountIn?.toString()}
              isLoading={isEstimating && inputSource === SwapInputSource.Out}
              onChange={handleAmountInChange}
              onPressEnter={handleSubmit}
              decimals={tokenIn?.decimals}
              labelClassName={styles.inputLabel}
              cornerClassName={styles.swapCornerTop}
            >
              <SelectTokenButton token={tokenIn as ApiToken} onClick={handleSelectTokenInModalOpen} />
            </RichNumberInput>
          </div>

          <div className={styles.swapButtonWrapper}>
            <AnimatedArrows onClick={handleSwitchTokens} />
          </div>

          <div ref={inputOutRef} className={styles.inputContainer}>
            <RichNumberInput
              id="swap-buy"
              labelText={lang('You Buy')}
              className={styles.amountInputBuy}
              value={amountOutValue}
              isLoading={isEstimating && inputSource === SwapInputSource.In}
              disabled={isBuyAmountInputDisabled}
              onChange={handleAmountOutChange}
              onPressEnter={handleSubmit}
              onInputClick={handleBuyAmountInputClick}
              decimals={tokenOut?.decimals}
              labelClassName={styles.inputLabel}
              cornerClassName={styles.swapCornerBottom}
            >
              <SelectTokenButton token={tokenOut as ApiToken} onClick={handleSelectTokenOutModalOpen} />
            </RichNumberInput>
          </div>
        </div>
        <div className={styles.footerBlock}>
          {renderFee()}
          {renderPriceImpactWarning()}
          {errorType !== undefined && swapHint && (
            <SwapHint
              hint={swapHint}
              tokens={tokens}
              tokenOut={tokenOut}
              onIntermediateClick={handleIntermediateHintClick}
            />
          )}
          {renderCexProviderInfo()}

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
        theme: global.settings.theme,
      };
    },
    (global, _, stickToFirst) => stickToFirst(selectCurrentAccountId(global)),
  )(SwapInitial),
);

function useReverseProhibited(
  swapType: SwapType,
  pairsBySlug: Record<string, AssetPairs> | undefined,
  currentTokenInSlug: string,
  currentTokenOutSlug: string,
  showToast: (arg: ActionPayloads['showToast']) => void,
  lang: LangFn,
) {
  const isReverseProhibited = isSwapReverseProhibited(currentTokenInSlug, currentTokenOutSlug, swapType, pairsBySlug);
  const isBuyAmountInputDisabled = isReverseProhibited;

  const handleBuyAmountInputClick = useMemo(() => {
    return isReverseProhibited
      ? () => {
        vibrate();
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
